import Foundation
import Testing
@testable import ApolloShellCore

struct DragReorderTests {
    @Test("Ablegen auf eine Zeile nimmt deren Platz ein, nach unten wie nach oben", arguments: [
        (0, 2, ["b", "c", "a", "d"]), (3, 1, ["a", "d", "b", "c"]), (1, 0, ["b", "a", "c", "d"]), (2, 3, ["a", "b", "d", "c"]),
    ])
    func onto(from: Int, to: Int, expected: [String]) {
        var list = ["a", "b", "c", "d"]
        list.move(fromOffsets: IndexSet(integer: from), toOffset: DragReorder.offset(from: from, onto: to))
        #expect(list == expected)
    }
}
