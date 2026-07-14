import UIKit

/// Typed gateway over Apple's private element-traversal engine — the same app-side machinery
/// VoiceOver consumes over IPC for reading order (`UIAccessibilityElementTraversalOptions` plus
/// the bulk leaf walk and the cursor-walk primitive).
///
/// Conceptual sibling of the `PrivateAXRuntime` gateway: every SPI selector string lives here and
/// nowhere else; callers get typed, optional-safe methods that return `nil` when the runtime
/// doesn't provide the SPI. Observation-only — parser output never depends on anything in this
/// file. The sole consumer is `ParserFidelity` scoring.
enum PrivateAXTraversal {
    /// A `UIAccessibilityElementTraversalOptions` instance. `direction` is left at its default
    /// (next); `sorted` is set explicitly so both walkers return geometry-ordered results.
    struct TraversalOptions {
        let object: NSObject

        init?(visibleFrameOnly: Bool) {
            guard let optionsClass = NSClassFromString("UIAccessibilityElementTraversalOptions") as? NSObject.Type else {
                return nil
            }
            object = optionsClass.init()
            Self.setBool(object, "setSorted:", true)
            Self.setBool(object, "setShouldOnlyIncludeElementsWithVisibleFrame:", visibleFrameOnly)
        }

        private static func setBool(_ object: NSObject, _ selectorName: String, _ value: Bool) {
            let selector = NSSelectorFromString(selectorName)
            guard object.responds(to: selector) else { return }
            typealias SetBoolFunction = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(object.method(for: selector), to: SetBoolFunction.self)(object, selector, value)
        }
    }

    /// The bulk walk: every leaf element under `root` in traversal order
    /// (`_accessibilityLeafDescendantsWithOptions:`).
    static func leafDescendants(of root: UIView, options: TraversalOptions) -> [NSObject]? {
        let selector = NSSelectorFromString("_accessibilityLeafDescendantsWithOptions:")
        guard root.responds(to: selector) else { return nil }
        return root.perform(selector, with: options.object)?.takeUnretainedValue() as? [NSObject]
    }

    /// The cursor-walk primitive VoiceOver's swipe consumes
    /// (`_accessibilityElementsInDirectionWithCount:options:`): one call returns every element
    /// following `anchor` in traversal order, across the whole screen.
    static func elementsFollowing(_ anchor: NSObject, options: TraversalOptions, limit: UInt = 1024) -> [NSObject]? {
        let selector = NSSelectorFromString("_accessibilityElementsInDirectionWithCount:options:")
        guard anchor.responds(to: selector) else { return nil }
        typealias WalkFunction = @convention(c) (NSObject, Selector, UInt, NSObject) -> NSArray?
        let result = unsafeBitCast(anchor.method(for: selector), to: WalkFunction.self)(anchor, selector, limit, options.object)
        return result as? [NSObject]
    }

    /// One hop up the element's `accessibilityContainer` chain (covers vended cell proxies whose
    /// container is a view inside the parsed root).
    static func container(of element: NSObject) -> NSObject? {
        let selector = NSSelectorFromString("accessibilityContainer")
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue() as? NSObject
    }
}
