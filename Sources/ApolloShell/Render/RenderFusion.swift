import AppKit
import SwiftUI
import ApolloStyle
import ApolloShellCore
import ApolloProviders

@MainActor
enum RenderFusion {
    static let screen = CGSize(width: 960, height: 600)
    static let pieces: [FusionPiece] = [
        FusionPiece(rect: CGRect(x: 0, y: 0, width: 960, height: 36), radius: 0),
        FusionPiece(rect: CGRect(x: 0, y: 36, width: 44, height: 564), radius: 14),
        FusionPiece(rect: CGRect(x: 380, y: 36, width: 260, height: 180), radius: 25),
        FusionPiece(rect: CGRect(x: 700, y: 420, width: 260, height: 180), radius: 20),
    ]

    static func run(_ arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--render-fusion"), index + 1 < arguments.count else { return 1 }
        var forwarded = arguments
        forwarded[index] = "--render"
        do {
            let options = try RenderCommand.options(forwarded, executable: URL(fileURLWithPath: CommandLine.arguments[0]))
            let session = try RenderSession(config: options.config, resources: options.resources, fixture: ProviderFixture.load(options.fixture),
                                            fixtureRoot: options.fixture.deletingLastPathComponent(), dark: options.dark, scale: options.scale, theme: options.theme)
            try render(session, into: options.output)
            return 0
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            return 1
        }
    }

    static func fill(_ session: RenderSession) -> ComputedStyle {
        let members = session.surfaces.filter { !FusionCoordinator.groupName($0).isEmpty }
        guard let chosen = members.first(where: { $0.property("fuse-fill").isTruthy }) ?? members.first else { return ComputedStyle(values: [:]) }
        let style = session.context.styles.resolve(surface: chosen)
        return ComputedStyle(values: style.values.filter { SurfaceBackground.properties.contains($0.key) })
    }

    static func scene(_ pieces: [FusionPiece], shape: FusionShape, fill: ComputedStyle, session: RenderSession, size: CGSize = screen) -> some View {
        let model = FusionSkinModel()
        model.pieces = pieces
        model.shape = shape
        model.fill = fill
        model.size = size
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.95, green: 0.62, blue: 0.25), Color(red: 0.36, green: 0.30, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            FusionSkinView(model: model, context: session.context)
        }
        .frame(width: size.width, height: size.height)
    }

    static func opening(_ strength: JellyStrength, fill: ComputedStyle, session: RenderSession) -> some View {
        let size = CGSize(width: 420, height: 260)
        let bar = CGRect(x: 0, y: size.height - 36, width: size.width, height: 36)
        let popout = CGRect(x: 110, y: size.height - 36 - 200, width: 200, height: 200)
        var field = JellyField(parameters: JellySpringParameters(strength: strength, speed: 1))
        field.set("bar", rect: bar, radius: 0, grow: nil)
        field.set("popout", rect: popout, radius: 25, grow: .maxY)
        var frames: [[FusionPiece]] = []
        for _ in 0..<12 {
            frames.append(field.pieces.map { entry in
                FusionPiece(rect: CGRect(x: entry.piece.rect.minX, y: size.height - entry.piece.rect.maxY,
                                         width: entry.piece.rect.width, height: entry.piece.rect.height), radius: entry.piece.radius)
            })
            for _ in 0..<6 { field.step(1.0 / 120) }
        }
        return VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { column in
                        scene(frames[row * 4 + column], shape: .standard, fill: fill, session: session, size: size)
                    }
                }
            }
        }
        .padding(8)
    }

    static func render(_ session: RenderSession, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fill = fill(session)
        let look = session.dark ? "dark" : "light"
        func write(_ view: some View, _ name: String) throws {
            let root = AnyView(view
                .environment(\.colorScheme, session.dark ? .dark : .light)
                .environment(\._accessibilityReduceTransparency, true)
                .environment(\.renderMode, true)
                .background(session.dark ? Color.black : Color.white)
                .transaction { $0.animation = nil; $0.disablesAnimations = true })
            let hosting = NSHostingView(rootView: root)
            session.canvas.host(hosting, size: hosting.fittingSize)
            defer { session.canvas.window.contentView = nil }
            try session.canvas.stableCapture(hosting, name: name).write(to: folder.appendingPathComponent(name))
        }
        for style in FusionStyle.allCases {
            for edge in FusionScreenEdge.allCases {
                for radius in [0.0, 14.0, 48.0] {
                    let shape = FusionShape(style: style, innerRadius: radius, screenEdge: edge)
                    try write(scene(pieces, shape: shape, fill: fill, session: session), "fusion-\(style.rawValue)-\(edge.rawValue)-r\(Int(radius))-\(look).png")
                }
            }
        }
        for strength in JellyStrength.allCases {
            try write(opening(strength, fill: fill, session: session), "fusion-jelly-\(strength.rawValue)-\(look).png")
        }
    }
}
