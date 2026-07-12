import Foundation

public extension Array where Element == AccessibilityHierarchy {
    /// Returns the same tree with every element's `description` and `hint` (re)materialized from its
    /// stored properties, the container context derived from its graph position, and `verbosity`.
    ///
    /// This is the delivery-time replacement for parse-time description baking: the parser stamps only
    /// raw facts (label/value/traits/…) plus the container structure, and the final spoken string is
    /// composed here, late, so it can be re-gated by any `VerbosityConfiguration`. At `.verbose` it
    /// reproduces the historical parse-time string.
    ///
    /// Context is derived per element from the *nearest enclosing container* via
    /// `AccessibilityContainer.derivedContext(forChildAt:in:)` over the full (unpruned) child set, so
    /// run this before `onscreen()`; data-table header text is resolved while every header is still
    /// present.
    func materializingDescriptions(verbosity: VerbosityConfiguration = .verbose) -> [AccessibilityHierarchy] {
        map { $0.materializingDescriptions(context: nil, verbosity: verbosity) }
    }
}

private extension AccessibilityHierarchy {
    /// - Parameter context: the context this node receives from its parent container (nil at the root
    ///   or under a container that lends no context).
    func materializingDescriptions(
        context: DerivedContext?,
        verbosity: VerbosityConfiguration
    ) -> AccessibilityHierarchy {
        switch self {
        case let .element(element, traversalIndex):
            let (description, hint) = element.description(context: context, verbosity: verbosity)
            return .element(element.withDescription(description, hint: hint), traversalIndex: traversalIndex)

        case let .container(container, children):
            let materializedChildren = children.enumerated().map { index, child -> AccessibilityHierarchy in
                let childContext = container.derivedContext(forChildAt: index, in: children)
                return child.materializingDescriptions(context: childContext, verbosity: verbosity)
            }
            return .container(container, children: materializedChildren)
        }
    }
}
