import AccessibilitySnapshotModel
import Foundation
import XCTest

/// Coverage for the delivery transform (trim + off-screen classification) and the
/// `AccessibilityShape.boundingRect` helper it relies on. Model-only; no UIKit.
final class AccessibilityDeliveryTests: XCTestCase {
    // MARK: - Helpers

    private func element(
        _ description: String,
        visibility: AccessibilityVisibility,
        shape: AccessibilityShape = .frame(.zero)
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: description, label: description, value: nil, traits: [],
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: shape, activationPoint: .zero, usesDefaultActivationPoint: true,
            customActions: [], customContent: [], customRotors: [],
            accessibilityLanguage: nil, respondsToUserInteraction: false,
            visibility: visibility
        )
    }

    private func scrollable(_ frame: AccessibilityRect, children: [AccessibilityHierarchy]) -> AccessibilityHierarchy {
        .container(
            AccessibilityContainer(type: .scrollable(contentSize: AccessibilitySize(width: frame.width, height: frame.height * 3)), frame: frame),
            children: children
        )
    }

    // MARK: - Untrimmed equivalence

    func testUntrimmedEqualsFlattenToElements() {
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element("A", visibility: .onscreen), traversalIndex: 0),
            .element(element("B", visibility: .offscreen), traversalIndex: 1),
        ]
        XCTAssertEqual(hierarchy.deliver(options: .untrimmed).elements, hierarchy.flattenToElements())
        XCTAssertTrue(hierarchy.deliver(options: .untrimmed).scrollContainerSummaries.isEmpty)
    }

    // MARK: - Trimming

    func testTrimmedDropsOffscreenElements() {
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element("A", visibility: .onscreen), traversalIndex: 0),
            .element(element("B", visibility: .offscreen), traversalIndex: 1),
            .element(element("C", visibility: .onscreen), traversalIndex: 2),
        ]
        let delivered = hierarchy.deliver(options: .trimmed)
        XCTAssertEqual(delivered.elements.map(\.label), ["A", "C"])
    }

    // MARK: - Framed classification (above / below the viewport)

    func testFramedElementsClassifyAboveAndBelow() {
        let viewport = AccessibilityRect(x: 0, y: 100, width: 100, height: 100) // visible y: 100...200
        let hierarchy = [scrollable(viewport, children: [
            .element(element("above", visibility: .offscreen, shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 40))), traversalIndex: 0),
            .element(element("visible", visibility: .onscreen, shape: .frame(AccessibilityRect(x: 0, y: 120, width: 100, height: 40))), traversalIndex: 1),
            .element(element("below", visibility: .offscreen, shape: .frame(AccessibilityRect(x: 0, y: 300, width: 100, height: 40))), traversalIndex: 2),
        ])]
        let summary = hierarchy.deliver(options: .trimmed).scrollContainerSummaries.first
        XCTAssertEqual(summary?.trimmedAbove, 1)
        XCTAssertEqual(summary?.trimmedBelow, 1)
        XCTAssertEqual(summary?.trimmedElsewhere, 0)
    }

    // MARK: - Zero-frame classification (enumeration order fallback)

    func testZeroFrameElementsClassifyByEnumerationOrder() {
        let viewport = AccessibilityRect(x: 0, y: 0, width: 100, height: 100)
        let hierarchy = [scrollable(viewport, children: [
            .element(element("before", visibility: .offscreen), traversalIndex: 0), // zero frame
            .element(element("visible", visibility: .onscreen, shape: .frame(AccessibilityRect(x: 0, y: 10, width: 100, height: 40))), traversalIndex: 1),
            .element(element("after1", visibility: .offscreen), traversalIndex: 2),
            .element(element("after2", visibility: .offscreen), traversalIndex: 3),
        ])]
        let summary = hierarchy.deliver(options: .trimmed).scrollContainerSummaries.first
        XCTAssertEqual(summary?.trimmedAbove, 1)
        XCTAssertEqual(summary?.trimmedBelow, 2)
    }

    // MARK: - No scrollable ancestor → trimmed but uncounted

    func testOffscreenWithoutScrollableAncestorIsTrimmedButUncounted() {
        let hierarchy: [AccessibilityHierarchy] = [
            .element(element("A", visibility: .onscreen), traversalIndex: 0),
            .element(element("B", visibility: .offscreen), traversalIndex: 1),
        ]
        let delivered = hierarchy.deliver(options: .trimmed)
        XCTAssertEqual(delivered.elements.map(\.label), ["A"])
        XCTAssertTrue(delivered.scrollContainerSummaries.isEmpty)
    }

    // MARK: - Nested scrollables attribute to nearest

    func testNestedScrollablesEachOwnTheirTrimmedChildren() {
        let outerViewport = AccessibilityRect(x: 0, y: 0, width: 100, height: 400)
        let innerViewport = AccessibilityRect(x: 0, y: 0, width: 100, height: 100)
        let inner = scrollable(innerViewport, children: [
            .element(element("inner-off", visibility: .offscreen, shape: .frame(AccessibilityRect(x: 0, y: 300, width: 100, height: 40))), traversalIndex: 1),
        ])
        let hierarchy = [scrollable(outerViewport, children: [
            .element(element("outer-off", visibility: .offscreen, shape: .frame(AccessibilityRect(x: 0, y: 900, width: 100, height: 40))), traversalIndex: 0),
            inner,
        ])]
        let summaries = hierarchy.deliver(options: .trimmed).scrollContainerSummaries
        XCTAssertEqual(summaries.count, 2)
        // The outer container's own tally must not absorb the inner container's trimmed child.
        let outer = summaries.first { $0.container.frame == outerViewport }
        XCTAssertEqual(outer?.trimmedBelow, 1)
    }

    // MARK: - boundingRect

    func testBoundingRectOfFrameIsFrame() {
        let rect = AccessibilityRect(x: 5, y: 6, width: 7, height: 8)
        XCTAssertEqual(AccessibilityShape.frame(rect).boundingRect, rect)
    }

    func testBoundingRectOfPathEnclosesAllPoints() {
        let shape = AccessibilityShape.path([
            .move(to: AccessibilityPoint(x: 10, y: 10)),
            .line(to: AccessibilityPoint(x: 30, y: 5)),
            .curve(to: AccessibilityPoint(x: 20, y: 40), control1: AccessibilityPoint(x: 0, y: 0), control2: AccessibilityPoint(x: 50, y: 20)),
            .closeSubpath,
        ])
        XCTAssertEqual(shape.boundingRect, AccessibilityRect(x: 0, y: 0, width: 50, height: 40))
    }

    func testBoundingRectOfEmptyPathIsZero() {
        XCTAssertEqual(AccessibilityShape.path([]).boundingRect, .zero)
    }
}
