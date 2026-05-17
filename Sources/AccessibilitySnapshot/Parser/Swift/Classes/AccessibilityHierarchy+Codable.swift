import UIKit

// MARK: - UIAccessibilityTraits Names

private enum AccessibilityTraitCatalog {
    /// Known trait names for human-readable encoding
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
        // Private traits — core set (used by the parser for element classification)
        (.textEntry, "textEntry"),
        (.isEditing, "isEditing"),
        (.secureTextField, "secureTextField"),
        (.backButton, "backButton"),
        (.tabBarItem, "tabBarItem"),
        (.textArea, "textArea"),
        (.switchButton, "switchButton"),
        // Private traits — extended set (from AXRuntime, surfaced for diagnostics)
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
}

public extension UIAccessibilityTraits {
    /// Known trait names for human-readable encoding.
    static let knownTraits: [(trait: UIAccessibilityTraits, name: String)] = AccessibilityTraitCatalog.knownTraits

    /// The set of all known trait name strings. Authoritative source of truth —
    /// cross-platform mirrors (e.g. HeistElement.knownTraitNames) must equal this set.
    static let knownTraitNames: Set<String> = AccessibilityTraitCatalog.knownTraitNames

    /// Human-readable names for all traits present in this bitmask.
    var traitNames: [String] {
        Self.knownTraits.compactMap { contains($0.trait) ? $0.name : nil }
    }

    /// Reconstruct a bitmask from an array of trait name strings.
    /// Unknown names are silently ignored.
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
                // Parse unknown raw values: "unknown(12345)"
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
        // Encode any unknown traits as raw values for forward compatibility
        if remainingRawValue != 0 {
            names.append("unknown(\(remainingRawValue))")
        }
        try container.encode(names)
    }
}

// MARK: - AccessibilityShape Codable

extension AccessibilityShape {
    private enum CodingKeys: String, CodingKey {
        case type
        case frame
        case pathElements
    }

    private enum ShapeType: String, Codable {
        case frame
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ShapeType.self, forKey: .type)

        switch type {
        case .frame:
            let frame = try container.decode(AccessibilityRect.self, forKey: .frame)
            self = .frame(frame)

        case .path:
            let elements = try container.decode([AccessibilityPathElement].self, forKey: .pathElements)
            self = .path(elements)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .frame(frame):
            try container.encode(ShapeType.frame, forKey: .type)
            try container.encode(frame, forKey: .frame)

        case let .path(elements):
            try container.encode(ShapeType.path, forKey: .type)
            try container.encode(elements, forKey: .pathElements)
        }
    }
}
