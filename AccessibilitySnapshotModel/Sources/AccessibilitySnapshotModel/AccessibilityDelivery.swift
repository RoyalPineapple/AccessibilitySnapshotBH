/// Options controlling how a parsed accessibility hierarchy is turned into the flat element list a
/// consumer renders. The parser always produces the full tree with every element flagged
/// `.onscreen`/`.offscreen`; trimming the off-screen ones is a delivery-time decision made here.
public struct DeliveryOptions: Hashable, Sendable {
    /// When `true`, elements flagged `.offscreen` are dropped from the delivered element list and
    /// counted into the enclosing scroll container's `ScrollContainerSummary` instead.
    public var trimsOffscreenElements: Bool

    public init(trimsOffscreenElements: Bool) {
        self.trimsOffscreenElements = trimsOffscreenElements
    }

    /// Drops off-screen elements (matches VoiceOver's visible-frame filtering). The snapshot
    /// product's default.
    public static let trimmed = DeliveryOptions(trimsOffscreenElements: true)

    /// Keeps every element the parser found. Equivalent to `flattenToElements()`.
    public static let untrimmed = DeliveryOptions(trimsOffscreenElements: false)
}

/// Counts of off-screen elements trimmed from a single scrollable container, bucketed by where
/// they sit relative to the container's visible viewport.
public struct ScrollContainerSummary: Hashable, Codable, Sendable {
    /// The `.scrollable` container the trimmed elements belong to.
    public let container: AccessibilityContainer
    /// Trimmed elements above the visible viewport (or, for zero-frame elements, ordered before the
    /// first on-screen sibling).
    public let trimmedAbove: Int
    /// Trimmed elements below the visible viewport (or ordered after the last on-screen sibling).
    public let trimmedBelow: Int
    /// Trimmed elements that are neither clearly above nor below (e.g. horizontal overflow, or
    /// indeterminate order).
    public let trimmedElsewhere: Int

    public init(container: AccessibilityContainer, trimmedAbove: Int, trimmedBelow: Int, trimmedElsewhere: Int) {
        self.container = container
        self.trimmedAbove = trimmedAbove
        self.trimmedBelow = trimmedBelow
        self.trimmedElsewhere = trimmedElsewhere
    }

    /// Whether this summary carries any nonzero count worth surfacing.
    public var isEmpty: Bool {
        trimmedAbove == 0 && trimmedBelow == 0 && trimmedElsewhere == 0
    }
}

/// The result of delivering a parsed hierarchy: the flat element list to render, plus per-scroll
/// container trim summaries (empty unless `DeliveryOptions.trimsOffscreenElements` dropped anything).
public struct DeliveredAccessibility: Hashable, Sendable {
    public let elements: [AccessibilityElement]
    public let scrollContainerSummaries: [ScrollContainerSummary]

    public init(elements: [AccessibilityElement], scrollContainerSummaries: [ScrollContainerSummary]) {
        self.elements = elements
        self.scrollContainerSummaries = scrollContainerSummaries
    }
}

public extension Array where Element == AccessibilityHierarchy {
    /// Flattens the hierarchy to the element list a consumer renders, applying `options`.
    ///
    /// With `.untrimmed` this is exactly `flattenToElements()`. With `.trimmed`, `.offscreen`
    /// elements are removed and tallied into a `ScrollContainerSummary` for their nearest
    /// enclosing `.scrollable` container.
    ///
    /// - Note: Context derivation (list/landmark boundaries, "X of N", data-table coordinates) is
    ///   composed separately from graph position; this transform preserves the ordered structure
    ///   that derivation reads.
    func deliver(options: DeliveryOptions) -> DeliveredAccessibility {
        guard options.trimsOffscreenElements else {
            return DeliveredAccessibility(elements: flattenToElements(), scrollContainerSummaries: [])
        }

        var summaries: [ScrollContainerSummary] = []

        // Walk containers depth-first; at each `.scrollable` node classify its trimmed descendants
        // relative to that container's frame and tally a summary.
        func visit(_ node: AccessibilityHierarchy, nearestScrollable: AccessibilityContainer?) {
            switch node {
            case .element:
                break
            case let .container(container, children):
                if case .scrollable = container.type {
                    let (above, below, elsewhere) = Self.classifyTrimmed(in: children, container: container)
                    if above + below + elsewhere > 0 {
                        summaries.append(
                            ScrollContainerSummary(
                                container: container,
                                trimmedAbove: above,
                                trimmedBelow: below,
                                trimmedElsewhere: elsewhere
                            )
                        )
                    }
                    for child in children {
                        visit(child, nearestScrollable: container)
                    }
                } else {
                    for child in children {
                        visit(child, nearestScrollable: nearestScrollable)
                    }
                }
            }
        }
        for node in self {
            visit(node, nearestScrollable: nil)
        }

        let trimmedElements = flattenToElements().filter { $0.visibility == .onscreen }
        return DeliveredAccessibility(elements: trimmedElements, scrollContainerSummaries: summaries)
    }

    /// Classifies the off-screen leaf elements directly beneath a scrollable container into
    /// above/below/elsewhere buckets. Framed elements compare against the container's viewport;
    /// zero-frame elements fall back to enumeration order relative to on-screen siblings.
    private static func classifyTrimmed(
        in children: [AccessibilityHierarchy],
        container: AccessibilityContainer
    ) -> (above: Int, below: Int, elsewhere: Int) {
        // Collect this container's leaf elements in order, stopping at nested scrollables (those
        // own their own summaries).
        var leaves: [AccessibilityElement] = []
        func collect(_ node: AccessibilityHierarchy) {
            switch node {
            case let .element(element, _):
                leaves.append(element)
            case let .container(inner, innerChildren):
                if case .scrollable = inner.type { return }
                for child in innerChildren {
                    collect(child)
                }
            }
        }
        for child in children {
            collect(child)
        }

        let firstOnscreen = leaves.firstIndex { $0.visibility == .onscreen }
        let lastOnscreen = leaves.lastIndex { $0.visibility == .onscreen }

        var above = 0, below = 0, elsewhere = 0
        for (index, leaf) in leaves.enumerated() where leaf.visibility == .offscreen {
            let rect = leaf.shape.boundingRect
            if rect.width > 0, rect.height > 0 {
                if rect.maxY <= container.frame.minY {
                    above += 1
                } else if rect.minY >= container.frame.maxY {
                    below += 1
                } else {
                    elsewhere += 1
                }
            } else if let first = firstOnscreen, index < first {
                above += 1
            } else if let last = lastOnscreen, index > last {
                below += 1
            } else {
                elsewhere += 1
            }
        }
        return (above, below, elsewhere)
    }
}
