import AccessibilitySnapshotModel
import UIKit

// MARK: - UIAccessibilityTraits Codable

#if compiler(>=6.0)
    extension UIAccessibilityTraits: @retroactive Codable {}
#else
    extension UIAccessibilityTraits: Codable {}
#endif

public extension UIAccessibilityTraits {
    static let knownTraits: [(trait: UIAccessibilityTraits, name: String)] = [
        // Public UIAccessibilityTraits (bits 0-14, 16-17)
        (.button, "button"),
        (.link, "link"),
        (.image, "image"),
        (.selected, "selected"),
        (.playsSound, "playsSound"),
        (.keyboardKey, "keyboardKey"),
        (.staticText, "staticText"),
        (.summaryElement, "summaryElement"),
        (.notEnabled, "notEnabled"),
        (.updatesFrequently, "updatesFrequently"),
        (.searchField, "searchField"),
        (.startsMediaSession, "startsMediaSession"),
        (.adjustable, "adjustable"),
        (.allowsDirectInteraction, "allowsDirectInteraction"),
        (.causesPageTurn, "causesPageTurn"),
        (.header, "header"),
        (.tabBar, "tabBar"),
        (.textEntry, "textEntry"),
        (.isEditing, "isEditing"),
        (.secureTextField, "secureTextField"),
        (.backButton, "backButton"),
        (.tabBarItem, "tabBarItem"),
        (.textArea, "textArea"),
        (.switchButton, "switchButton"),
        (.webContent, "webContent"),
        (.pickerElement, "pickerElement"),
        (.radioButton, "radioButton"),
        (.launchIcon, "launchIcon"),
        (.statusBarElement, "statusBarElement"),
        (.inactive, "inactive"),
        (.footer, "footer"),
        (.autoCorrectCandidate, "autoCorrectCandidate"),
        (.deleteKey, "deleteKey"),
        (.selectionDismissesItem, "selectionDismissesItem"),
        (.visited, "visited"),
        (.spacer, "spacer"),
        (.tableIndex, "tableIndex"),
        (.map, "map"),
        (.textOperationsAvailable, "textOperationsAvailable"),
        (.draggable, "draggable"),
        (.popupButton, "popupButton"),
        (.menuItem, "menuItem"),
        (.alert, "alert"),
    ]

    static let knownTraitNames: Set<String> = Set(knownTraits.map(\.name))

    var traitNames: [String] {
        Self.knownTraits.compactMap { contains($0.trait) ? $0.name : nil }
    }

    static func fromNames(_ names: [String]) -> UIAccessibilityTraits {
        var traits = UIAccessibilityTraits()
        for name in names {
            if let known = knownTraits.first(where: { $0.name == name }) {
                traits.insert(known.trait)
            }
        }
        return traits
    }
}

// MARK: - AccessibilityTraits Codable

public extension AccessibilityTraits {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let traitNames = try container.decode([String].self)

        var traits = UIAccessibilityTraits()
        var unknownValues: UInt64 = 0

        for name in traitNames {
            if let known = UIAccessibilityTraits.knownTraits.first(where: { $0.name == name }) {
                traits.insert(known.trait)
            } else if name.hasPrefix("unknown("), name.hasSuffix(")") {
                let startIndex = name.index(name.startIndex, offsetBy: 8)
                let endIndex = name.index(name.endIndex, offsetBy: -1)
                if let rawValue = UInt64(name[startIndex ..< endIndex]) {
                    unknownValues |= rawValue
                }
            }
        }

        self = AccessibilityTraits(rawValue: traits.rawValue | unknownValues)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var names = traitNames
        var remainingRawValue = rawValue
        for (trait, _) in UIAccessibilityTraits.knownTraits where contains(AccessibilityTraits(trait)) {
            remainingRawValue &= ~AccessibilityTraits(trait).rawValue
        }

        if remainingRawValue != 0 {
            names.append("unknown(\(remainingRawValue))")
        }
        try container.encode(names)
    }
}
