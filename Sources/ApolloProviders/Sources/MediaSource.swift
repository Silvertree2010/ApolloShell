import Foundation
import ApolloShellCore

public enum MediaStreamEvent: Sendable {
    case messages([MediaStreamMessage])
    case exited(Int32)
}

@MainActor
public protocol MediaSource: AnyObject {
    var adapterAvailable: Bool { get }
    var now: Date { get }
    func startStream(_ handler: @escaping @MainActor (MediaStreamEvent) -> Void) -> Bool
    func stopStream()
    func send(_ command: MediaCommand)
    func seek(microseconds: Int)
    func appName(_ bundleIdentifier: String) -> String?
    func artworkAspect(_ data: Data) -> Double?
    func openApp(_ bundleIdentifier: String)
}
