import UIKit

// MARK: - Public API Surface (always compiled)

public extension NSObject {
    /// Visibility gate. Returns false for elements that should be excluded from
    /// the accessibility tree.
    ///
    /// Public fallback checks hidden, alpha, and accessibilityFrame size on UIView.
    /// Non-UIView objects always return true.
    var ax_shouldBeProcessed: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.ShouldBeProcessed.self) ?? true
        #else
            guard let view = self as? UIView else { return true }
            if view.isHidden || view.alpha <= 0 { return false }
            let axFrame = view.accessibilityFrame
            if axFrame.width < 1, axFrame.height < 1 { return false }
            return true
        #endif
    }

    /// Returns true if this element owns scroll semantics for accessibility.
    /// UIScrollView and its subclasses return true.
    var ax_isScrollAncestor: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.IsScrollAncestor.self) ?? false
        #else
            return self is UIScrollView
        #endif
    }

    /// Returns the nearest scroll ancestor in the accessibility tree.
    /// Walks accessibilityContainer upward, stops at the first UIScrollView.
    var ax_scrollParent: UIScrollView? {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.ScrollParent.self) as? UIScrollView
        #else
            var current: NSObject? = self
            while let container = (current?.value(forKey: "accessibilityContainer")) as? NSObject {
                if let scrollView = container as? UIScrollView {
                    return scrollView
                }
                current = container
            }
            return nil
        #endif
    }

    /// Returns true when children should be traversed via the index API
    /// rather than the subview walk.
    ///
    /// Public fallback: not an accessibility element AND accessibilityElementCount
    /// returns a real number (not NSNotFound).
    var ax_hasOrderedChildren: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.HasOrderedChildren.self) ?? false
        #else
            if isAccessibilityElement { return false }
            return accessibilityElementCount() != NSNotFound
        #endif
    }

    /// Context flag: true on every element inside a scrollable region.
    /// Use ax_isScrollAncestor for "is this THE scroll view?"
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
    /// ancestor's viewport. Synchronous — no animation, no run loop needed.
    /// Returns true on success and on no-op (already visible).
    /// Returns false if the element has an invalid frame (not yet laid out).
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
            let insets = scrollView.adjustedContentInset
            let targetY = max(
                -insets.top,
                min(
                    elementFrame.origin.y - insets.top,
                    scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
                )
            )
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: targetY),
                animated: false
            )
            return true
        #endif
    }

    /// Returns true if this element overrides the zero-frame visibility gate.
    /// Views returning true will be processed even when accessibilityFrame < 1x1.
    /// Used by SwiftUI's _UIInheritedView.
    var ax_overridesInvalidFrames: Bool {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.OverridesInvalidFrames.self) ?? false
        #else
            return false
        #endif
    }

    /// Label + localized value — the closest in-process approximation of what
    /// VoiceOver would speak for this element.
    /// Returns nil if unavailable.
    var ax_speakThisString: String? {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            return ax_private(PrivateAXRuntime.SpeakThisString.self) as? String
        #else
            var parts: [String] = []
            if let label = accessibilityLabel, !label.isEmpty { parts.append(label) }
            if let value = accessibilityValue, !value.isEmpty { parts.append(value) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        #endif
    }
}

// MARK: - Validation Harness

public extension NSObject {
    /// Compares every public API fallback against its SPI equivalent on this
    /// element. Returns an array of divergence descriptions. Empty = full parity.
    ///
    /// Call this on accessibility elements during testing to identify where our
    /// public API implementations diverge from VoiceOver's ground truth.
    func ax_validateAgainstSPI() -> [String] {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            var divergences: [String] = []
            let elementDesc = accessibilityLabel ?? String(describing: type(of: self))

            // Visibility
            let publicProcessed = ax_publicShouldBeProcessed
            let spiProcessed = ax_private(PrivateAXRuntime.ShouldBeProcessed.self) ?? true
            if publicProcessed != spiProcessed {
                divergences.append(
                    "[\(elementDesc)] shouldBeProcessed: public=\(publicProcessed) spi=\(spiProcessed)"
                )
            }

            // Scroll ancestor
            let publicScrollAncestor = self is UIScrollView
            let spiScrollAncestor = ax_private(PrivateAXRuntime.IsScrollAncestor.self) ?? false
            if publicScrollAncestor != spiScrollAncestor {
                divergences.append(
                    "[\(elementDesc)] isScrollAncestor: public=\(publicScrollAncestor) spi=\(spiScrollAncestor)"
                )
            }

            // Ordered children
            let publicOrdered = ax_publicHasOrderedChildren
            let spiOrdered = ax_private(PrivateAXRuntime.HasOrderedChildren.self) ?? false
            if publicOrdered != spiOrdered {
                divergences.append(
                    "[\(elementDesc)] hasOrderedChildren: public=\(publicOrdered) spi=\(spiOrdered)"
                )
            }

            // Scroll parent
            let publicParent = ax_publicScrollParent
            let spiParent = ax_private(PrivateAXRuntime.ScrollParent.self) as? UIScrollView
            if publicParent !== spiParent {
                divergences.append(
                    "[\(elementDesc)] scrollParent: public=\(publicParent.map { "\(type(of: $0))" } ?? "nil") "
                        + "spi=\(spiParent.map { "\(type(of: $0))" } ?? "nil")"
                )
            }

            // Scrollable context
            let publicScrollable = ax_publicIsScrollable
            let spiScrollable = ax_private(PrivateAXRuntime.IsScrollable.self) ?? false
            if publicScrollable != spiScrollable {
                divergences.append(
                    "[\(elementDesc)] isScrollable: public=\(publicScrollable) spi=\(spiScrollable)"
                )
            }

            // Override invalid frames
            let publicOverrides = false
            let spiOverrides = ax_private(PrivateAXRuntime.OverridesInvalidFrames.self) ?? false
            if publicOverrides != spiOverrides {
                divergences.append(
                    "[\(elementDesc)] overridesInvalidFrames: public=\(publicOverrides) spi=\(spiOverrides)"
                )
            }

            // Speak-this string
            let publicSpeak = ax_publicSpeakThisString
            let spiSpeak = ax_private(PrivateAXRuntime.SpeakThisString.self) as? String
            if publicSpeak != spiSpeak {
                divergences.append(
                    "[\(elementDesc)] speakThisString: public=\(publicSpeak ?? "nil") spi=\(spiSpeak ?? "nil")"
                )
            }

            return divergences
        #else
            return []
        #endif
    }

    // MARK: - Public API implementations (exposed for validation)

    fileprivate var ax_publicShouldBeProcessed: Bool {
        guard let view = self as? UIView else { return true }
        if view.isHidden || view.alpha <= 0 { return false }
        let axFrame = view.accessibilityFrame
        if axFrame.width < 1 && axFrame.height < 1 { return false }
        return true
    }

    fileprivate var ax_publicHasOrderedChildren: Bool {
        if isAccessibilityElement { return false }
        return accessibilityElementCount() != NSNotFound
    }

    fileprivate var ax_publicScrollParent: UIScrollView? {
        var current: NSObject? = self
        while let container = (current?.value(forKey: "accessibilityContainer")) as? NSObject {
            if let scrollView = container as? UIScrollView {
                return scrollView
            }
            current = container
        }
        return nil
    }

    fileprivate var ax_publicIsScrollable: Bool {
        guard let view = self as? UIView else { return false }
        var current: UIView? = view.superview
        while let parent = current {
            if parent is UIScrollView { return true }
            current = parent.superview
        }
        return false
    }

    fileprivate var ax_publicSpeakThisString: String? {
        var parts: [String] = []
        if let label = accessibilityLabel, !label.isEmpty { parts.append(label) }
        if let value = accessibilityValue, !value.isEmpty { parts.append(value) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Geometry Sort Comparator

public extension NSObject {
    /// VoiceOver's geometry comparator. Compares two elements for traversal order.
    /// Returns NSComparisonResult values: -1 (ascending), 0 (same), 1 (descending).
    ///
    /// The callable entry point is accessibilityCompareGeometry: (no underscore).
    /// The underscored variant is an internal C function not registered with the
    /// ObjC runtime — respondsToSelector: returns NO for it.
    func ax_compareGeometry(to other: NSObject) -> ComparisonResult {
        #if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
            let sel = NSSelectorFromString("accessibilityCompareGeometry:")
            guard responds(to: sel) else { return .orderedSame }
            let imp = method(for: sel)
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Int
            let fn = unsafeBitCast(imp, to: Fn.self)
            let result = fn(self, sel, other)
            switch result {
            case ...(-1): return .orderedAscending
            case 1...: return .orderedDescending
            default: return .orderedSame
            }
        #else
            return .orderedSame
        #endif
    }
}

// MARK: - Private AX Runtime (compiled out unless opted in)

#if ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX

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

    /// Every private accessibility method the parser validates against.
    /// Each entry documents what the SPI does, its return values, and what
    /// public API behavior it validates.
    private enum PrivateAXRuntime {
        /// Visibility gate for the accessibility tree walker.
        ///
        /// On UIView: checks hidden, alpha, accessibilityFrame size, out-of-bounds.
        /// On NSObject: always returns YES.
        ///
        /// Our public fallback checks hidden, alpha, and accessibilityFrame < 1x1.
        /// It misses the out-of-bounds check and the _accessibilityOverridesInvalidFrames
        /// escape hatch.
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
        enum IsScrollAncestor: PrivateAXBoolSelector {
            static let name = "_accessibilityIsScrollAncestor"
        }

        /// Returns the nearest scroll ancestor in the accessibility tree.
        ///
        /// Walks the accessibilityContainer chain upward, stops at the first
        /// object where _accessibilityIsScrollAncestor returns YES.
        /// Uses includeSelf:YES, so calling on a UIScrollView returns self.
        ///
        /// On SwiftUI AccessibilityNode: returns HostingScrollView — the chain is
        ///   AccessibilityNode → PlatformGroupContainer → HostingScrollView
        ///   (PlatformContainer is skipped — not in the accessibilityContainer chain).
        enum ScrollParent: PrivateAXObjectSelector {
            static let name = "_accessibilityScrollParent"
        }

        /// Returns YES when children should be traversed via the index API.
        ///
        /// Default implementation: if isAccessibilityElement → NO.
        /// Otherwise: accessibilityElementCount() != NSNotFound.
        enum HasOrderedChildren: PrivateAXBoolSelector {
            static let name = "_accessibilityHasOrderedChildren"
        }

        /// Context flag: YES on every element inside a scrollable region.
        ///
        /// WARNING: returns YES on everything inside a scroll view — UIImageView,
        /// UISwitch, UISlider, UILabel, everything. It means "an ancestor can
        /// scroll me."
        ///
        /// Use IsScrollAncestor for "is this THE scroll view?"
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

        /// Returns YES if this element overrides the zero-frame visibility gate.
        ///
        /// Default: NO on NSObject (literal return, no storage).
        /// UIView: backed by per-instance associated-object bool.
        /// Only known override: SwiftUI._UIInheritedView (iOS 26+).
        ///
        /// When YES, the visibility gate accepts the element even if its
        /// accessibilityFrame is smaller than 1x1.
        enum OverridesInvalidFrames: PrivateAXBoolSelector {
            static let name = "_accessibilityOverridesInvalidFrames"
        }

        /// Label + localized value — the closest in-process approximation of what
        /// VoiceOver would speak for this element.
        ///
        /// Returns a string combining accessibilityLabel with a localized version
        /// of accessibilityValue (e.g., "0" becomes "Off" for toggles).
        /// Does NOT include role names ("Switch Button") or hints
        /// ("Double tap to toggle setting") — those are assembled out-of-process
        /// by VoiceOver's server.
        enum SpeakThisString: PrivateAXObjectSelector {
            static let name = "_accessibilitySpeakThisString"
        }
    }

    private extension NSObject {
        func ax_private<S: PrivateAXSelector>(_: S.Type) -> S.Return? {
            guard responds(to: NSSelectorFromString(S.name)) else { return nil }
            return S.invoke(on: self)
        }
    }

    // MARK: - SPI Parser

    extension AccessibilityHierarchyParser {
        /// Parses the accessibility hierarchy using UIKit's internal
        /// _accessibilityLeafDescendantsWithOptions: API with scanner groups enabled.
        /// Returns the same [AccessibilityHierarchy] type as the public API parser.
        ///
        /// This is a thin shell — UIKit does the walk, the sort, the filtering,
        /// the container nesting. We just map the output format.
        public func parseAccessibilityHierarchyUsingSPI(
            in root: UIView,
            rotorResultLimit: Int = AccessibilityElement.defaultRotorResultLimit
        ) -> [AccessibilityHierarchy] {
            let optionsClass: AnyClass? = NSClassFromString("UIAccessibilityElementTraversalOptions")
            guard let optionsClass else { return [] }

            let options = (optionsClass as! NSObject.Type).perform(NSSelectorFromString("alloc"))!
                .takeUnretainedValue()
                .perform(NSSelectorFromString("init"))!
                .takeUnretainedValue() as! NSObject

            let setSorted = NSSelectorFromString("setSorted:")
            let imp1 = options.method(for: setSorted)
            typealias SetBoolFn = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(imp1, to: SetBoolFn.self)(options, setSorted, true)

            let setScannerGroups = NSSelectorFromString("setShouldReturnScannerGroups:")
            let imp2 = options.method(for: setScannerGroups)
            unsafeBitCast(imp2, to: SetBoolFn.self)(options, setScannerGroups, true)

            let sel = NSSelectorFromString("_accessibilityLeafDescendantsWithOptions:")
            guard root.responds(to: sel) else { return [] }

            let result = root.perform(sel, with: options)?.takeUnretainedValue()

            guard let groups = result as? [Any] else { return [] }

            var traversalIndex = 0
            return mapScannerGroups(groups, in: root, rotorResultLimit: rotorResultLimit, traversalIndex: &traversalIndex)
        }

        private func mapScannerGroups(
            _ groups: [Any],
            in root: UIView,
            rotorResultLimit: Int,
            traversalIndex: inout Int
        ) -> [AccessibilityHierarchy] {
            var result: [AccessibilityHierarchy] = []

            for item in groups {
                if let dict = item as? NSDictionary {
                    let children = dict["GroupElements"] as? [Any] ?? []
                    let groupLabel = (dict["GroupLabel"] as? NSAttributedString)?.string
                        ?? dict["GroupLabel"] as? String

                    let mappedChildren = mapScannerGroups(
                        children, in: root, rotorResultLimit: rotorResultLimit,
                        traversalIndex: &traversalIndex
                    )

                    if mappedChildren.isEmpty { continue }

                    if groupLabel != nil || mappedChildren.count > 1 {
                        let containerType: AccessibilityContainer.ContainerType
                        if let label = groupLabel {
                            containerType = .semanticGroup(label: label, value: nil, identifier: nil)
                        } else {
                            containerType = .semanticGroup(label: nil, value: nil, identifier: nil)
                        }

                        let childFrames = mappedChildren.compactMap { node -> CGRect? in
                            switch node {
                            case let .element(element, _):
                                return element.shape.frame.cgRect
                            case let .container(container, _):
                                return container.frame.cgRect
                            }
                        }
                        let unionFrame = childFrames.reduce(CGRect.null) { $0.union($1) }

                        let container = AccessibilityContainer(
                            type: containerType,
                            frame: AccessibilityRect(unionFrame)
                        )
                        result.append(.container(container, children: mappedChildren))
                    } else {
                        result.append(contentsOf: mappedChildren)
                    }

                } else if let element = item as? NSObject {
                    let built = buildElement(
                        from: element, context: nil, in: root,
                        rotorResultLimit: rotorResultLimit
                    )
                    result.append(.element(built, traversalIndex: traversalIndex))
                    traversalIndex += 1
                }
            }

            return result
        }
    }

#endif // ACCESSIBILITY_SNAPSHOT_ENABLE_PRIVATE_AX
