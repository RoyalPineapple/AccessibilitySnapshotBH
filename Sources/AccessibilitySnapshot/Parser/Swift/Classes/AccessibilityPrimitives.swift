import CoreGraphics
import Foundation
import UIKit

// MARK: - Portable Geometry

public struct AccessibilityPoint: Hashable, Codable, Sendable {
    public let x: CGFloat
    public let y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public extension AccessibilityPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

public struct AccessibilitySize: Hashable, Codable, Sendable {
    public let width: CGFloat
    public let height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
}

public extension AccessibilitySize {
    var isFinite: Bool {
        width.isFinite && height.isFinite
    }
}

public struct AccessibilityRect: Hashable, Codable, Sendable {
    public let origin: AccessibilityPoint
    public let size: AccessibilitySize

    public init(origin: AccessibilityPoint, size: AccessibilitySize) {
        self.origin = origin
        self.size = size
    }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(
            origin: AccessibilityPoint(x: x, y: y),
            size: AccessibilitySize(width: width, height: height)
        )
    }
}

public extension AccessibilityRect {
    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + size.width }
    var maxY: CGFloat { origin.y + size.height }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    var isFinite: Bool {
        origin.isFinite && size.isFinite
    }
}

public enum AccessibilityPathElement: Hashable, Codable, Sendable {
    case move(to: AccessibilityPoint)
    case line(to: AccessibilityPoint)
    case quadCurve(to: AccessibilityPoint, control: AccessibilityPoint)
    case curve(to: AccessibilityPoint, control1: AccessibilityPoint, control2: AccessibilityPoint)
    case closeSubpath
}

// MARK: - Portable Traits

public struct AccessibilityTraits: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public extension AccessibilityTraits {
    static let button = AccessibilityTraits(rawValue: UIAccessibilityTraits.button.rawValue)
    static let link = AccessibilityTraits(rawValue: UIAccessibilityTraits.link.rawValue)
    static let image = AccessibilityTraits(rawValue: UIAccessibilityTraits.image.rawValue)
    static let selected = AccessibilityTraits(rawValue: UIAccessibilityTraits.selected.rawValue)
    static let playsSound = AccessibilityTraits(rawValue: UIAccessibilityTraits.playsSound.rawValue)
    static let keyboardKey = AccessibilityTraits(rawValue: UIAccessibilityTraits.keyboardKey.rawValue)
    static let staticText = AccessibilityTraits(rawValue: UIAccessibilityTraits.staticText.rawValue)
    static let summaryElement = AccessibilityTraits(rawValue: UIAccessibilityTraits.summaryElement.rawValue)
    static let notEnabled = AccessibilityTraits(rawValue: UIAccessibilityTraits.notEnabled.rawValue)
    static let updatesFrequently = AccessibilityTraits(rawValue: UIAccessibilityTraits.updatesFrequently.rawValue)
    static let searchField = AccessibilityTraits(rawValue: UIAccessibilityTraits.searchField.rawValue)
    static let startsMediaSession = AccessibilityTraits(rawValue: UIAccessibilityTraits.startsMediaSession.rawValue)
    static let adjustable = AccessibilityTraits(rawValue: UIAccessibilityTraits.adjustable.rawValue)
    static let allowsDirectInteraction = AccessibilityTraits(rawValue: UIAccessibilityTraits.allowsDirectInteraction.rawValue)
    static let causesPageTurn = AccessibilityTraits(rawValue: UIAccessibilityTraits.causesPageTurn.rawValue)
    static let header = AccessibilityTraits(rawValue: UIAccessibilityTraits.header.rawValue)
    static let tabBar = AccessibilityTraits(rawValue: UIAccessibilityTraits.tabBar.rawValue)

    static let webContent = AccessibilityTraits(rawValue: UIAccessibilityTraits.webContent.rawValue)
    static let textEntry = AccessibilityTraits(rawValue: UIAccessibilityTraits.textEntry.rawValue)
    static let pickerElement = AccessibilityTraits(rawValue: UIAccessibilityTraits.pickerElement.rawValue)
    static let radioButton = AccessibilityTraits(rawValue: UIAccessibilityTraits.radioButton.rawValue)
    static let isEditing = AccessibilityTraits(rawValue: UIAccessibilityTraits.isEditing.rawValue)
    static let launchIcon = AccessibilityTraits(rawValue: UIAccessibilityTraits.launchIcon.rawValue)
    static let statusBarElement = AccessibilityTraits(rawValue: UIAccessibilityTraits.statusBarElement.rawValue)
    static let secureTextField = AccessibilityTraits(rawValue: UIAccessibilityTraits.secureTextField.rawValue)
    static let inactive = AccessibilityTraits(rawValue: UIAccessibilityTraits.inactive.rawValue)
    static let footer = AccessibilityTraits(rawValue: UIAccessibilityTraits.footer.rawValue)
    static let backButton = AccessibilityTraits(rawValue: UIAccessibilityTraits.backButton.rawValue)
    static let tabBarItem = AccessibilityTraits(rawValue: UIAccessibilityTraits.tabBarItem.rawValue)
    static let autoCorrectCandidate = AccessibilityTraits(rawValue: UIAccessibilityTraits.autoCorrectCandidate.rawValue)
    static let deleteKey = AccessibilityTraits(rawValue: UIAccessibilityTraits.deleteKey.rawValue)
    static let selectionDismissesItem = AccessibilityTraits(rawValue: UIAccessibilityTraits.selectionDismissesItem.rawValue)
    static let visited = AccessibilityTraits(rawValue: UIAccessibilityTraits.visited.rawValue)
    static let spacer = AccessibilityTraits(rawValue: UIAccessibilityTraits.spacer.rawValue)
    static let tableIndex = AccessibilityTraits(rawValue: UIAccessibilityTraits.tableIndex.rawValue)
    static let map = AccessibilityTraits(rawValue: UIAccessibilityTraits.map.rawValue)
    static let textOperationsAvailable = AccessibilityTraits(rawValue: UIAccessibilityTraits.textOperationsAvailable.rawValue)
    static let draggable = AccessibilityTraits(rawValue: UIAccessibilityTraits.draggable.rawValue)
    static let popupButton = AccessibilityTraits(rawValue: UIAccessibilityTraits.popupButton.rawValue)
    static let textArea = AccessibilityTraits(rawValue: UIAccessibilityTraits.textArea.rawValue)
    static let menuItem = AccessibilityTraits(rawValue: UIAccessibilityTraits.menuItem.rawValue)
    static let switchButton = AccessibilityTraits(rawValue: UIAccessibilityTraits.switchButton.rawValue)
    static let alert = AccessibilityTraits(rawValue: UIAccessibilityTraits.alert.rawValue)
}

// MARK: - Portable Shapes

public enum AccessibilityShape: Hashable, Codable, Sendable {
    case frame(AccessibilityRect)
    case path([AccessibilityPathElement])
}

public extension AccessibilityShape {
    var frame: CGRect {
        switch self {
        case let .frame(rect):
            return rect.cgRect
        case let .path(elements):
            let path = UIBezierPath()
            for element in elements {
                element.apply(to: path)
            }
            guard !path.isEmpty else { return .zero }
            let rect = path.cgPath.boundingBoxOfPath
            guard !rect.isNull,
                  rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.size.width.isFinite,
                  rect.size.height.isFinite
            else { return .zero }
            return rect
        }
    }
}

// MARK: - Portable Rotor Limit

public enum AccessibilityRotorResultLimit: Equatable, Codable, Sendable {
    case none
    case underMaxCount(Int)
    case greaterThanMaxCount
}

// MARK: - Portable Images

public struct AccessibilityImageData: Hashable, Codable, Sendable {
    public let pngData: Data
    public let scale: Double

    public init(pngData: Data, scale: Double) {
        self.pngData = pngData
        self.scale = scale
    }
}

// MARK: - UIKit Adapters

public extension AccessibilityPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public extension AccessibilitySize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

public extension AccessibilityRect {
    init(_ rect: CGRect) {
        self.init(origin: AccessibilityPoint(rect.origin), size: AccessibilitySize(rect.size))
    }

    var cgRect: CGRect {
        CGRect(origin: origin.cgPoint, size: size.cgSize)
    }
}

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

    static func elements(from cgPath: CGPath) -> [AccessibilityPathElement] {
        var elements: [AccessibilityPathElement] = []
        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                elements.append(.move(to: AccessibilityPoint(element.points[0])))
            case .addLineToPoint:
                elements.append(.line(to: AccessibilityPoint(element.points[0])))
            case .addQuadCurveToPoint:
                elements.append(.quadCurve(
                    to: AccessibilityPoint(element.points[1]),
                    control: AccessibilityPoint(element.points[0])
                ))
            case .addCurveToPoint:
                elements.append(.curve(
                    to: AccessibilityPoint(element.points[2]),
                    control1: AccessibilityPoint(element.points[0]),
                    control2: AccessibilityPoint(element.points[1])
                ))
            case .closeSubpath:
                elements.append(.closeSubpath)
            @unknown default:
                break
            }
        }
        return elements
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

public extension AccessibilityTraits {
    static let knownTraits: [(trait: AccessibilityTraits, name: String)] = UIAccessibilityTraits.knownTraits.map {
        (trait: AccessibilityTraits($0.trait), name: $0.name)
    }

    static let knownTraitNames: Set<String> = UIAccessibilityTraits.knownTraitNames

    var traitNames: [String] {
        uiAccessibilityTraits.traitNames
    }

    static func fromNames(_ names: [String]) -> AccessibilityTraits {
        AccessibilityTraits(UIAccessibilityTraits.fromNames(names))
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

    var cgPath: CGPath {
        bezierPath.cgPath
    }

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
