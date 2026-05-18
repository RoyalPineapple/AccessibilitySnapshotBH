import AccessibilitySnapshotModel
import UIKit

// MARK: - UIAccessibilityTraits Names

public extension UIAccessibilityTraits {
    /// Known trait names for human-readable encoding.
    static let knownTraits: [(trait: UIAccessibilityTraits, name: String)] = AccessibilityTraits.knownTraits.map {
        (trait: UIAccessibilityTraits(rawValue: $0.trait.rawValue), name: $0.name)
    }

    /// The set of all known trait name strings. Authoritative source of truth —
    /// cross-platform mirrors (e.g. HeistElement.knownTraitNames) must equal this set.
    static let knownTraitNames: Set<String> = AccessibilityTraits.knownTraitNames

    /// Human-readable names for all traits present in this bitmask.
    var traitNames: [String] {
        AccessibilityTraits(self).traitNames
    }

    /// Reconstruct a bitmask from an array of trait name strings.
    /// Unknown names are silently ignored.
    static func fromNames(_ names: [String]) -> UIAccessibilityTraits {
        AccessibilityTraits.fromNames(names).uiAccessibilityTraits
    }
}
