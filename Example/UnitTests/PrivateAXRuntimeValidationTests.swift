@testable import AccessibilitySnapshotCore
@testable import AccessibilitySnapshotParser
import XCTest

final class PrivateAXRuntimeValidationTests: XCTestCase {
    // MARK: - Visibility Gate

    func testShouldBeProcessed_visibleView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        window.addSubview(view)
        window.makeKeyAndVisible()
        XCTAssertTrue(view.ax_shouldBeProcessed)
    }

    func testShouldBeProcessed_hiddenView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        view.isHidden = true
        window.addSubview(view)
        XCTAssertFalse(view.ax_shouldBeProcessed)
    }

    func testShouldBeProcessed_zeroAlphaView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        view.alpha = 0
        window.addSubview(view)
        XCTAssertFalse(view.ax_shouldBeProcessed)
    }

    func testShouldBeProcessed_nonUIView() {
        let element = UIAccessibilityElement(accessibilityContainer: UIView())
        XCTAssertTrue(element.ax_shouldBeProcessed)
    }

    // MARK: - Scroll Ancestor

    func testIsScrollAncestor_scrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertTrue(scrollView.ax_isScrollAncestor)
    }

    func testIsScrollAncestor_tableView() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertTrue(tableView.ax_isScrollAncestor)
    }

    func testIsScrollAncestor_plainView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertFalse(view.ax_isScrollAncestor)
    }

    // MARK: - Scroll Parent

    func testScrollParent_labelInsideScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        label.text = "Hello"
        scrollView.addSubview(label)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(scrollView)
        window.makeKeyAndVisible()

        let parent = label.ax_scrollParent
        XCTAssertTrue(parent === scrollView, "Expected scroll parent to be the scroll view")
    }

    func testScrollParent_labelNotInScrollView() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        label.text = "Hello"
        container.addSubview(label)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(container)

        XCTAssertNil(label.ax_scrollParent)
    }

    // MARK: - Ordered Children

    func testHasOrderedChildren_plainView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertFalse(view.ax_hasOrderedChildren)
    }

    func testHasOrderedChildren_accessibilityElement() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.isAccessibilityElement = true
        XCTAssertFalse(view.ax_hasOrderedChildren)
    }

    func testHasOrderedChildren_viewWithAccessibilityElements() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let child1 = UIAccessibilityElement(accessibilityContainer: container)
        child1.accessibilityLabel = "One"
        let child2 = UIAccessibilityElement(accessibilityContainer: container)
        child2.accessibilityLabel = "Two"
        container.accessibilityElements = [child1, child2]
        XCTAssertTrue(container.ax_hasOrderedChildren)
    }

    // MARK: - SPI Validation (only runs with ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX)

    func testValidationHarness_onVisibleElements() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        label.text = "Test Label"
        label.isAccessibilityElement = true
        container.addSubview(label)

        let button = UIButton(frame: CGRect(x: 0, y: 50, width: 100, height: 44))
        button.setTitle("Test Button", for: .normal)
        button.isAccessibilityElement = true
        container.addSubview(button)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(container)
        window.makeKeyAndVisible()

        let labelDivergences = label.ax_validateAgainstSPI()
        let buttonDivergences = button.ax_validateAgainstSPI()

        for d in labelDivergences {
            print("DIVERGENCE: \(d)")
        }
        for d in buttonDivergences {
            print("DIVERGENCE: \(d)")
        }

        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            XCTAssertEqual(labelDivergences.count, 0, "Label divergences: \(labelDivergences)")
            XCTAssertEqual(buttonDivergences.count, 0, "Button divergences: \(buttonDivergences)")
        #else
            XCTAssertEqual(labelDivergences.count, 0, "Without SPI, validation should return empty")
        #endif
    }

    func testValidationHarness_onScrollViewContent() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 2000)

        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        label.text = "Inside scroll"
        label.isAccessibilityElement = true
        scrollView.addSubview(label)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(scrollView)
        window.makeKeyAndVisible()

        let scrollDivergences = scrollView.ax_validateAgainstSPI()
        let labelDivergences = label.ax_validateAgainstSPI()

        for d in scrollDivergences {
            print("SCROLL DIVERGENCE: \(d)")
        }
        for d in labelDivergences {
            print("LABEL DIVERGENCE: \(d)")
        }

        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            XCTAssertEqual(scrollDivergences.count, 0, "ScrollView divergences: \(scrollDivergences)")
            XCTAssertEqual(labelDivergences.count, 0, "Label-in-scroll divergences: \(labelDivergences)")
        #endif
    }
}
