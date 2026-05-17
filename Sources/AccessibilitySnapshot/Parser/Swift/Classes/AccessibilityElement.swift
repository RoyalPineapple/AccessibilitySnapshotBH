import UIKit

/// A type alias for backwards compatibility.
public typealias AccessibilityMarker = AccessibilityElement

public struct AccessibilityElement: Hashable, Codable, Sendable {
    /// Default number of rotor results to collect in each direction.
    public static let defaultRotorResultLimit: Int = 10

    // MARK: - Public Types

    public enum Shape: Equatable {
        /// Accessibility frame, in the coordinate space of the view being snapshotted.
        case frame(CGRect)

        /// Accessibility path, in the coordinate space of the view being snapshotted.
        case path(UIBezierPath)
    }

    public struct CustomRotor: Equatable, CustomStringConvertible, Codable, Sendable {
        public struct ResultMarker: Equatable, CustomStringConvertible, Codable, Sendable {
            public let elementDescription: String
            public let rangeDescription: String?
            public let shape: AccessibilityShape?

            public init(elementDescription: String, rangeDescription: String? = nil, shape: AccessibilityShape? = nil) {
                self.elementDescription = elementDescription
                self.rangeDescription = rangeDescription
                self.shape = shape
            }

            public init(elementDescription: String, rangeDescription: String? = nil, shape: Shape?) {
                self.init(
                    elementDescription: elementDescription,
                    rangeDescription: rangeDescription,
                    shape: shape.map(AccessibilityShape.init)
                )
            }

            public var description: String {
                guard let rangeDescription else {
                    return elementDescription
                }
                return "\(elementDescription) \(rangeDescription)"
            }
        }

        public var name: String
        public var resultMarkers: [AccessibilityElement.CustomRotor.ResultMarker] = []
        public let limit: AccessibilityRotorResultLimit

        public init(name: String, resultMarkers: [ResultMarker] = [], limit: AccessibilityRotorResultLimit = .none) {
            self.name = name
            self.resultMarkers = resultMarkers
            self.limit = limit
        }

        init?(from: UIAccessibilityCustomRotor, parentElement: NSObject, root: UIView, context: AccessibilityHierarchyParser.Context? = nil, resultLimit: Int) {
            guard from.isKnownRotorType else { return nil }
            name = from.displayName(locale: parentElement.accessibilityLanguage)
            guard resultLimit > 0 else {
                limit = .none
                resultMarkers = []
                return
            }
            let collected = from.collectAllResults(nextLimit: resultLimit, previousLimit: resultLimit)
            limit = AccessibilityRotorResultLimit(collected.limit)
            resultMarkers = collected.results.compactMap { result in
                guard let element = result.targetElement as? NSObject else { return nil }
                var description = element.accessibilityDescription(context: context).description
                var shape: Shape? = AccessibilityHierarchyParser.accessibilityShape(for: element, in: root)

                if let range = result.targetRange,
                   let input = element as? UITextInput
                {
                    if let path = input.accessibilityPath(for: range) {
                        let converted = root.convert(path, from: input as? UIView)
                        shape = .path(converted)
                    }
                    if let substring = input.text(in: range) {
                        description = substring
                    }
                    return ResultMarker(elementDescription: description, rangeDescription: range.formatted(in: input), shape: shape)
                }
                return ResultMarker(elementDescription: description, rangeDescription: nil, shape: shape)
            }
        }

        public var description: String {
            return name + ": " + resultMarkers.map { $0.description }.joined(separator: "\n")
        }
    }

    public struct CustomContent: Codable, Equatable, Sendable {
        public var label: String
        public var value: String
        public var isImportant: Bool

        public init(label: String, value: String, isImportant: Bool = false) {
            self.label = label
            self.value = value
            self.isImportant = isImportant
        }

        @available(iOS 14.0, *)
        init(from: AXCustomContent) {
            label = from.label
            value = from.value
            isImportant = from.importance == .high
        }
    }

    public struct CustomAction: Equatable, Codable, Sendable {
        public var name: String
        public var image: AccessibilityImageData?

        public init(name: String, image: AccessibilityImageData? = nil) {
            self.name = name
            self.image = image
        }

        public init(name: String, image: UIImage?) {
            self.init(name: name, image: AccessibilityImageData(image))
        }

        @available(iOS 14.0, *)
        init(from: UIAccessibilityCustomAction) {
            name = from.name
            image = AccessibilityImageData(from.image)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case imageData
            case imageScale
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)

            if let imageData = try container.decodeIfPresent(Data.self, forKey: .imageData) {
                let scale = try container.decodeIfPresent(Double.self, forKey: .imageScale) ?? 1.0
                image = AccessibilityImageData(pngData: imageData, scale: scale)
            } else {
                image = nil
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)

            if let image {
                try container.encode(image.pngData, forKey: .imageData)
                try container.encode(image.scale, forKey: .imageScale)
            }
        }
    }

    // MARK: - Public Properties

    /// The description of the accessibility element that will be read by VoiceOver when the element is brought into
    /// focus.
    public let description: String

    public let label: String?

    public let value: String?

    public let traits: AccessibilityTraits

    /// A unique identifier for the element, primarily used in UI tests for locating and interacting with elements.
    /// This identifier is not visible to users.
    public let identifier: String?

    /// A hint that will be read by VoiceOver if focus remains on the element after the `description` is read.
    public let hint: String?

    /// The labels that will be used by Voice Control for user input.
    /// These labels are displayed based on the `AccessibilityContentDisplayMode` configuration:
    /// - `.always`: Always shows user input labels
    /// - `.whenOverridden`: Shows labels only when they differ from default values (future enhancement)
    /// - `.never`: Never shows user input labels
    public let userInputLabels: [String]?

    /// The shape that will be highlighted on screen while the element is in focus.
    public let shape: AccessibilityShape

    /// The accessibility activation point, in the coordinate space of the view being snapshotted.
    public let activationPoint: AccessibilityPoint

    /// Whether or not the `activationPoint` is the default activation point for the object.
    ///
    /// For most elements, the default activation point is the midpoint of the element's accessibility frame. Certain
    /// elements have distinct defaults - for example, a `UISlider` puts its activation point at the center of its thumb
    /// by default.
    public let usesDefaultActivationPoint: Bool

    /// The custom actions supported by the element.
    public let customActions: [CustomAction]

    /// Any custom content included by the element.
    public let customContent: [CustomContent]

    /// Any custom rotors included by the element.
    public let customRotors: [CustomRotor]

    /// The language code of the language used to localize strings in the description.
    public let accessibilityLanguage: String?

    /// Whether the element performs an action based on user interaction.
    public let respondsToUserInteraction: Bool

    // MARK: - Initialization

    init(
        description: String,
        label: String?,
        value: String?,
        traits: AccessibilityTraits,
        identifier: String?,
        hint: String?,
        userInputLabels: [String]?,
        shape: AccessibilityShape,
        activationPoint: AccessibilityPoint,
        usesDefaultActivationPoint: Bool,
        customActions: [CustomAction],
        customContent: [CustomContent],
        customRotors: [CustomRotor],
        accessibilityLanguage: String?,
        respondsToUserInteraction: Bool
    ) {
        self.description = description
        self.label = label
        self.value = value
        self.traits = traits
        self.identifier = identifier
        self.hint = hint
        self.userInputLabels = userInputLabels
        self.shape = shape
        self.activationPoint = activationPoint
        self.usesDefaultActivationPoint = usesDefaultActivationPoint
        self.customActions = customActions
        self.customContent = customContent
        self.customRotors = customRotors
        self.accessibilityLanguage = accessibilityLanguage
        self.respondsToUserInteraction = respondsToUserInteraction
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(description)
        hasher.combine(label)
        hasher.combine(value)
        hasher.combine(traits)
        hasher.combine(identifier)
        hasher.combine(activationPoint.x)
        hasher.combine(activationPoint.y)
        switch shape {
        case let .frame(rect):
            hasher.combine(0)
            hasher.combine(rect.origin.x)
            hasher.combine(rect.origin.y)
            hasher.combine(rect.size.width)
            hasher.combine(rect.size.height)
        case let .path(path):
            let bounds = AccessibilityShape.path(path).frame
            hasher.combine(1)
            hasher.combine(bounds.origin.x)
            hasher.combine(bounds.origin.y)
            hasher.combine(bounds.size.width)
            hasher.combine(bounds.size.height)
        }
    }
}

public extension AccessibilityElement {
    var activationCGPoint: CGPoint {
        activationPoint.cgPoint
    }

    /// UIKit compatibility initializer for callers constructing parser values
    /// by hand. Stored geometry and traits remain parser-owned portable data.
    init(
        description: String,
        label: String?,
        value: String?,
        traits: UIAccessibilityTraits,
        identifier: String?,
        hint: String?,
        userInputLabels: [String]?,
        shape: Shape,
        activationPoint: CGPoint,
        usesDefaultActivationPoint: Bool,
        customActions: [CustomAction],
        customContent: [CustomContent],
        customRotors: [CustomRotor],
        accessibilityLanguage: String?,
        respondsToUserInteraction: Bool
    ) {
        self.init(
            description: description,
            label: label,
            value: value,
            traits: AccessibilityTraits(traits),
            identifier: identifier,
            hint: hint,
            userInputLabels: userInputLabels,
            shape: AccessibilityShape(shape),
            activationPoint: AccessibilityPoint(activationPoint),
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: customActions,
            customContent: customContent,
            customRotors: customRotors,
            accessibilityLanguage: accessibilityLanguage,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }
}
