import Foundation

struct TempFolder {
    let url: URL

    init() {
        var template = Array((NSTemporaryDirectory() + "ac.XXXXXX").utf8CString)
        let created = template.withUnsafeMutableBufferPointer { buffer in
            mkdtemp(buffer.baseAddress!)
        }
        let path = String(cString: created!)
        url = URL(fileURLWithPath: path, isDirectory: true)
    }

    var socketPath: String { url.appendingPathComponent("s").path }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
