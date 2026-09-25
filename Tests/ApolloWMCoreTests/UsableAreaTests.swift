import Foundation
import Testing
@testable import ApolloWMCore

@Suite("Nutzbarer Bereich: Panels ab Rand, reserve ab visibleFrame")
struct UsableAreaTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let visible = CGRect(x: 0, y: 30, width: 1000, height: 600)

    @Test("reserve top zählt unter der Menüleiste, bottom neben dem Dock")
    func extraFromVisible() {
        let rect = UsableArea.rect(visible: visible, bounds: bounds, edge: NSEdgeInsets(), extra: NSEdgeInsets(top: 40, left: 0, bottom: 8, right: 0))
        #expect(rect == CGRect(x: 0, y: 70, width: 1000, height: 552))
    }

    @Test("Panel-Streifen zählen ab Bildschirmrand, reserve kommt dazu")
    func panelsFromEdge() {
        let rect = UsableArea.rect(visible: visible, bounds: bounds, edge: NSEdgeInsets(top: 24, left: 44, bottom: 0, right: 0), extra: NSEdgeInsets(top: 10, left: 6, bottom: 0, right: 0))
        #expect(rect == CGRect(x: 50, y: 40, width: 950, height: 590))
        let tall = UsableArea.rect(visible: visible, bounds: bounds, edge: NSEdgeInsets(top: 50, left: 0, bottom: 0, right: 0), extra: NSEdgeInsets())
        #expect(tall.minY == 50)
    }
}
