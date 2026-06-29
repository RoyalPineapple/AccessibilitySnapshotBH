# SPI-Backed Parser — PrivateAXSelector Spec

## What This Is

A rewrite of the accessibility parser to use UIKit's own accessibility SPI as the
primary implementation, wrapped in the `PrivateAXSelector` gateway from PR #324.
Each SPI is documented inline in the code. Public API fallback compiled in by
default. Snapshot/test builds opt in via `ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX`.

The parser stops inventing its own tree walk and calls the same methods VoiceOver
calls. The code IS the documentation.

## Implementation

### File 1: `PrivateAXSelector.swift`

This is the complete SPI gateway. Every private accessibility method the parser
uses is cataloged here with full inline documentation.

```swift
import UIKit

// MARK: - Public API Surface (always compiled)

extension NSObject {

    /// Visibility gate. Returns false for elements that should be excluded.
    /// Public fallback: manual hidden/alpha/frame checks on UIView.
    var ax_shouldBeProcessed: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.ShouldBeProcessed.self) ?? true
        #else
        guard let view = self as? UIView else { return true }
        if view.isHidden || view.alpha <= 0 { return false }
        if view.frame.size == .zero
            && (view.clipsToBounds || view.isAccessibilityElement || view.accessibilityElements != nil) {
            return false
        }
        return true
        #endif
    }

    /// Returns true if this element owns scroll semantics for accessibility.
    /// UIScrollView and its subclasses return true.
    /// Public fallback: `self is UIScrollView`.
    var ax_isScrollAncestor: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.IsScrollAncestor.self) ?? false
        #else
        return self is UIScrollView
        #endif
    }

    /// Returns the nearest scroll ancestor in the accessibility tree.
    /// Walks accessibilityContainer upward, stops at the first scroll ancestor.
    /// Public fallback: walk accessibilityContainer checking `is UIScrollView`.
    var ax_scrollParent: UIScrollView? {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.ScrollParent.self) as? UIScrollView
        #else
        var current: NSObject? = self
        while let container = current?.accessibilityContainer as? NSObject {
            if let scrollView = container as? UIScrollView {
                return scrollView
            }
            current = container
        }
        return nil
        #endif
    }

    /// Returns true when children should be traversed via the index API
    /// (accessibilityElementCount / accessibilityElementAtIndex:) rather
    /// than the subview walk.
    /// Public fallback: check if the class overrides the index API methods.
    var ax_hasOrderedChildren: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.HasOrderedChildren.self) ?? false
        #else
        return ax_overridesAccessibilityContainerIndexing
        #endif
    }

    /// Context flag: true on every element inside a scrollable region.
    /// WARNING: returns true on UIImageView, UISwitch, UISlider — everything
    /// inside a scroll view. Use ax_isScrollAncestor for "is this THE scroll view?"
    /// Public fallback: check if any ancestor is UIScrollView.
    var ax_isScrollable: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.IsScrollable.self) ?? false
        #else
        guard let view = self as? UIView else { return false }
        var current: UIView? = view.superview
        while let parent = current {
            if parent is UIScrollView { return true }
            current = parent.superview
        }
        return false
        #endif
    }

    /// Scrolls the minimum distance to reveal this element in its scroll
    /// ancestor's viewport. Uses setContentOffset:animated:NO internally.
    /// Returns true on success and on no-op (already visible).
    /// Returns false if the element has (+Inf, +Inf) frame — not yet laid out.
    /// Public fallback: find scroll parent via ax_scrollParent, compute offset
    /// manually, call setContentOffset.
    @discardableResult
    func ax_scrollToVisible() -> Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_private(PrivateAXRuntime.BaseScrollToVisible.self) ?? false
        #else
        guard let scrollView = ax_scrollParent else { return false }
        let elementFrame = accessibilityFrame
        guard elementFrame.origin.x.isFinite, elementFrame.origin.y.isFinite else {
            return false
        }
        let visibleRect = CGRect(
            origin: scrollView.contentOffset,
            size: scrollView.bounds.size
        )
        if visibleRect.contains(elementFrame) { return true }
        let targetY = max(
            -scrollView.adjustedContentInset.top,
            min(
                elementFrame.origin.y - scrollView.adjustedContentInset.top,
                scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
            )
        )
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetY), animated: false)
        return true
        #endif
    }

    /// Expanded/collapsed state for disclosure-style elements.
    /// (From PR #324 — SwiftUI overrides the private getter; the public iOS 18
    /// getter misses SwiftUI elements.)
    var ax_expandedStatus: AccessibilityElement.ExpandedStatus {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
        return ax_privateExpandedStatus
        #else
        return ax_publicExpandedStatus
        #endif
    }

    private var ax_publicExpandedStatus: AccessibilityElement.ExpandedStatus {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            return AccessibilityElement.ExpandedStatus(rawValue: accessibilityExpandedStatus.rawValue) ?? .unsupported
        }
        #endif
        return .unsupported
    }

    // MARK: - Internal helpers

    fileprivate var ax_overridesAccessibilityContainerIndexing: Bool {
        let selectors = [
            #selector(NSObject.accessibilityElementCount),
            #selector(NSObject.accessibilityElement(at:)),
        ]
        return selectors.contains { selector in
            guard let objectMethod = class_getInstanceMethod(type(of: self), selector) else {
                return false
            }
            guard let baseMethod = class_getInstanceMethod(NSObject.self, selector) else {
                return true
            }
            return method_getImplementation(objectMethod) != method_getImplementation(baseMethod)
        }
    }
}

// MARK: - Private AX Runtime (compiled out unless opted in)

#if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX

/// A catalog entry describing a single private Apple accessibility API.
///
/// Each conformer names a selector and the Swift type its getter returns.
/// Callers invoke the selector through `NSObject.ax_private(_:)`, which
/// resolves it safely at runtime via `method(for:)` + `unsafeBitCast`.
///
/// KVC is deliberately avoided: plain NSObjects respond to some private
/// accessibility selectors but are not KVC-compliant for them.
private protocol PrivateAXSelector {
    associatedtype Return
    static var name: String { get }
    static func invoke(on target: NSObject) -> Return?
}

private protocol PrivateAXBoolSelector: PrivateAXSelector where Return == Bool {}
private extension PrivateAXBoolSelector {
    static func invoke(on target: NSObject) -> Bool? {
        let selector = NSSelectorFromString(name)
        let imp = target.method(for: selector)
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: Fn.self)(target, selector)
    }
}

private protocol PrivateAXIntSelector: PrivateAXSelector where Return == Int {}
private extension PrivateAXIntSelector {
    static func invoke(on target: NSObject) -> Int? {
        let selector = NSSelectorFromString(name)
        let imp = target.method(for: selector)
        typealias Fn = @convention(c) (AnyObject, Selector) -> Int
        return unsafeBitCast(imp, to: Fn.self)(target, selector)
    }
}

private protocol PrivateAXObjectSelector: PrivateAXSelector where Return == AnyObject {}
private extension PrivateAXObjectSelector {
    static func invoke(on target: NSObject) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        let imp = target.method(for: selector)
        typealias Fn = @convention(c) (AnyObject, Selector) -> AnyObject?
        return unsafeBitCast(imp, to: Fn.self)(target, selector)
    }
}

/// Namespace for known private accessibility selectors. Each nested type
/// documents what the SPI does, its return values, which public API it
/// replaces, and what the research confidence level is.
private enum PrivateAXRuntime {

    /// Visibility gate for the accessibility tree walker.
    ///
    /// On UIView: checks hidden, alpha, frame, bounds. Returns NO for views
    /// that should be skipped entirely.
    /// On NSObject: always returns YES (non-UIView elements are always processed).
    ///
    /// The parser's manual checks (hidden || alpha <= 0 || zero-frame-with-clips)
    /// approximate this but miss edge cases around accessibilityFrame vs frame,
    /// and don't handle non-UIView subclasses correctly.
    enum ShouldBeProcessed: PrivateAXBoolSelector {
        static let name = "_accessibilityShouldBeProcessed"
    }

    /// Returns YES on views that own scroll semantics for accessibility.
    ///
    /// Default: NO on NSObject.
    /// UIScrollView and subclasses: YES.
    /// SwiftUI HostingScrollView: YES (inherited from UIScrollView).
    /// PlatformContainer: NO.
    /// PlatformGroupContainer: NO.
    ///
    /// This is the predicate _accessibilityScrollParent uses internally.
    /// Walking accessibilityContainer upward and checking this predicate
    /// is the public+SPI equivalent of _accessibilityScrollParent.
    enum IsScrollAncestor: PrivateAXBoolSelector {
        static let name = "_accessibilityIsScrollAncestor"
    }

    /// Returns the nearest scroll ancestor in the accessibility tree.
    ///
    /// Walks the accessibilityContainer chain upward, stops at the first
    /// object where _accessibilityIsScrollAncestor returns YES.
    /// Uses includeSelf:YES, so calling on a UIScrollView returns self.
    ///
    /// On scroll views: returns self.
    /// On elements not inside a scroll view: returns nil.
    /// On SwiftUI AccessibilityNode: returns HostingScrollView — the chain is
    ///   AccessibilityNode → PlatformGroupContainer → HostingScrollView
    ///   (PlatformContainer is skipped — not in the accessibilityContainer chain).
    enum ScrollParent: PrivateAXObjectSelector {
        static let name = "_accessibilityScrollParent"
    }

    /// Returns YES when children should be traversed via the index API.
    ///
    /// When YES, the tree walker uses accessibilityElementCount +
    /// accessibilityElement(at:) for ordered children. When NO, it walks
    /// subviews or accessibilityElements array.
    enum HasOrderedChildren: PrivateAXBoolSelector {
        static let name = "_accessibilityHasOrderedChildren"
    }

    /// Context flag: YES on every element inside a scrollable region.
    ///
    /// WARNING: this is NOT "is this a scroll view?" It returns YES on
    /// everything inside a scroll view — UIImageView, UISwitch, UISlider,
    /// UILabel, everything. It means "an ancestor can scroll me."
    ///
    /// Use IsScrollAncestor for "is this THE scroll view?"
    /// Use this for "is this element inside a scrollable context?"
    enum IsScrollable: PrivateAXBoolSelector {
        static let name = "_accessibilityIsScrollable"
    }

    /// Scrolls minimum distance to reveal this element in its scroll ancestor.
    ///
    /// Finds the scroll parent automatically. Uses setContentOffset:animated:NO
    /// internally — synchronous, no run loop needed. Scrolls the minimum
    /// distance (doesn't center).
    ///
    /// Returns YES on success and on no-op (already visible).
    /// Returns NO if frame is (+Inf, +Inf) — not yet laid out in lazy container.
    enum BaseScrollToVisible: PrivateAXBoolSelector {
        static let name = "_accessibilityBaseScrollToVisible"
    }

    /// Expanded/collapsed state for disclosure-style elements.
    ///
    /// Returns 0 (unsupported), 1 (expanded), or 2 (collapsed).
    ///
    /// SwiftUI overrides this to read from its internal graph. The public
    /// iOS 18 getter reads from separate storage and returns 0 for all
    /// SwiftUI nodes. VoiceOver reads this private getter.
    ///
    /// On stock UIView/NSObject, the public setter syncs to this getter.
    /// No private setter exists.
    enum ExpandedStatus: PrivateAXIntSelector {
        static let name = "_accessibilityExpandedStatus"
    }
}

private extension NSObject {
    func ax_private<S: PrivateAXSelector>(_: S.Type) -> S.Return? {
        guard responds(to: NSSelectorFromString(S.name)) else { return nil }
        return S.invoke(on: self)
    }

    var ax_privateExpandedStatus: AccessibilityElement.ExpandedStatus {
        guard let rawValue = ax_private(PrivateAXRuntime.ExpandedStatus.self) else {
            return .unsupported
        }
        return AccessibilityElement.ExpandedStatus(rawValue: rawValue) ?? .unsupported
    }
}

#endif // ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
```

### File 2: Parser changes in `AccessibilityHierarchyParser.swift`

The changes are surgical — replace specific heuristics with `ax_*` calls.

#### Visibility gate (replaces lines 843-848)

```swift
// BEFORE:
if let `self` = self as? UIView,
   self.isHidden || self.alpha <= 0
   || (self.frame.size == .zero && (self.clipsToBounds || self.isAccessibilityElement || self.accessibilityElements != nil))
{
    return []
}

// AFTER:
guard ax_shouldBeProcessed else {
    return []
}
```

#### Child enumeration heuristic (replaces shouldUseAccessibilityContainerElements)

```swift
// BEFORE:
private var shouldUseAccessibilityContainerElements: Bool {
    if isAppleFrameworkObject { return false }
    if type(of: self) == NSObject.self { return false }
    if self is UIView { return false }
    return overridesAccessibilityContainerIndexing
}

// AFTER:
private var shouldUseAccessibilityContainerElements: Bool {
    if self is UIView { return false }
    return ax_hasOrderedChildren
}
```

The bundle identifier check (`isAppleFrameworkObject`) and the method-override
check (`overridesAccessibilityContainerIndexing`) are both approximations of
`_accessibilityHasOrderedChildren`. With SPI enabled, the SPI gives the exact
answer. With SPI disabled, `ax_hasOrderedChildren` falls back to the existing
`overridesAccessibilityContainerIndexing` check — same behavior as today.

#### Scroll detection (replaces scrollableContentSize else branch)

```swift
// BEFORE:
private func scrollableContentSize(for view: UIView) -> CGSize? {
    let contentSize: CGSize
    if let scrollView = view as? UIScrollView {
        guard scrollView.isScrollEnabled else { return nil }
        contentSize = scrollView.contentSize
    } else {
        guard view.subviews.contains(where: { $0 is UIScrollView }) else {
            return nil
        }
        let contentFrame = view.subviews.reduce(CGRect.zero) { union, child in
            union.union(child.frame)
        }
        contentSize = contentFrame.size
    }
    return contentSize.isScrollableContentSize(for: view.bounds.size) ? contentSize : nil
}

// AFTER:
private func scrollableContentSize(for view: UIView) -> CGSize? {
    guard let scrollView = view as? UIScrollView ?? view.ax_childScrollView else {
        return nil
    }
    guard scrollView.isScrollEnabled else { return nil }
    let contentSize = scrollView.contentSize
    return contentSize.isScrollableContentSize(for: view.bounds.size) ? contentSize : nil
}
```

With a helper:

```swift
private extension UIView {
    /// Finds the UIScrollView child for non-UIScrollView containers
    /// (e.g. SwiftUI PlatformContainer wrapping HostingScrollView).
    var ax_childScrollView: UIScrollView? {
        subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
    }
}
```

This always reads `contentSize` from the actual UIScrollView, never from a
frame-union heuristic. For PlatformContainer, it finds HostingScrollView as
a direct child and reads its `contentSize`. For UIScrollView itself, the `as?`
cast succeeds directly.

### What doesn't change

These parts of the parser stay as-is:

- **`buildElement(from:context:in:rotorResultLimit:)`** — reads public API
  properties (label, value, traits, frame, path, activationPoint, etc.)
- **`sortedElements(for:explicitlyOrdered:in:...)`** — geometry sorting logic
  (could be replaced by `_accessibilityCompareGeometry:` but that's a separate
  change with its own risk profile)
- **`context(for:from:...)`** — series/tab/list/landmark context derivation
- **`foldNodes(_:sortedElements:elements:in:makeElement:makeContainer:)`** — the
  generic fold
- **`containerInfo(for:)`** — container type detection (semanticGroup, list,
  landmark, dataTable, tabBar) — all based on public API
- **Modal masking** — `accessibilityViewIsModal` is public API
- **Custom content, custom rotors, custom actions** — all public API
- **Shape/frame/activation point computation** — all public API
- **Tab bar button detection** — uses `NSClassFromString` which is already
  runtime-resolved

### What gets deleted

- `isAppleFrameworkObject` — bundle identifier check for Apple frameworks
- `overridesAccessibilityContainerIndexing` — method-override heuristic (moves
  into fallback path of `ax_hasOrderedChildren`)
- The `else` branch comment about `_accessibilityIsScrollable`

## How BH Uses This

BH defines `ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX` in its build settings.
The parser gives BH VoiceOver-accurate results.

For scroll detection, BH can additionally use `ax_scrollParent` at interaction
time to resolve the scroll view for any element — replacing the
`scrollDispatchView()` subview-search heuristic in TheBurglar.

For scroll-to-visible, BH can call `ax_scrollToVisible()` on any element to
reveal it — replacing SemanticReveal's manual offset computation.

## Testing Strategy

Run both paths and compare:

```swift
// In snapshot tests:
let publicResult = parser.parseAccessibilityHierarchy(in: root)  // default path

// Temporarily enable SPI for comparison:
let spiResult = parser.parseAccessibilityHierarchy(in: root)     // SPI path

XCTAssertEqual(
    publicResult.flattenToElements().map(\.description),
    spiResult.flattenToElements().map(\.description)
)
```

Divergences are test failures. Each divergence is either a bug in the public API
path (fix it) or a known VoiceOver behavior we weren't matching (document it).

## Migration Order

1. **Land PR #324** — establishes the pattern and compile flag
2. **Add `PrivateAXBoolSelector` and `PrivateAXObjectSelector`** to the protocol
   family
3. **Add `ax_shouldBeProcessed`** — visibility gate, smallest behavioral change
4. **Add `ax_isScrollAncestor` and `ax_scrollParent`** — scroll detection
5. **Add `ax_hasOrderedChildren`** — child enumeration
6. **Add `ax_scrollToVisible`** — scroll-to-visible (BH integration)
7. **Add `ax_isScrollable`** — context flag (BH scroll inventory)
8. **Run parity tests** — compare SPI vs public API output across all snapshot
   tests
9. **Remove dead code** — `isAppleFrameworkObject`, the `else` branch in
   `scrollableContentSize`, the old `accessibilityIsScrollable` extension

## Relationship to Focus Walker Spec

The focus-walker-spec.md covers BH's scroll exploration cleanup. This spec covers
the parser's SPI gateway. They're complementary:

- **This spec**: how the parser discovers and characterizes elements
- **Focus walker spec**: how BH discovers offscreen content and presents it

The focus walker's scan primitive calls the parser. With SPI enabled, each parse
is more accurate. The scroll inventory uses public API regardless.

## Open Questions

1. **Geometry sort.** The callable entry point is `accessibilityCompareGeometry:`
   (no underscore) — the underscored variant is an internal C function not
   registered with the ObjC runtime. The public selector is on
   `NSObject(AXPrivCategory)`, returns `long long` (NSComparisonResult-shaped
   -1/0/1), takes one `id` argument. Considers sort frame, window, scene, RTL,
   orientation, scroll parent, supplementary headers/footers, and
   `_accessibilityAlwaysOrderedFirst`. Needs a `PrivateAXComparatorSelector`
   protocol variant for the one-arg invoke pattern.

2. **`_accessibilityLeafDescendantsWithOptions:` as a full replacement.** This
   single call could replace the entire tree walk. But it returns a flat array
   (no container structure) or a scanner-group tree (different container model).
   Mapping scanner groups back to our container types needs more research. The
   incremental approach (replace individual heuristics with SPI calls, keep the
   tree walk structure) is lower risk.

3. **iOS version support.** The SPI methods exist on iOS 15+. The compile flag
   already gates them behind `responds(to:)`, so older OS versions gracefully
   get nil and fall through to the default. But we should document minimum
   versions per SPI.

4. **~~`_accessibilityUserTestingChildren`~~** — **Ruled out.** Live probing
   confirmed it returns empty arrays for SwiftUI HostingScrollView even with
   the app running (not an LLDB-stopped artifact). SwiftUI AccessibilityNodes
   are only reachable via the snapshot tree or via `accessibilityElements` on
   the hosting view. This SPI is UIKit-only — it doesn't cross the SwiftUI
   bridge. Our parser's existing `accessibilityElements` → `subviews` dual
   path already handles this correctly.
