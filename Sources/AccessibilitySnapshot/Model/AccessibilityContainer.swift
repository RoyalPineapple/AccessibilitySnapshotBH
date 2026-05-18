import CoreGraphics

/// Information about a container node
public struct AccessibilityContainer: Hashable, Codable, Sendable {
    /// The type of accessibility container with its associated data
    public enum ContainerType: Hashable, Codable, Sendable {
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

        /// A scrollable container (UIScrollView or subclass) with content dimensions
        case scrollable(contentSize: AccessibilitySize)
    }

    /// The type of container with its associated data
    public let type: ContainerType

    /// Container's frame in the root view's coordinate space (for visualization)
    public let frame: AccessibilityRect

    /// Whether this container marks an accessibility modal boundary.
    ///
    /// Modal boundaries hide lower siblings from VoiceOver traversal. The
    /// parser preserves them even when the view would otherwise be flattened
    /// so consumers can apply the same scope across multiple windows.
    public let isModalBoundary: Bool

    public init(type: ContainerType, frame: AccessibilityRect, isModalBoundary: Bool = false) {
        self.type = type
        self.frame = frame
        self.isModalBoundary = isModalBoundary
    }

    public init(type: ContainerType, frame: CGRect, isModalBoundary: Bool = false) {
        self.init(type: type, frame: AccessibilityRect(frame), isModalBoundary: isModalBoundary)
    }
}
