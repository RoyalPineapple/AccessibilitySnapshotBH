import AccessibilitySnapshotCore
import AccessibilitySnapshotParser

/// The hierarchy with graph-derived context applied to each element: the spoken description and
/// hint are composed from the element's container context, and every node gets an overlay color
/// index — the render-ready tree behind the container-aware legend.
///
/// Elements use their flat traversal-order index (matching the `markers` array), so element
/// overlays render identically whether or not container mode is enabled.
/// Containers get a separate sequential index starting after all elements.
///
/// Like the materializing flatten, the walk derives context from the FULL child set (so "X of N"
/// counts and data-table headers are complete) while emitting only on-screen elements unless
/// `includesOffscreen` is set; a container whose children are all filtered out is dropped (an empty
/// container is not an accessibility element).
@available(iOS 16.0, *)
public struct ContextualizedHierarchy {
    /// A node with context applied and its assigned color index.
    public enum Node {
        case element(AccessibilityElement, colorIndex: Int)
        case container(AccessibilityContainer, colorIndex: Int, children: [Node])
    }

    /// The contextualized nodes in hierarchy order.
    public let nodes: [Node]

    /// Applies context to a hierarchy tree, composing each element's description and hint and
    /// assigning color indices.
    public static func build(
        from hierarchy: [AccessibilityHierarchy],
        verbosity: VerbosityConfiguration = .verbose,
        includesOffscreen: Bool = false
    ) -> ContextualizedHierarchy {
        var elementCounter = 0
        var containerCounter = 0

        func includes(_ element: AccessibilityElement) -> Bool {
            includesOffscreen || element.visibility == .onscreen
        }

        func countElements(in nodes: [AccessibilityHierarchy]) -> Int {
            nodes.reduce(0) { count, node in
                switch node {
                case let .element(element, _):
                    return count + (includes(element) ? 1 : 0)
                case let .container(_, children):
                    return count + countElements(in: children)
                }
            }
        }

        let totalElements = countElements(in: hierarchy)

        func hasIncludedElement(_ node: AccessibilityHierarchy) -> Bool {
            switch node {
            case let .element(element, _):
                return includes(element)
            case let .container(_, children):
                return children.contains { hasIncludedElement($0) }
            }
        }

        func assign(_ node: AccessibilityHierarchy, context: DerivedContext?) -> Node? {
            switch node {
            case let .element(element, _):
                guard includes(element) else { return nil }
                let index = elementCounter
                elementCounter += 1
                // Fold the graph-derived context into the rendered strings — the same composition
                // the materializing flatten performs, so both legend modes speak identically.
                let (description, hint) = element.description(context: context, verbosity: verbosity)
                return .element(element.withDescription(description, hint: hint), colorIndex: index)

            case let .container(container, children):
                guard hasIncludedElement(node) else { return nil }
                // Pre-order: a container is numbered before any containers nested inside it.
                let index = totalElements + containerCounter
                containerCounter += 1
                let assignedChildren = children.enumerated().compactMap { childIndex, child in
                    assign(child, context: container.derivedContext(forChildAt: childIndex, in: children))
                }
                return .container(container, colorIndex: index, children: assignedChildren)
            }
        }

        let assignedNodes = hierarchy.compactMap { assign($0, context: nil) }
        return ContextualizedHierarchy(nodes: assignedNodes)
    }
}
