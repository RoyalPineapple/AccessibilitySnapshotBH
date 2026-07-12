public enum AccessibilityHierarchy: Hashable, Codable, Sendable {
    case element(AccessibilityElement, traversalIndex: Int)
    case container(AccessibilityContainer, children: [AccessibilityHierarchy])

    public var children: [AccessibilityHierarchy] {
        switch self {
        case .element:
            return []
        case let .container(_, children):
            return children
        }
    }

    public var sortIndex: Int {
        switch self {
        case let .element(_, index):
            return index
        case let .container(_, children):
            return children.map { $0.sortIndex }.min() ?? Int.max
        }
    }
}

public extension AccessibilityHierarchy {
    func forEach(_ apply: (AccessibilityHierarchy) -> Void) {
        apply(self)
        for child in children {
            child.forEach(apply)
        }
    }
}

public extension Array where Element == AccessibilityHierarchy {
    /// Collapses the tree into its elements in traversal order, materializing each element's spoken
    /// `description` and `hint` as it goes: flattening is the moment the container structure is
    /// dropped, so it is also the moment each element's graph-derived context (list/landmark
    /// boundaries, "X of N", data-table coordinates) is folded into its final rendered string.
    ///
    /// The composition reads only the element's stored facts (label/value/traits/raw hint) plus the
    /// context derived from its position under the nearest enclosing container — never a previously
    /// composed string — so the returned elements are a terminal, render-ready projection.
    ///
    /// Call this on the full (unpruned) tree so "X of N" counts and data-table header text derive
    /// from the complete child set; prune the returned array by `visibility` afterwards.
    func flattenToElements(verbosity: VerbosityConfiguration = .verbose) -> [AccessibilityElement] {
        var pairs: [(index: Int, element: AccessibilityElement)] = []

        func collect(from node: AccessibilityHierarchy, context: DerivedContext?) {
            switch node {
            case let .element(element, index):
                let (description, hint) = element.description(context: context, verbosity: verbosity)
                pairs.append((index, element.withDescription(description, hint: hint)))
            case let .container(container, children):
                for (childIndex, child) in children.enumerated() {
                    collect(from: child, context: container.derivedContext(forChildAt: childIndex, in: children))
                }
            }
        }

        forEach { collect(from: $0, context: nil) }
        return pairs.sorted { $0.index < $1.index }.map { $0.element }
    }

    func flattenToContainers() -> [AccessibilityContainer] {
        var containers: [AccessibilityContainer] = []

        func collect(from node: AccessibilityHierarchy) {
            switch node {
            case .element: break
            case let .container(container, children):
                containers.append(container)
                children.forEach { collect(from: $0) }
            }
        }

        forEach { collect(from: $0) }
        return containers
    }
}
