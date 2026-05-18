import CoreGraphics
import Foundation

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
    static let button = bit(0)
    static let link = bit(1)
    static let image = bit(2)
    static let selected = bit(3)
    static let playsSound = bit(4)
    static let keyboardKey = bit(5)
    static let staticText = bit(6)
    static let summaryElement = bit(7)
    static let notEnabled = bit(8)
    static let updatesFrequently = bit(9)
    static let searchField = bit(10)
    static let startsMediaSession = bit(11)
    static let adjustable = bit(12)
    static let allowsDirectInteraction = bit(13)
    static let causesPageTurn = bit(14)
    static let header = bit(16)
    static let tabBar = bit(17)

    static let webContent = bit(17)
    static let textEntry = bit(18)
    static let pickerElement = bit(19)
    static let radioButton = bit(20)
    static let isEditing = bit(21)
    static let launchIcon = bit(22)
    static let statusBarElement = bit(23)
    static let secureTextField = bit(24)
    static let inactive = bit(25)
    static let footer = bit(26)
    static let backButton = bit(27)
    static let tabBarItem = bit(28)
    static let autoCorrectCandidate = bit(29)
    static let deleteKey = bit(30)
    static let selectionDismissesItem = bit(31)
    static let visited = bit(32)
    static let spacer = bit(34)
    static let tableIndex = bit(35)
    static let map = bit(36)
    static let textOperationsAvailable = bit(37)
    static let draggable = bit(38)
    static let popupButton = bit(40)
    static let textArea = bit(47)
    static let menuItem = bit(52)
    static let switchButton = bit(53)
    static let alert = bit(56)

    static let knownTraits: [(trait: AccessibilityTraits, name: String)] = [
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

    static func fromNames(_ names: [String]) -> AccessibilityTraits {
        var traits = AccessibilityTraits()
        for name in names {
            if let known = knownTraits.first(where: { $0.name == name }) {
                traits.insert(known.trait)
            }
        }
        return traits
    }

    private static func bit(_ index: Int) -> AccessibilityTraits {
        AccessibilityTraits(rawValue: UInt64(1) << index)
    }
}

public extension AccessibilityTraits {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let traitNames = try container.decode([String].self)

        var traits = AccessibilityTraits()
        var unknownValues: UInt64 = 0

        for name in traitNames {
            if let known = Self.knownTraits.first(where: { $0.name == name }) {
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
        for (trait, _) in Self.knownTraits where contains(trait) {
            remainingRawValue &= ~trait.rawValue
        }
        if remainingRawValue != 0 {
            names.append("unknown(\(remainingRawValue))")
        }
        try container.encode(names)
    }
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
            let path = CGMutablePath()
            for element in elements {
                element.apply(to: path)
            }
            guard !path.isEmpty else { return .zero }
            let rect = path.boundingBoxOfPath
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
            self = try .frame(container.decode(AccessibilityRect.self, forKey: .frame))
        case .path:
            self = try .path(container.decode([AccessibilityPathElement].self, forKey: .pathElements))
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

// MARK: - CoreGraphics Adapters

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
    func apply(to path: CGMutablePath) {
        switch self {
        case let .move(to):
            path.move(to: to.cgPoint)
        case let .line(to):
            path.addLine(to: to.cgPoint)
        case let .quadCurve(to, control):
            path.addQuadCurve(to: to.cgPoint, control: control.cgPoint)
        case let .curve(to, control1, control2):
            path.addCurve(to: to.cgPoint, control1: control1.cgPoint, control2: control2.cgPoint)
        case .closeSubpath:
            path.closeSubpath()
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

public extension AccessibilityShape {
    var cgPath: CGPath {
        let path = CGMutablePath()
        switch self {
        case let .frame(rect):
            path.addRect(rect.cgRect)
        case let .path(elements):
            for element in elements {
                element.apply(to: path)
            }
        }
        return path
    }
}
