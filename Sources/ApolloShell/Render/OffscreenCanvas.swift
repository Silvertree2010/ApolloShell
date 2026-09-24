import AppKit
import CoreImage
import SwiftUI

@MainActor
final class OffscreenCanvas {
    static let origin = NSPoint(x: -40_000, y: -40_000)
    static let settleStep: TimeInterval = 0.02
    static let stableCaptures = 3
    static let maxSteps = 250

    let window: NSWindow
    let scale: CGFloat

    init(appearance: ColorScheme, scale: CGFloat) {
        self.scale = scale
        window = NSWindow(contentRect: NSRect(origin: Self.origin, size: NSSize(width: 64, height: 64)),
                          styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    func host(_ view: NSView, size: CGSize) {
        window.setFrame(NSRect(origin: Self.origin, size: size), display: false, animate: false)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
    }

    func settle() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CFRunLoopRunInMode(.defaultMode, Self.settleStep, false)
            quietFieldEditor()
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            CATransaction.commit()
        }
    }

    func quietFieldEditor() {
        guard let editor = window.firstResponder as? NSTextView else { return }
        editor.insertionPointColor = .clear
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        if editor.selectedRange() != end { editor.setSelectedRange(end) }
    }

    func stableCapture(_ view: NSView, name: String) throws -> Data {
        var previous: Data?
        var same = 0
        for _ in 0..<Self.maxSteps {
            settle()
            let data = try snapshot(view, name: name)
            if data == previous {
                same += 1
                if same + 1 >= Self.stableCaptures { return data }
            } else {
                same = 0
            }
            previous = data
        }
        throw RenderError.unstable(name)
    }

    static let glassLayerClasses: Set<String> = ["CABackdropLayer", "SDFPortalLayer", "CASDFLayer", "CAPortalLayer"]

    private(set) var hiddenGlass: [String: Int] = [:]

    func hideGlass(in layer: CALayer) {
        let name = String(describing: type(of: layer))
        if Self.glassLayerClasses.contains(name) {
            if !layer.isHidden { hiddenGlass[name, default: 0] += 1 }
            layer.isHidden = true
            return
        }
        if let matrix = Self.vibrantMatrix(of: layer) {
            bakeVibrancy(matrix, into: layer)
            hiddenGlass["vibrantColorMatrix", default: 0] += 1
        }
        for sublayer in layer.sublayers ?? [] { hideGlass(in: sublayer) }
    }

    static func vibrantMatrix(of layer: CALayer) -> [CGFloat]? {
        for filter in layer.filters ?? [] {
            let object = filter as AnyObject
            guard String(describing: object.value(forKey: "name") ?? "") == "vibrantColorMatrix",
                  let value = object.value(forKey: "inputColorMatrix") as? NSValue else { continue }
            var matrix = [Float](repeating: 0, count: 20)
            matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
            return matrix.map { CGFloat($0) }
        }
        return nil
    }

    func bakeVibrancy(_ m: [CGFloat], into layer: CALayer) {
        let size = layer.bounds.size
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        let saved = layer.filters
        layer.filters = nil
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -layer.bounds.minX, y: -layer.bounds.minY)
        layer.render(in: context)
        layer.filters = saved
        guard let source = context.makeImage() else { return }
        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: m[0], y: m[1], z: m[2], w: m[3]), forKey: "inputRVector")
        filter.setValue(CIVector(x: m[5], y: m[6], z: m[7], w: m[8]), forKey: "inputGVector")
        filter.setValue(CIVector(x: m[10], y: m[11], z: m[12], w: m[13]), forKey: "inputBVector")
        filter.setValue(CIVector(x: m[15], y: m[16], z: m[17], w: m[18]), forKey: "inputAVector")
        filter.setValue(CIVector(x: m[4], y: m[9], z: m[14], w: m[19]), forKey: "inputBiasVector")
        let ci = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space, .useSoftwareRenderer: true])
        guard let output = filter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)),
              let baked = ci.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: space)
        else { return }
        layer.filters = nil
        layer.backgroundColor = nil
        layer.sublayers?.forEach { $0.isHidden = true }
        layer.contentsGravity = .resize
        layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.contentsScale = scale
        layer.contents = baked
    }

    func takeHiddenGlass() -> [String: Int] {
        defer { hiddenGlass = [:] }
        return hiddenGlass
    }

    func snapshot(_ view: NSView, name: String) throws -> Data {
        let bounds = view.bounds
        guard let blank = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * scale).rounded()), pixelsHigh: Int((bounds.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let bitmap = blank.retagging(with: .sRGB) else { throw RenderError.noImage(name) }
        bitmap.size = bounds.size
        if let layer = view.layer { hideGlass(in: layer) }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.noImage(name)
        }
        return data
    }
}


enum RenderError: Error, CustomStringConvertible {
    case unstable(String)
    case noImage(String)
    case usage(String)
    case config(String)

    var description: String {
        switch self {
        case .unstable(let name): "render of \(name) did not settle"
        case .noImage(let name): "no image for \(name)"
        case .usage(let text): text
        case .config(let text): text
        }
    }
}
