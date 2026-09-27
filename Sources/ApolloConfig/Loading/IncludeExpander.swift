import Foundation
import ApolloBase
import ApolloKDL

private final class ExpansionState {
    var diagnostics: [Diagnostic] = []
    var filesOrdered: [URL] = []
    var seenFiles: Set<String> = []
    var insertions = 0
    var insertionLimitHit = false
    var nodeCount = 0
    var budgetHit = false
    var depthLimitHit = false
}

private struct IncludeTarget {
    var url: URL
    var origin: FileOrigin
    var boundary: URL
}

private enum IncludeResolution {
    case failure(Diagnostic)
    case success([IncludeTarget])
}

enum IncludeExpander {
    static func expand(
        root: URL,
        entryFile: String = "shell.kdl",
        origin: FileOrigin,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths
    ) -> IncludeExpansionResult {
        StackHeadroom.run {
            let state = ExpansionState()
            let entryURL = root.appendingPathComponent(entryFile)
            let nodes = expandFile(
                url: entryURL,
                origin: origin,
                boundary: root,
                chain: [],
                ancestorFiles: [],
                depth: 0,
                fileSystem: fileSystem,
                paths: paths,
                state: state
            )
            return IncludeExpansionResult(nodes: nodes, diagnostics: state.diagnostics, files: state.filesOrdered)
        }
    }

    private static func expandFile(
        url: URL,
        origin: FileOrigin,
        boundary: URL,
        chain: [SourceSpan],
        ancestorFiles: [String],
        depth: Int,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths,
        state: ExpansionState
    ) -> [ExpandedNode] {
        let resolved = fileSystem.resolvingSymlinks(url)
        guard isWithin(resolved, boundary: boundary) else {
            emit(Diagnostic(.error, "include path escapes the config folder", span: chain.last), chain: chain, state: state)
            return []
        }
        if ancestorFiles.contains(resolved.path) {
            let names = (ancestorFiles + [resolved.path]).map { URL(fileURLWithPath: $0).lastPathComponent }
            emit(Diagnostic(.error, "include cycle: \(names.joined(separator: " -> "))", span: chain.last), chain: chain, state: state)
            return []
        }
        state.insertions += 1
        if state.insertions > ConfigLimits.maxFileInsertions {
            if !state.insertionLimitHit {
                state.insertionLimitHit = true
                emit(Diagnostic(.error, "config includes more than \(ConfigLimits.maxFileInsertions) files", span: chain.last), chain: chain, state: state)
            }
            return []
        }
        let text: String
        do {
            text = try fileSystem.read(resolved)
        } catch {
            emit(Diagnostic(.error, "cannot read '\(resolved.path)'", span: chain.last), chain: chain, state: state)
            return []
        }
        guard text.utf8.count <= KDLLimits.maxBytes else {
            emit(Diagnostic(.error, "'\(resolved.path)' is larger than \(KDLLimits.maxBytes) bytes", span: chain.last), chain: chain, state: state)
            return []
        }
        let document: KDLDocument
        do throws(KDLParseError) {
            document = try KDLDocument.parse(text, file: resolved.path)
        } catch {
            emit(Diagnostic(.error, error.message, span: error.span), chain: chain, state: state)
            return []
        }
        if !state.seenFiles.contains(resolved.path) {
            state.seenFiles.insert(resolved.path)
            state.filesOrdered.append(resolved)
        }
        return expandNodes(
            document.nodes,
            file: resolved.path,
            chain: chain,
            boundary: boundary,
            origin: origin,
            ancestorFiles: ancestorFiles + [resolved.path],
            depth: depth,
            fileSystem: fileSystem,
            paths: paths,
            state: state
        )
    }

    private static func expandNodes(
        _ kdlNodes: [KDLNode],
        file: String,
        chain: [SourceSpan],
        boundary: URL,
        origin: FileOrigin,
        ancestorFiles: [String],
        depth: Int,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths,
        state: ExpansionState
    ) -> [ExpandedNode] {
        guard depth <= ConfigLimits.maxExpandedDepth else {
            if !state.depthLimitHit {
                state.depthLimitHit = true
                emit(Diagnostic(.error, "config is nested deeper than \(ConfigLimits.maxExpandedDepth) levels across include", span: kdlNodes.first?.span ?? chain.last), chain: chain, state: state)
            }
            return []
        }
        if state.budgetHit { return [] }
        var result: [ExpandedNode] = []
        for node in kdlNodes {
            if state.budgetHit { break }
            if node.annotation != nil {
                emit(Diagnostic(.error, "type annotations are reserved", span: node.span), chain: chain, state: state)
            }
            for value in node.arguments + node.properties.map(\.value) where value.annotation != nil {
                emit(Diagnostic(.error, "type annotations are reserved", span: value.span), chain: chain, state: state)
            }
            if node.name == "include" {
                result.append(contentsOf: handleInclude(
                    node,
                    file: file,
                    chain: chain,
                    boundary: boundary,
                    origin: origin,
                    ancestorFiles: ancestorFiles,
                    depth: depth,
                    fileSystem: fileSystem,
                    paths: paths,
                    state: state
                ))
                continue
            }
            state.nodeCount += 1
            if state.nodeCount > ConfigLimits.maxExpansionBudget {
                if !state.budgetHit {
                    state.budgetHit = true
                    emit(Diagnostic(.error, "config expands to more than \(ConfigLimits.maxExpansionBudget) nodes", span: node.span), chain: chain, state: state)
                }
                break
            }
            let expandedChildren: [ExpandedNode]
            if let children = node.children {
                expandedChildren = expandNodes(
                    children,
                    file: file,
                    chain: chain,
                    boundary: boundary,
                    origin: origin,
                    ancestorFiles: ancestorFiles,
                    depth: depth + 1,
                    fileSystem: fileSystem,
                    paths: paths,
                    state: state
                )
            } else {
                expandedChildren = []
            }
            result.append(ExpandedNode(kdl: node, file: file, includeChain: chain, children: expandedChildren, origin: origin))
        }
        return result
    }

    private static func handleInclude(
        _ node: KDLNode,
        file: String,
        chain: [SourceSpan],
        boundary: URL,
        origin: FileOrigin,
        ancestorFiles: [String],
        depth: Int,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths,
        state: ExpansionState
    ) -> [ExpandedNode] {
        guard node.arguments.count == 1, case .string(let raw) = node.arguments[0].scalar else {
            emit(Diagnostic(.error, "include requires exactly one string argument", span: node.span), chain: chain, state: state)
            return []
        }
        var optional = false
        for property in node.properties {
            if property.name == "optional" {
                if case .bool(let flag) = property.value.scalar {
                    optional = flag
                } else {
                    emit(Diagnostic(.error, "'optional' must be a bool", span: property.value.span), chain: chain, state: state)
                }
            } else {
                let suggestion = Suggestion.closest(to: property.name, among: ["optional"])
                emit(Diagnostic(.error, "unknown property '\(property.name)' on 'include'", span: property.span, help: suggestion.map { "did you mean '\($0)'?" }), chain: chain, state: state)
            }
        }
        if raw.utf8.contains(UInt8(ascii: "{")) {
            emit(Diagnostic(.error, "include path cannot contain an expression", span: node.arguments[0].span), chain: chain, state: state)
            return []
        }
        let resolution = resolveIncludeTargets(
            raw,
            currentFile: file,
            currentOrigin: origin,
            currentBoundary: boundary,
            fileSystem: fileSystem,
            paths: paths
        )
        switch resolution {
        case .failure(let diagnostic):
            var located = diagnostic
            if located.span == nil { located.span = node.arguments[0].span }
            emit(located, chain: chain, state: state)
            return []
        case .success(let targets):
            if targets.isEmpty {
                if !optional {
                    emit(Diagnostic(.warning, "glob '\(raw)' matched no files", span: node.span), chain: chain, state: state)
                }
                return []
            }
            var result: [ExpandedNode] = []
            let newChain = chain + [node.span]
            for target in targets {
                if !fileSystem.exists(target.url) {
                    if optional { continue }
                    emit(Diagnostic(.error, "included file '\(raw)' does not exist", span: node.span), chain: chain, state: state)
                    continue
                }
                result.append(contentsOf: expandFile(
                    url: target.url,
                    origin: target.origin,
                    boundary: target.boundary,
                    chain: newChain,
                    ancestorFiles: ancestorFiles,
                    depth: depth,
                    fileSystem: fileSystem,
                    paths: paths,
                    state: state
                ))
            }
            return result
        }
    }

    static func resolveAsset(
        _ raw: String,
        currentFile: String,
        origin: FileOrigin,
        configRoot: URL,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths
    ) -> Result<[URL], Diagnostic> {
        if raw.utf8.contains(UInt8(ascii: "{")) {
            return .failure(Diagnostic(.error, "style path cannot contain an expression"))
        }
        let boundary: URL
        switch origin {
        case .user: boundary = configRoot
        case .builtin(let id): boundary = paths.builtinConfigs.appendingPathComponent(id)
        case .pkg(let id): boundary = paths.packagesDirectory.appendingPathComponent(id)
        }
        switch resolveIncludeTargets(raw, currentFile: currentFile, currentOrigin: origin, currentBoundary: boundary, fileSystem: fileSystem, paths: paths) {
        case .failure(var diagnostic):
            diagnostic.message = diagnostic.message.replacingOccurrences(of: "include path", with: "style path")
            return .failure(diagnostic)
        case .success(let targets):
            return .success(targets.map(\.url))
        }
    }

    private static func resolveIncludeTargets(
        _ raw: String,
        currentFile: String,
        currentOrigin: FileOrigin,
        currentBoundary: URL,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths
    ) -> IncludeResolution {
        if raw.hasPrefix("builtin:") {
            let rest = String(raw.dropFirst("builtin:".count))
            guard let slash = rest.firstIndex(of: "/") else {
                return .failure(Diagnostic(.error, "'builtin:' needs a config id and a path"))
            }
            let id = String(rest[rest.startIndex..<slash])
            let path = String(rest[rest.index(after: slash)...])
            let boundary = paths.builtinConfigs.appendingPathComponent(id)
            return resolveWithinBoundary(path, boundary: boundary, origin: .builtin(id), fileSystem: fileSystem)
        }
        if raw.hasPrefix("pkg:") {
            let rest = String(raw.dropFirst("pkg:".count))
            guard let slash = rest.firstIndex(of: "/") else {
                return .failure(Diagnostic(.error, "'pkg:' needs a package id and a path"))
            }
            let id = String(rest[rest.startIndex..<slash])
            let path = String(rest[rest.index(after: slash)...])
            if case .pkg(let currentId) = currentOrigin, currentId != id {
                return .failure(Diagnostic(.error, "a file inside package '\(currentId)' can only include files from the same package or 'builtin:'"))
            }
            let boundary = paths.packagesDirectory.appendingPathComponent(id)
            return resolveWithinBoundary(path, boundary: boundary, origin: .pkg(id), fileSystem: fileSystem)
        }
        if raw.hasPrefix("/") {
            return .failure(Diagnostic(.error, "include path must be relative, not absolute"))
        }
        if raw.hasPrefix("~") {
            return .failure(Diagnostic(.error, "include path must not use '~'"))
        }
        let currentDirectory = URL(fileURLWithPath: currentFile).deletingLastPathComponent()
        return resolveWithinBoundary(raw, baseDirectory: currentDirectory, boundary: currentBoundary, origin: currentOrigin, fileSystem: fileSystem)
    }

    private static func resolveWithinBoundary(
        _ path: String,
        boundary: URL,
        origin: FileOrigin,
        fileSystem: any ConfigFileSystem
    ) -> IncludeResolution {
        resolveWithinBoundary(path, baseDirectory: boundary, boundary: boundary, origin: origin, fileSystem: fileSystem)
    }

    private static func resolveWithinBoundary(
        _ path: String,
        baseDirectory: URL,
        boundary: URL,
        origin: FileOrigin,
        fileSystem: any ConfigFileSystem
    ) -> IncludeResolution {
        let combined = baseDirectory.appendingPathComponent(path)
        let normalized = normalize(combined)
        guard isWithin(normalized, boundary: boundary) else {
            return .failure(Diagnostic(.error, "include path escapes the config folder"))
        }
        let resolved = fileSystem.resolvingSymlinks(normalized)
        guard isWithin(resolved, boundary: boundary) else {
            return .failure(Diagnostic(.error, "include path escapes the config folder via a symlink"))
        }
        let lastComponent = normalized.lastPathComponent
        guard lastComponent.contains("*") else {
            return .success([IncludeTarget(url: normalized, origin: origin, boundary: boundary)])
        }
        let directory = normalized.deletingLastPathComponent()
        guard let entries = try? fileSystem.contentsOfDirectory(directory) else {
            return .success([])
        }
        let matches = entries
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") && matchesGlob($0, pattern: lastComponent) }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let targets = matches.map { name in
            IncludeTarget(url: directory.appendingPathComponent(name), origin: origin, boundary: boundary)
        }
        return .success(targets)
    }

    private static func normalize(_ url: URL) -> URL {
        var components: [String] = []
        for component in url.pathComponents {
            if component == "/" { continue }
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"))
    }

    private static func isWithin(_ url: URL, boundary: URL) -> Bool {
        let boundaryPath = normalize(boundary).path
        let path = normalize(url).path
        return path == boundaryPath || path.hasPrefix(boundaryPath + "/")
    }

    private static func matchesGlob(_ name: String, pattern: String) -> Bool {
        let nameChars = Array(name)
        let patternChars = Array(pattern)
        return wildcardMatch(nameChars, 0, patternChars, 0)
    }

    private static func wildcardMatch(_ text: [Character], _ ti: Int, _ pattern: [Character], _ pi: Int) -> Bool {
        var ti = ti
        var pi = pi
        var starIndex = -1
        var matchIndex = 0
        while ti < text.count {
            if pi < pattern.count, pattern[pi] == "*" {
                starIndex = pi
                matchIndex = ti
                pi += 1
            } else if pi < pattern.count, pattern[pi] == text[ti] {
                ti += 1
                pi += 1
            } else if starIndex != -1 {
                pi = starIndex + 1
                matchIndex += 1
                ti = matchIndex
            } else {
                return false
            }
        }
        while pi < pattern.count, pattern[pi] == "*" {
            pi += 1
        }
        return pi == pattern.count
    }

    private static func emit(_ diagnostic: Diagnostic, chain: [SourceSpan], state: ExpansionState) {
        state.diagnostics.append(DiagnosticCollector.withIncludeChain(diagnostic, chain: chain))
    }
}
