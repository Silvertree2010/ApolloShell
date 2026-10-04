import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Springy rectangles of fused surfaces")
struct JellyFieldTests {
    private func run(_ field: inout JellyField, seconds: Double, watch: (JellyField) -> Void = { _ in }) {
        var left = seconds
        while left > 0 {
            field.step(1.0 / 120)
            watch(field)
            left -= 1.0 / 120
        }
    }

    private func rect(_ field: JellyField, _ id: String) -> CGRect? {
        field.pieces.first { $0.id == id }?.piece.rect
    }

    @Test("Off, reduced motion or speed 0: no spring at all")
    func noParameters() {
        #expect(JellySpringParameters(strength: .off, speed: 1) == nil)
        #expect(JellySpringParameters(strength: .strong, speed: 0) == nil)
        #expect(JellySpringParameters(strength: .strong, speed: 1, reduceMotion: true) == nil)
        #expect(JellySpringParameters(strength: .subtle, speed: 1) != nil)
    }

    @Test("Without parameters every change is there at once")
    func instant() {
        var field = JellyField(parameters: nil)
        let target = CGRect(x: 10, y: 10, width: 100, height: 50)
        field.set("a", rect: target, radius: 8, grow: .maxY)
        #expect(rect(field, "a") == target)
        #expect(field.isResting)
        field.remove("a", into: .maxY)
        #expect(field.pieces.isEmpty)
    }

    @Test("A new piece grows out of its side and comes to rest on its frame")
    func grows() {
        var field = JellyField(parameters: JellySpringParameters(strength: .subtle, speed: 1))
        let target = CGRect(x: 400, y: 364, width: 200, height: 200)
        field.set("popout", rect: target, radius: 16, grow: .maxY)
        let start = rect(field, "popout")
        #expect(start?.height == 0)
        #expect(start?.maxY == target.maxY)
        #expect(!field.isResting)
        run(&field, seconds: 2)
        #expect(field.isResting)
        #expect(rect(field, "popout") == target)
    }

    @Test("A huge theme speed is clamped and still comes to rest")
    func hugeSpeed() {
        for speed in [100.0, 1e9, .infinity] {
            var field = JellyField(parameters: JellySpringParameters(strength: .subtle, speed: speed))
            let target = CGRect(x: 400, y: 364, width: 200, height: 200)
            field.set("p", rect: target, radius: 16, grow: .maxY)
            run(&field, seconds: 3)
            #expect(field.isResting)
            #expect(rect(field, "p") == target)
        }
    }

    @Test("A spring with a non-finite state counts as resting")
    func nonFinite() {
        var s = JellyField.Spring(0)
        s.target = 10
        s.value = .nan
        #expect(s.isResting)
        s.value = 0
        s.velocity = .infinity
        #expect(s.isResting)
    }

    @Test("Strong overshoots visibly, subtle hardly")
    func overshoot() {
        for (strength, low, high) in [(JellyStrength.strong, 0.10, 0.40), (.subtle, 0.0, 0.03)] {
            var field = JellyField(parameters: JellySpringParameters(strength: strength, speed: 1))
            field.set("p", rect: CGRect(x: 0, y: 300, width: 200, height: 200), radius: 0, grow: .maxY)
            var lowest: CGFloat = 300
            run(&field, seconds: 2) { lowest = min(lowest, rect($0, "p")?.minY ?? 300) }
            let overshoot = Double(300 - lowest) / 200
            #expect(overshoot >= low && overshoot <= high, "\(strength): \(overshoot)")
        }
    }

    @Test("Removed with a side: shrinks into it, then is gone")
    func removes() {
        var field = JellyField(parameters: JellySpringParameters(strength: .subtle, speed: 1))
        field.set("p", rect: CGRect(x: 0, y: 300, width: 200, height: 200), radius: 0, grow: nil)
        field.remove("p", into: .maxY)
        #expect(field.pieces.count == 1)
        run(&field, seconds: 2)
        #expect(field.pieces.isEmpty)
        #expect(field.isResting)
    }

    @Test("Set again while shrinking away: it stays")
    func revives() {
        var field = JellyField(parameters: JellySpringParameters(strength: .subtle, speed: 1))
        let target = CGRect(x: 0, y: 300, width: 200, height: 200)
        field.set("p", rect: target, radius: 0, grow: nil)
        field.remove("p", into: .maxY)
        run(&field, seconds: 0.05)
        field.set("p", rect: target, radius: 0, grow: .maxY)
        run(&field, seconds: 2)
        #expect(rect(field, "p") == target)
    }

    @Test("A frame change springs over; a hang of a whole second does not blow it up")
    func largeStep() {
        var field = JellyField(parameters: JellySpringParameters(strength: .strong, speed: 1))
        field.set("p", rect: CGRect(x: 0, y: 0, width: 44, height: 500), radius: 0, grow: nil)
        field.set("p", rect: CGRect(x: 0, y: 0, width: 64, height: 500), radius: 0, grow: nil)
        #expect(!field.isResting)
        field.step(1)
        let now = rect(field, "p")!
        #expect(now.width.isFinite && now.width > 30 && now.width < 100)
    }

    @Test("A neighbour touching a moving edge gives way and springs back")
    func neighbour() {
        var field = JellyField(parameters: JellySpringParameters(strength: .subtle, speed: 1))
        field.set("side", rect: CGRect(x: 0, y: 0, width: 44, height: 500), radius: 0, grow: nil)
        field.set("next", rect: CGRect(x: 44, y: 0, width: 100, height: 500), radius: 0, grow: nil)
        field.set("side", rect: CGRect(x: 0, y: 0, width: 64, height: 500), radius: 0, grow: nil)
        var moved = false
        run(&field, seconds: 2) { if (rect($0, "next")?.minX ?? 44) > 44.5 { moved = true } }
        #expect(moved)
        #expect(rect(field, "next")?.minX == 44)
        #expect(field.isResting)
    }

    @Test("Pieces keep their radius and come out in a stable order")
    func order() {
        var field = JellyField(parameters: nil)
        field.set("b", rect: CGRect(x: 0, y: 0, width: 10, height: 10), radius: 3, grow: nil)
        field.set("a", rect: CGRect(x: 20, y: 0, width: 10, height: 10), radius: 5, grow: nil)
        #expect(field.pieces.map(\.id) == ["a", "b"])
        #expect(field.pieces.map(\.piece.radius) == [5, 3])
    }
}
