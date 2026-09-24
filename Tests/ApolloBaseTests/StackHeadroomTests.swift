import Testing
import Foundation
@testable import ApolloBase

@Suite("Stapel-Reserve für rekursive Parser")
struct StackHeadroomTests {
    struct Outcome: Sendable {
        let callerIdentity: ObjectIdentifier
        let ranIdentity: ObjectIdentifier
        let ranQoS: QualityOfService
    }

    final class OutcomeBox: @unchecked Sendable {
        var value: Outcome?
    }

    static func runOnThread(stackSize: Int, qos: QualityOfService, minimum: Int, headroomStackSize: Int) -> Outcome {
        let box = OutcomeBox()
        let semaphore = DispatchSemaphore(value: 0)
        let caller = Thread {
            let callerIdentity = ObjectIdentifier(Thread.current)
            let (ranIdentity, ranQoS) = StackHeadroom.run(minimum: minimum, stackSize: headroomStackSize) {
                (ObjectIdentifier(Thread.current), Thread.current.qualityOfService)
            }
            box.value = Outcome(callerIdentity: callerIdentity, ranIdentity: ranIdentity, ranQoS: ranQoS)
            semaphore.signal()
        }
        caller.stackSize = stackSize
        caller.qualityOfService = qos
        caller.start()
        semaphore.wait()
        return box.value!
    }

    @Test("reicht der Stapel, läuft der Block auf demselben Thread")
    func runsInline() {
        let outcome = Self.runOnThread(stackSize: 8 << 20, qos: .default, minimum: 1, headroomStackSize: 8 << 20)
        #expect(outcome.callerIdentity == outcome.ranIdentity)
    }

    @Test("reicht der Stapel nicht, wechselt der Block auf einen neuen Thread mit grossem Stapel und übernimmt die QoS")
    func switchesThread() {
        let outcome = Self.runOnThread(stackSize: 256 << 10, qos: .userInitiated, minimum: Int.max, headroomStackSize: 8 << 20)
        #expect(outcome.callerIdentity != outcome.ranIdentity)
        #expect(outcome.ranQoS == .userInitiated)
    }

    @Test("Werte kommen unverändert zurück")
    func returnsValue() {
        let value = StackHeadroom.run(minimum: Int.max, stackSize: 256 << 10) { 42 }
        #expect(value == 42)
    }

    struct SampleError: Error, Sendable, Equatable {}

    @Test("Fehler als Result kommen unverändert zurück")
    func returnsFailure() {
        let result: Result<Int, SampleError> = StackHeadroom.run(minimum: Int.max, stackSize: 256 << 10) {
            .failure(SampleError())
        }
        #expect(result == .failure(SampleError()))
    }
}
