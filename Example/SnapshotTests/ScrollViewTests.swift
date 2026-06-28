import FBSnapshotTestCase_Accessibility
import iOSSnapshotTestCase
import SwiftUI

@testable import AccessibilitySnapshotDemo

final class ScrollViewTests: SnapshotTestCase {
    // MARK: - UIKit UITableView

    func testTableViewScrolledToTop() {
        let vc = ScrollViewAccessibilityViewController(scrollPosition: .top)
        vc.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        vc.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(vc.view)
    }

    func testTableViewScrolledToMiddle() {
        let vc = ScrollViewAccessibilityViewController(scrollPosition: .middle)
        vc.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        vc.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(vc.view)
    }

    func testTableViewScrolledToBottom() {
        let vc = ScrollViewAccessibilityViewController(scrollPosition: .bottom)
        vc.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        vc.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(vc.view)
    }

    // MARK: - SwiftUI List

    func testSwiftUIListScrolledToTop() {
        let view = SwiftUIScrollView(scrollPosition: .top)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        host.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(host.view)
    }

    func testSwiftUIListScrolledToMiddle() {
        let view = SwiftUIScrollView(scrollPosition: .middle)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        host.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(host.view)
    }

    func testSwiftUIListScrolledToBottom() {
        let view = SwiftUIScrollView(scrollPosition: .bottom)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        host.view.layoutIfNeeded()
        SnapshotVerifyAccessibility(host.view)
    }
}
