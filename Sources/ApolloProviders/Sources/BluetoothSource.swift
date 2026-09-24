import ApolloShellCore

@MainActor
public protocol BluetoothSource: AnyObject {
    func read(_ completion: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void)
    func openSettings()
}
