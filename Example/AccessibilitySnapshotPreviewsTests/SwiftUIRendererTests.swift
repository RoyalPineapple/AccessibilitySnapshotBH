import AccessibilitySnapshotCore
@testable import AccessibilitySnapshotPreviewsDemo
import UIKit

@available(iOS 16.0, *)
final class SwiftUIRendererTests: AccessibilitySnapshotPreviewsTestCase {
    func testBasicAccessibilityDemo() {
        snapshotVerifyAccessibility(BasicAccessibilityDemo())
    }

    func testCustomActionsDemo() {
        snapshotVerifyAccessibility(CustomActionsDemo())
    }

    func testCustomRotorsDemo() {
        snapshotVerifyAccessibility(CustomRotorsDemo())
    }

    func testCustomContentDemo() {
        snapshotVerifyAccessibility(CustomContentDemo())
    }

    func testPathShapesDemo() {
        snapshotVerifyAccessibility(PathShapesDemo())
    }

    func testUnspokenTraitsDemo() {
        snapshotVerifyAccessibility(UnspokenTraitsDemoView())
    }

    func testContainerDemoWithoutContainers() {
        // TEMPORARY: record the missing 26.2 reference on CI (the 26.2 runtime is no longer
        // downloadable locally). Reverted once the recorded image is harvested from the artifact.
        recordMode = UIDevice.current.systemVersion == "26.2"
        snapshotVerifyAccessibility(
            ContainerDemo(),
            identifier: "no_containers"
        )
    }

    func testContainerDemo() {
        // TEMPORARY: see above.
        recordMode = UIDevice.current.systemVersion == "26.2"
        snapshotVerifyAccessibility(
            ContainerDemo(),
            configuration: .init(viewRenderingMode: .drawHierarchyInRect, showContainers: true)
        )
    }
}
