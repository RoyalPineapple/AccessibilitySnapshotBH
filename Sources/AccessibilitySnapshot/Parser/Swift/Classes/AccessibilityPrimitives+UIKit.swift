import AccessibilitySnapshotModel
import UIKit

public extension AccessibilityPathElement {
    func apply(to path: UIBezierPath) {
        switch self {
        case let .move(to):
            path.move(to: to.cgPoint)
        case let .line(to):
            path.addLine(to: to.cgPoint)
        case let .quadCurve(to, control):
            path.addQuadCurve(to: to.cgPoint, controlPoint: control.cgPoint)
        case let .curve(to, control1, control2):
            path.addCurve(to: to.cgPoint, controlPoint1: control1.cgPoint, controlPoint2: control2.cgPoint)
        case .closeSubpath:
            path.close()
        }
    }
}

public extension AccessibilityTraits {
    init(_ traits: UIAccessibilityTraits) {
        self.init(rawValue: traits.rawValue)
    }

    var uiAccessibilityTraits: UIAccessibilityTraits {
        UIAccessibilityTraits(rawValue: rawValue)
    }
}

public extension AccessibilityShape {
    var bezierPath: UIBezierPath {
        switch self {
        case let .frame(rect):
            return UIBezierPath(rect: rect.cgRect)
        case let .path(elements):
            let path = UIBezierPath()
            for element in elements {
                element.apply(to: path)
            }
            return path
        }
    }

    init(_ path: UIBezierPath) {
        self = .path(AccessibilityPathElement.elements(from: path.cgPath))
    }
}

public extension AccessibilityRotorResultLimit {
    init(_ limit: UIAccessibilityCustomRotor.CollectedRotorResults.Limit) {
        switch limit {
        case .none:
            self = .none
        case let .underMaxCount(count):
            self = .underMaxCount(count)
        case .greaterThanMaxCount:
            self = .greaterThanMaxCount
        }
    }

    var uiAccessibilityLimit: UIAccessibilityCustomRotor.CollectedRotorResults.Limit {
        switch self {
        case .none:
            return .none
        case let .underMaxCount(count):
            return .underMaxCount(count)
        case .greaterThanMaxCount:
            return .greaterThanMaxCount
        }
    }
}

public extension AccessibilityImageData {
    init?(_ image: UIImage?) {
        guard let image, let pngData = image.pngData() else { return nil }
        self.init(pngData: pngData, scale: Double(image.scale))
    }

    var uiImage: UIImage? {
        UIImage(data: pngData, scale: CGFloat(scale))
    }
}

public extension AccessibilityElement {
    enum Shape: Equatable {
        case frame(CGRect)
        case path(UIBezierPath)
    }

    var activationCGPoint: CGPoint {
        activationPoint.cgPoint
    }

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

public extension AccessibilityShape {
    init(_ shape: AccessibilityElement.Shape) {
        switch shape {
        case let .frame(rect):
            self = .frame(AccessibilityRect(rect))
        case let .path(path):
            self = .path(AccessibilityPathElement.elements(from: path.cgPath))
        }
    }

    var legacyShape: AccessibilityElement.Shape {
        switch self {
        case let .frame(rect):
            return .frame(rect.cgRect)
        case let .path(elements):
            let path = UIBezierPath()
            for element in elements {
                element.apply(to: path)
            }
            return .path(path)
        }
    }
}

public extension AccessibilityElement.CustomAction {
    init(name: String, image: UIImage?) {
        self.init(name: name, image: AccessibilityImageData(image))
    }

    @available(iOS 14.0, *)
    init(from: UIAccessibilityCustomAction) {
        self.init(name: from.name, image: from.image)
    }
}

public extension AccessibilityElement.CustomContent {
    @available(iOS 14.0, *)
    init(from: AXCustomContent) {
        self.init(label: from.label, value: from.value, isImportant: from.importance == .high)
    }
}

extension AccessibilityElement.CustomRotor {
    init?(
        from: UIAccessibilityCustomRotor,
        parentElement: NSObject,
        root: UIView,
        context: AccessibilityHierarchyParser.Context? = nil,
        resultLimit: Int
    ) {
        guard from.isKnownRotorType else { return nil }
        let name = from.displayName(locale: parentElement.accessibilityLanguage)
        guard resultLimit > 0 else {
            self.init(name: name, resultMarkers: [], limit: .none)
            return
        }

        let collected = from.collectAllResults(nextLimit: resultLimit, previousLimit: resultLimit)
        let limit = AccessibilityRotorResultLimit(collected.limit)
        let resultMarkers: [AccessibilityElement.CustomRotor.ResultMarker] = collected.results.compactMap { result in
            guard let element = result.targetElement as? NSObject else { return nil }
            var description = element.accessibilityDescription(context: context).description
            var shape: AccessibilityShape? = AccessibilityHierarchyParser.accessibilityShape(for: element, in: root)

            if let range = result.targetRange,
               let input = element as? UITextInput
            {
                if let path = input.accessibilityPath(for: range) {
                    let converted = root.convert(path, from: input as? UIView)
                    shape = AccessibilityShape(converted)
                }
                if let substring = input.text(in: range) {
                    description = substring
                }
                return ResultMarker(elementDescription: description, rangeDescription: range.formatted(in: input), shape: shape)
            }
            return ResultMarker(elementDescription: description, rangeDescription: nil, shape: shape)
        }
        self.init(name: name, resultMarkers: resultMarkers, limit: limit)
    }
}
