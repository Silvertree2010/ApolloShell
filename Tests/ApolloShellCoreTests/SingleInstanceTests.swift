import ApolloShellCore
import Testing

@Suite("Nur eine Instanz")
struct SingleInstanceTests {
    @Test("Entscheidung", arguments: [
        (0, false, false, SingleInstance.Decision.run),
        (0, true, false, .run),
        (1, false, false, .handOver),
        (1, true, false, .wait),
        (1, true, true, .handOver),
        (2, false, true, .handOver),
    ])
    func decide(others: Int, replacesOld: Bool, waited: Bool, expected: SingleInstance.Decision) {
        #expect(SingleInstance.decide(otherInstances: others, replacesOld: replacesOld, waitedLongEnough: waited) == expected)
    }

    @Test("Ersetzt eine alte Instanz", arguments: [
        ([], [:], false),
        (["ApolloShell", "--relaunch"], [:], true),
        ([], ["XPC_SERVICE_NAME": "org.example.apolloshell"], true),
        // Finder, Dock, `open`: LaunchServices setzt "application.…".
        ([], ["XPC_SERVICE_NAME": "application.io.github.example.123.456"], false),
        ([], ["XPC_SERVICE_NAME": "0"], false),
    ] as [([String], [String: String], Bool)])
    func replacesOld(arguments: [String], environment: [String: String], expected: Bool) {
        #expect(SingleInstance.replacesOld(arguments: arguments, environment: environment) == expected)
    }
}
