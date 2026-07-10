@testable import AccessibilitySnapshotModel
import XCTest

/// Pins the model-side description assembly ported from the parse-time path. `.verbose` must
/// reproduce the historical strings; the verbosity flags must gate each section; `traitPosition`
/// must mirror iOS 18.4's Controls verbosity (Speak Before / After / Don't Speak).
final class DescriptionAssemblyTests: XCTestCase {
    private func element(
        label: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = [],
        hint: String? = nil,
        customContent: [AccessibilityElement.CustomContent] = []
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: "",
            label: label,
            value: value,
            traits: traits,
            identifier: nil,
            hint: hint,
            userInputLabels: nil,
            shape: .frame(.zero),
            activationPoint: .zero,
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: customContent,
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    // MARK: - Trait position mirrors iOS Controls verbosity

    func testTraitPositionAfterIsHistoricalDefault() {
        let button = element(label: "Submit", traits: .button)
        XCTAssertEqual(button.description(context: nil).description, "Submit. Button.")
    }

    func testTraitPositionBeforeSpeaksTraitFirst() {
        var verbosity = VerbosityConfiguration.verbose
        verbosity.traitPosition = .before
        let button = element(label: "Submit", traits: .button)
        XCTAssertEqual(button.description(context: nil, verbosity: verbosity).description, "Button. Submit")
    }

    func testTraitPositionNoneOmitsTrait() {
        var verbosity = VerbosityConfiguration.verbose
        verbosity.traitPosition = .none
        let button = element(label: "Submit", traits: .button)
        XCTAssertEqual(button.description(context: nil, verbosity: verbosity).description, "Submit")
    }

    // MARK: - Verbosity gating

    func testMinimalIsLabelOnly() {
        let button = element(label: "Submit", value: "ready", traits: [.button, .header])
        XCTAssertEqual(button.description(context: nil, verbosity: .minimal).description, "Submit")
    }

    func testValueAppendedWithColonWhenVerbose() {
        let slider = element(label: "Volume", value: "50%")
        XCTAssertEqual(slider.description(context: nil).description, "Volume: 50%")
    }

    func testIncludesValueFalseDropsValue() {
        var verbosity = VerbosityConfiguration.verbose
        verbosity.includesValue = false
        let slider = element(label: "Volume", value: "50%")
        XCTAssertEqual(slider.description(context: nil, verbosity: verbosity).description, "Volume")
    }

    // MARK: - Container context

    func testSeriesContext() {
        let item = element(label: "Photo")
        // seriesContextFormat is "%@ %@ of %@." — no period between the label and the count.
        XCTAssertEqual(item.description(context: .series(index: 2, count: 5)).description, "Photo 2 of 5.")
    }

    func testListStartContext() {
        let item = element(label: "First")
        XCTAssertEqual(item.description(context: .listStart).description, "First. List Start.")
    }

    func testContainerContextGatedOff() {
        var verbosity = VerbosityConfiguration.verbose
        verbosity.includesContainerContext = false
        let item = element(label: "Photo")
        XCTAssertEqual(item.description(context: .series(index: 2, count: 5), verbosity: verbosity).description, "Photo")
    }

    // MARK: - Hints

    func testHintPassthroughAndGating() {
        let el = element(label: "Save", hint: "Saves your work")
        XCTAssertEqual(el.description(context: nil).hint, "Saves your work")

        var verbosity = VerbosityConfiguration.verbose
        verbosity.includesHints = false
        XCTAssertNil(el.description(context: nil, verbosity: verbosity).hint)
    }
}
