import CoreGraphics

/// Information about a container node
public struct AccessibilityContainer: Hashable, Codable {
    /// The type of accessibility container with its associated data
    public enum ContainerType: Hashable, Codable {
        /// A semantic grouping with optional label, value, and identifier
        case semanticGroup(label: String?, value: String?, identifier: String?)

        /// A list container (affects rotor navigation)
        case list

        /// A landmark container (affects rotor navigation)
        case landmark

        /// A data table with row and column counts
        case dataTable(rowCount: Int, columnCount: Int)

        /// A tab bar container (detected via .tabBar trait)
        case tabBar

        /// A navigation bar container (detected via UINavigationBar class).
        /// UIKit does not expose a public accessibility trait for navigation
        /// bars, so detection relies on the class. Consumers use the frame to
        /// compute "top of safe swipe region" — below the nav bar, above the
        /// content — without having to walk the view hierarchy themselves.
        case navigationBar

        /// A scrollable container (UIScrollView or subclass) with content dimensions
        case scrollable(contentSize: CGSize)
    }

    /// The type of container with its associated data
    public let type: ContainerType

    /// Container's frame in the root view's coordinate space (for visualization)
    public let frame: CGRect

    public init(type: ContainerType, frame: CGRect) {
        self.type = type
        self.frame = frame
    }
}
