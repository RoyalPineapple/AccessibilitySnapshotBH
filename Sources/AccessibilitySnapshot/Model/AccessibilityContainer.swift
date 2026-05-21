public struct AccessibilityContainer: Hashable, Codable, Sendable {
    public enum ContainerType: Hashable, Codable, Sendable {
        case semanticGroup(label: String?, value: String?, identifier: String?)
        case list
        case landmark
        case dataTable(rowCount: Int, columnCount: Int)
        case tabBar
        case scrollable(contentSize: AccessibilitySize)
    }

    public let type: ContainerType
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
}
