import XCTest
@testable import MacDring

final class NotesDrawerResizeTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private let tab = CGRect(x: 0, y: 350, width: 30, height: 100)
    private let initial = CGRect(x: 0, y: 200, width: 400, height: 400)

    func testScreenAttachedSideAndCornersHaveNoHandles() {
        XCTAssertEqual(NotesDrawerResize.handles(for: .left), [.right, .top, .bottom, .topRight, .bottomRight])
        XCTAssertEqual(NotesDrawerResize.handles(for: .right), [.left, .top, .bottom, .topLeft, .bottomLeft])
        XCTAssertEqual(NotesDrawerResize.handles(for: .top), [.left, .right, .bottom, .bottomLeft, .bottomRight])
        XCTAssertEqual(NotesDrawerResize.handles(for: .bottom), [.left, .right, .top, .topLeft, .topRight])
    }

    func testCornerKeepsScreenEdgeAndOppositeSideFixed() {
        let frame = resized(.topRight, by: CGSize(width: 100, height: 80))
        XCTAssertEqual(frame, CGRect(x: 0, y: 200, width: 500, height: 480))
    }

    func testAttachedSideCannotMove() {
        XCTAssertEqual(resized(.left, by: CGSize(width: 100, height: 0)), initial)
    }

    func testInwardResizeForEveryScreenEdge() {
        let cases: [(Edge, NotesDrawerResize.Handle, CGRect, CGRect, CGSize, CGRect)] = [
            (.left, .right, initial, tab, CGSize(width: 100, height: 0), CGRect(x: 0, y: 200, width: 500, height: 400)),
            (.right, .left, CGRect(x: 800, y: 200, width: 400, height: 400),
             CGRect(x: 1170, y: 350, width: 30, height: 100), CGSize(width: 100, height: 0),
             CGRect(x: 900, y: 200, width: 300, height: 400)),
            (.top, .bottom, CGRect(x: 300, y: 500, width: 400, height: 400),
             CGRect(x: 450, y: 870, width: 100, height: 30), CGSize(width: 0, height: -60),
             CGRect(x: 300, y: 440, width: 400, height: 460)),
            (.bottom, .top, CGRect(x: 300, y: 0, width: 400, height: 400),
             CGRect(x: 450, y: 0, width: 100, height: 30), CGSize(width: 0, height: 70),
             CGRect(x: 300, y: 0, width: 400, height: 470))
        ]
        for (edge, handle, start, pill, delta, expected) in cases {
            XCTAssertEqual(NotesDrawerResize.frame(handle: handle, initialFrame: start, translation: delta,
                                                    minimumSize: DrawerMetrics.notesMinimumSize, tabFrame: pill,
                                                    edge: edge, in: visible), expected, "\(edge)")
        }
    }

    func testGrowthStopsAtScreenBoundaryAndLeavesRoomForTab() {
        let frame = resized(.topRight, by: CGSize(width: 10_000, height: 10_000))
        XCTAssertEqual(frame, CGRect(x: 0, y: 200, width: 1170, height: 700))
        let openedTab = EdgeLayout.openedTabFrame(edge: .left, restingTabFrame: tab, drawerFrame: frame)
        XCTAssertTrue(visible.contains(openedTab))
    }

    func testShrinkHonorsMinimumSizeAndTabSpan() {
        XCTAssertEqual(resized(.right, by: CGSize(width: -1000, height: 0)).width, DrawerMetrics.notesMinimumSize.width)
        XCTAssertEqual(resized(.top, by: CGSize(width: 0, height: -1000)).maxY, tab.maxY)
        XCTAssertEqual(resized(.bottom, by: CGSize(width: 0, height: 1000)).minY, tab.minY)
    }

    func testAsymmetricResizeRestoresWithoutRecentering() {
        let screen = CGRect(x: -1400, y: -500, width: 1200, height: 900)
        for edge in Edge.allCases {
            let pillSize = edge.isVertical ? CGSize(width: 30, height: 100) : CGSize(width: 100, height: 30)
            let pill = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pillSize, in: screen)
            let start = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: pill,
                                                    contentSize: CGSize(width: 400, height: 400), in: screen)
            for handle in NotesDrawerResize.handles(for: edge) {
                let frame = NotesDrawerResize.frame(handle: handle, initialFrame: start,
                                                     translation: CGSize(width: 73, height: -54),
                                                     minimumSize: DrawerMetrics.notesMinimumSize,
                                                     tabFrame: pill, edge: edge, in: screen)
                let position = NotesDrawerResize.tabPosition(edge: edge, tabFrame: pill, drawerFrame: frame)
                let saved = NotesDrawerSize(width: Double(frame.width), height: Double(frame.height), tabPosition: position)!
                let size = DrawerMetrics.notesSize(preferredSize: saved, columns: 12, rows: 16, iconSize: 128, in: screen)
                let reopened = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: pill, contentSize: size,
                                                           tabPosition: saved.tabPosition, in: screen)
                XCTAssertEqual(reopened.minX, frame.minX, accuracy: 0.001)
                XCTAssertEqual(reopened.minY, frame.minY, accuracy: 0.001)
                XCTAssertEqual(reopened.size, frame.size)
            }
        }
    }

    func testSavedAlignmentKeepsTabInsideDrawerAfterMovingAlongEdge() {
        let movedTab = CGRect(x: 0, y: 50, width: 30, height: 100)
        let frame = EdgeLayout.openDrawerFrame(edge: .left, tabFrame: movedTab,
                                                contentSize: CGSize(width: 400, height: 500),
                                                tabPosition: 0.1, in: visible)
        XCTAssertGreaterThanOrEqual(frame.maxY, movedTab.maxY)
        XCTAssertLessThanOrEqual(frame.minY, movedTab.minY)
        XCTAssertTrue(visible.contains(frame))
    }

    func testSmallDisplayCanOverrideMinimumWithoutSpilling() {
        let screen = CGRect(x: -200, y: -100, width: 200, height: 160)
        let pill = CGRect(x: -200, y: -70, width: 30, height: 100)
        let start = CGRect(x: -200, y: -100, width: 170, height: 160)
        let frame = NotesDrawerResize.frame(handle: .topRight, initialFrame: start,
                                             translation: CGSize(width: -1000, height: -1000),
                                             minimumSize: DrawerMetrics.notesMinimumSize, tabFrame: pill,
                                             edge: .left, in: screen)
        XCTAssertEqual(frame, start)
    }

    func testNonfinitePointerTranslationIsIgnored() {
        XCTAssertEqual(resized(.right, by: CGSize(width: CGFloat.infinity, height: 0)), initial)
    }

    private func resized(_ handle: NotesDrawerResize.Handle, by translation: CGSize) -> CGRect {
        NotesDrawerResize.frame(handle: handle, initialFrame: initial, translation: translation,
                                 minimumSize: DrawerMetrics.notesMinimumSize, tabFrame: tab,
                                 edge: .left, in: visible)
    }
}
