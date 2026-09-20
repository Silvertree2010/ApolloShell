import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Edit mode: where toolbar and gallery stand")
struct EditModeGeometryTests {
    /// 14" MacBook Pro, the machine the mode was built on.
    private let wide = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    /// 13" MacBook Air - narrow enough for the gallery and the control
    /// centre to want the same place.
    private let narrow = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let gallery = CGSize(width: 760, height: 304)
    private let toolbar = CGSize(width: 429, height: 54)

    /// The control centre stands at the right edge, 430 pt wide.
    private func utilities(on screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.maxX - 430, y: screen.minY - 25, width: 430, height: height)
    }

    @Test("Toolbar: the middle of the screen, not of the free area")
    func toolbarUsesScreenMiddle() {
        // Apple's Dock at the left edge: the free area starts further
        // right, the toolbar stays in the middle of the screen all the
        // same.
        let dockLeft = CGRect(x: 100, y: 0, width: 1628, height: 1084)
        let center = EditModeGeometry.toolbarCenter(screen: wide, visible: dockLeft, size: toolbar, utilities: nil)
        #expect(center.x == wide.midX)
    }

    @Test("Toolbar: bottom centre while nothing stands there")
    func toolbarPlain() {
        let center = EditModeGeometry.toolbarCenter(screen: wide, visible: wide, size: toolbar, utilities: nil)
        #expect(center.x == wide.midX)
        #expect(center.y == wide.minY + 20 + toolbar.height / 2)
    }

    @Test("Toolbar: above the control centre, and never off the top edge")
    func toolbarAvoids() {
        // On the wide screen the two never meet: the toolbar is 429 pt in
        // the middle, the panel 430 pt at the right edge.
        let apart = EditModeGeometry.toolbarCenter(screen: wide, visible: wide, size: toolbar, utilities: utilities(on: wide, height: 451))
        #expect(apart.y == wide.minY + 20 + toolbar.height / 2)
        // An old 1280 pt screen is narrow enough for them to overlap.
        let small = CGRect(x: 0, y: 0, width: 1280, height: 780)
        let low = EditModeGeometry.toolbarCenter(screen: small, visible: small, size: toolbar, utilities: utilities(on: small, height: 451))
        #expect(low.y > small.minY + 20 + toolbar.height / 2)
        #expect(low.y + toolbar.height / 2 <= small.maxY)
        // A control centre nearly as tall as the screen used to push the
        // toolbar out through the top edge.
        let tall = EditModeGeometry.toolbarCenter(screen: small, visible: small, size: toolbar, utilities: utilities(on: small, height: 760))
        #expect(tall.y + toolbar.height / 2 <= small.maxY)
    }

    @Test("Gallery: middle of the screen while no dashboard is open")
    func galleryWithoutDashboard() {
        let center = EditModeGeometry.galleryCenter(visible: wide, gallery: gallery, dashboard: nil,
                                                    utilities: nil, toolbarHeight: toolbar.height)
        #expect(center == CGPoint(x: wide.midX, y: wide.midY))
    }

    @Test("Gallery: under the dashboard, above the toolbar")
    func galleryUnderDashboard() {
        let dashboard = CGRect(x: 366, y: 533, width: 996, height: 609)
        let center = EditModeGeometry.galleryCenter(visible: wide, gallery: gallery, dashboard: dashboard,
                                                    utilities: nil, toolbarHeight: toolbar.height)
        #expect(center.y + gallery.height / 2 < dashboard.minY)
        #expect(center.y - gallery.height / 2 > wide.minY + 20 + toolbar.height)
    }

    @Test("Gallery: keeps clear of the control centre, even on a narrow screen")
    func galleryKeepsClear() {
        let panel = utilities(on: narrow, height: 451)
        let dashboard = CGRect(x: 320, y: 470, width: 870, height: 530)
        let center = EditModeGeometry.galleryCenter(visible: narrow, gallery: gallery, dashboard: dashboard,
                                                    utilities: panel, toolbarHeight: toolbar.height)
        let rect = CGRect(x: center.x - gallery.width / 2, y: center.y - gallery.height / 2,
                          width: gallery.width, height: gallery.height)
        #expect(!rect.intersects(panel))
        #expect(rect.minX >= narrow.minX)
        // On the wide screen it stays in the middle: there is room there.
        let wideCenter = EditModeGeometry.galleryCenter(visible: wide, gallery: gallery,
                                                        dashboard: CGRect(x: 366, y: 533, width: 996, height: 609),
                                                        utilities: utilities(on: wide, height: 451),
                                                        toolbarHeight: toolbar.height)
        #expect(wideCenter.x == wide.midX)
    }

    @Test("Gallery: narrower beside the control centre instead of over it")
    func galleryShrinks() {
        let panel = utilities(on: narrow, height: 451)
        let width = EditModeGeometry.galleryWidth(visible: narrow, utilities: panel, preferred: 760, minimum: 390)
        // 1512 - 430 of panel - 32 of air = 1050, so it keeps its own width.
        #expect(width == 760)
        // A 1024 pt screen leaves 594 - 32 = 562 free: narrower it is.
        let small = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let onSmall = EditModeGeometry.galleryWidth(visible: small, utilities: utilities(on: small, height: 451),
                                                    preferred: 760, minimum: 390)
        #expect(onSmall == 562)
        let rect = CGRect(x: 0, y: 0, width: onSmall, height: 300)
        #expect(!rect.intersects(utilities(on: small, height: 451)))
        // Even narrower it stops at the minimum rather than becoming a
        // column of one.
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(EditModeGeometry.galleryWidth(visible: tiny, utilities: utilities(on: tiny, height: 451),
                                              preferred: 760, minimum: 390) == 390)
        // Without a control centre it always keeps its own width.
        #expect(EditModeGeometry.galleryWidth(visible: small, utilities: nil, preferred: 760, minimum: 390) == 760)
    }

    @Test("Gallery: the columns follow the width", arguments: [
        (760.0, 8), (562.0, 5), (390.0, 4), (200.0, 1),
    ])
    func galleryColumns(width: Double, expected: Int) {
        #expect(EditModeGeometry.galleryColumns(width: width, margin: 16, tile: 82,
                                                spacing: 10, maximum: 8) == expected)
    }

    @Test("Gallery: a closed control centre takes no room")
    func galleryIgnoresClosedPanel() {
        let closed = CGRect(x: narrow.maxX - 430, y: narrow.minY, width: 430, height: 0)
        let center = EditModeGeometry.galleryCenter(visible: narrow, gallery: gallery, dashboard: nil,
                                                    utilities: closed, toolbarHeight: toolbar.height)
        #expect(center.x == narrow.midX)
    }
}
