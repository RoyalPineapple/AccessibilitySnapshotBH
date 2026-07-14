import AccessibilitySnapshotModel
import ObjectiveC
import UIKit

/// Non-blocking fidelity scoring, designed to be popped onto a codebase as a single commit,
/// run against its suites, and popped off.
///
/// During a test run the parser only *records* each parse root (recording costs an append). At
/// the very end of each test, after teardown, each recorded root is restored to the hosting state
/// the parser originally saw (re-hosted, un-hidden, or left unhosted), re-parsed, and compared
/// black-box against Apple's own accessibility walkers (via the `PrivateAXTraversal` gateway) on
/// the same root, at the same moment. Nothing runs between parse and render, so scoring can never
/// perturb a snapshot; it never alters parser output and never fails a test.
///
/// Two comparisons run, both against the parser's pruned, flattened output (the 1:1 contract):
/// - the bulk leaf walk, the same walker the curated parity fixtures assert against; and
/// - VoiceOver's cursor-walk primitive — the exact app-side engine a swipe consumes — anchored on
///   the first element and filtered to the parsed root's subtree (the walk spans the whole
///   screen), validating the relative order the cursor visits the parsed elements.
///
/// Outside XCTest nothing is recorded and nothing runs. Under XCTest the default handler prints
/// divergent reports per test and an aggregate score when the bundle finishes — silent when 1:1,
/// loud when not. Set `reportHandler` to a custom closure to collect or assert instead.
public enum ParserFidelity {
    public struct Report {
        /// The test that produced the parse, when known.
        public let test: String?

        /// Short description of the parsed root view.
        public let root: String

        /// The parser's pruned element count.
        public let parserCount: Int

        /// The bulk leaf walker's element count; `nil` when the SPI or its options class is
        /// unavailable at runtime.
        public let leafWalkCount: Int?

        /// The cursor walk's in-scope chain length (anchor included); `nil` when the axis was
        /// skipped.
        public let cursorWalkCount: Int?

        /// Human-readable mismatches, capped; empty when both walks agree with the parser 1:1.
        public let divergences: [String]

        public var isClean: Bool { divergences.isEmpty }
    }

    /// Receives a report for every root scored at the end of a test. Defaults to printing
    /// divergent reports.
    public static var reportHandler: (Report) -> Void = { report in
        if ProcessInfo.processInfo.environment["PARSER_FIDELITY_VERBOSE"] != nil {
            print("[ParserFidelity] \(report.isClean ? "clean" : "DIVERGENT") \(report.root)\(report.test.map { " — \($0)" } ?? ""): parser=\(report.parserCount) leafWalk=\(report.leafWalkCount.map(String.init) ?? "n/a") cursorWalk=\(report.cursorWalkCount.map(String.init) ?? "n/a")")
        }
        guard !report.isClean else { return }
        print("[ParserFidelity] DIVERGENCE in \(report.root)\(report.test.map { " — \($0)" } ?? "")")
        report.divergences.forEach { print("[ParserFidelity]   \($0)") }
    }

    // MARK: - Recording (during the test)

    // Roots are retained until their test finishes: the snapshot flow unhosts and releases the
    // view once the snapshot is taken, which would leave nothing to score at teardown. Whether
    // the root was hosted at parse time is captured alongside it so scoring can reproduce the
    // exact state the parser saw, and the root's responder-chain view controller is retained
    // with it — a test's function-local view controller dies when the test method returns, and
    // a re-hosted view whose data source (the view controller) has deallocated vends nothing to
    // Apple's walkers. The window is NOT retained: keeping a test's window alive-and-visible
    // past its natural lifetime perturbs rendering later in the same test.
    private static var pendingRoots: [(root: UIView, wasHosted: Bool, companions: [AnyObject])] = []
    private static var isScoring = false
    private static var scoredCount = 0
    private static var divergentCount = 0
    private static var skippedCount = 0
    private static var divergentReports: [Report] = []

    /// Called by the parser after each parse. Under XCTest, remembers the root for scoring at the
    /// end of the current test; everywhere else, does nothing.
    static func recordForScoring(_ root: UIView) {
        guard !isScoring, isRunningUnderXCTest else { return }
        _ = registerObserverOnce
        if !pendingRoots.contains(where: { $0.root === root }) {
            var companions: [AnyObject] = []
            var responder: UIResponder? = root.next
            while let current = responder {
                if let viewController = current as? UIViewController {
                    companions.append(viewController)
                    break
                }
                responder = current.next
            }
            pendingRoots.append((root: root, wasHosted: root.window != nil, companions: companions))
        }
    }

    private static let isRunningUnderXCTest =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil

    // MARK: - Scoring (at the end of the test)

    fileprivate static func scorePendingRoots(testName: String?) {
        let roots = pendingRoots
        pendingRoots = []
        // `roots` keeps each entry's companions (window, view controller) alive through scoring.
        roots.forEach { score($0.root, wasHosted: $0.wasHosted, testName: testName) }
    }

    private static func score(_ root: UIView, wasHosted: Bool, testName: String?) {
        isScoring = true
        defer { isScoring = false }

        // Apple's visible-frame walkers see nothing outside a visible window, so every root gets
        // one — but reproducing the hosting state the parser saw is what keeps the comparison
        // honest, and any single recipe manufactures false divergences:
        // - parsed hosted, still in its (retained) window that the test has since hidden:
        //   un-hide that window — its view controller and data sources are intact;
        // - parsed hosted, since unhosted (the snapshot flow unhosts after verifying): re-host
        //   in a scratch window with the snapshot flow's own recipe (centered, key, visible);
        // - never hosted (bare fixture roots): host in a scratch window at the ORIGIN — such
        //   fixtures hard-code accessibility frames and paths in absolute coordinates near the
        //   origin, which centering would relocate out from under them.
        // A root that is captive in some other unhosted tree can't be moved; count it skipped.
        var scratchWindow: UIWindow?
        var windowToRehide: UIWindow?
        if !(root is UIWindow) {
            if let window = root.window {
                if window.isHidden {
                    window.isHidden = false
                    window.makeKeyAndVisible()
                    window.layoutIfNeeded()
                    windowToRehide = window
                }
            } else {
                guard root.superview == nil else {
                    skippedCount += 1
                    return
                }
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.addSubview(root)
                if wasHosted {
                    root.center = window.center
                }
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                scratchWindow = window
            }
        }
        defer {
            if let scratchWindow {
                root.removeFromSuperview()
                scratchWindow.isHidden = true
            }
            windowToRehide?.isHidden = true
        }

        // Re-parse at scoring time so the parser and Apple's walkers observe the identical view
        // state, whatever the test did to it in between.
        let hierarchy = AccessibilityHierarchyParser().parseAccessibilityHierarchy(in: root)
        let parserIdentities = hierarchy.onscreen().flattenToElements().map { element in
            identity(label: element.label, traits: element.traits.rawValue)
        }

        var divergences: [String] = []
        var leafWalkCount: Int?
        var cursorWalkCount: Int?

        if let options = PrivateAXTraversal.TraversalOptions(visibleFrameOnly: true),
           let leaves = PrivateAXTraversal.leafDescendants(of: root, options: options)
        {
            let leafIdentities = leaves.map { identity(label: $0.accessibilityLabel, traits: $0.accessibilityTraits.rawValue) }
            leafWalkCount = leaves.count
            divergences += diff("leafWalk", parser: parserIdentities, apple: leafIdentities)

            if let anchor = leaves.first,
               let walkOptions = PrivateAXTraversal.TraversalOptions(visibleFrameOnly: true),
               let walk = PrivateAXTraversal.elementsFollowing(anchor, options: walkOptions)
            {
                let leafSet = Set(leaves.map { ObjectIdentifier($0) })
                let chain = ([anchor] + walk).filter { isInScope($0, root: root, leafSet: leafSet) }
                let chainIdentities = chain.map { identity(label: $0.accessibilityLabel, traits: $0.accessibilityTraits.rawValue) }
                cursorWalkCount = chain.count
                divergences += diff("cursorWalk", parser: parserIdentities, apple: chainIdentities)
            }
        }

        let report = Report(
            test: testName,
            root: "\(type(of: root))(\(root.frame.width)x\(root.frame.height))",
            parserCount: parserIdentities.count,
            leafWalkCount: leafWalkCount,
            cursorWalkCount: cursorWalkCount,
            divergences: divergences
        )

        scoredCount += 1
        if !report.isClean {
            divergentCount += 1
            if divergentReports.count < 100 {
                divergentReports.append(report)
            }
        }

        reportHandler(report)
    }

    // MARK: - Roll-up (at the end of the bundle)

    fileprivate static func finishBundle(named bundleName: String) {
        let summary = "\(scoredCount - divergentCount)/\(scoredCount) parse roots 1:1 with Apple's walkers"
            + " (\(divergentCount) divergent, \(skippedCount) skipped)"
        print("[ParserFidelity] SCORE \(bundleName): \(summary)")
        writeReportFileIfRequested(bundleName: bundleName, summary: summary)

        scoredCount = 0
        divergentCount = 0
        skippedCount = 0
        divergentReports = []
    }

    /// When `PARSER_FIDELITY_REPORT_PATH` is set in the test runner's environment (CI passes it
    /// via xcodebuild's `TEST_RUNNER_` prefix), appends a markdown section per test bundle so the
    /// job can roll the score up into its step summary — one section per bundle, one summary per
    /// OS version in the matrix.
    private static func writeReportFileIfRequested(bundleName: String, summary: String) {
        guard let path = ProcessInfo.processInfo.environment["PARSER_FIDELITY_REPORT_PATH"] else { return }

        var markdown = "### Parser fidelity — \(bundleName), iOS \(UIDevice.current.systemVersion)\n\n"
        markdown += "**\(summary)**\n\n"
        for report in divergentReports {
            markdown += "<details><summary>\(report.root)\(report.test.map { " — \($0)" } ?? "")</summary>\n\n"
            markdown += report.divergences.map { "- `\($0)`" }.joined(separator: "\n")
            markdown += "\n\n</details>\n"
        }
        markdown += "\n"

        guard let data = markdown.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Black-box comparison

    private static func identity(label: String?, traits: UInt64) -> String {
        "(label=\(label.map { "\"\($0)\"" } ?? "nil"), traits=\(traits))"
    }

    private static func diff(_ axis: String, parser: [String], apple: [String]) -> [String] {
        guard parser != apple else { return [] }
        var out = ["\(axis): parser \(parser.count) elements, apple \(apple.count)"]
        for index in 0 ..< max(parser.count, apple.count) {
            let p = index < parser.count ? parser[index] : "(absent)"
            let a = index < apple.count ? apple[index] : "(absent)"
            if p != a {
                out.append("\(axis)[\(index)]: parser \(p) vs apple \(a)")
            }
            if out.count >= 6 {
                out.append("\(axis): … further divergences truncated")
                break
            }
        }
        return out
    }

    /// Whether a walked element belongs to the parsed root's subtree: a member of the leaf list,
    /// a descendant view, or a vended element whose `accessibilityContainer` chain reaches a
    /// descendant view (covers table/collection cell proxies vended fresh per SPI call).
    private static func isInScope(_ element: NSObject, root: UIView, leafSet: Set<ObjectIdentifier>) -> Bool {
        if leafSet.contains(ObjectIdentifier(element)) { return true }

        var current: NSObject? = element
        var hops = 0
        while let candidate = current, hops < 32 {
            if let view = candidate as? UIView {
                return view === root || view.isDescendant(of: root)
            }
            current = PrivateAXTraversal.container(of: candidate)
            hops += 1
        }
        return false
    }

    // MARK: - XCTest hookup (runtime-only; this target never links XCTest)

    /// Registers a test observer with XCTestObservationCenter via the ObjC runtime so scoring
    /// runs after each test's teardown ("afterEach") without this library depending on XCTest.
    private static let registerObserverOnce: Void = {
        guard
            let centerClass = NSClassFromString("XCTestObservationCenter") as? NSObject.Type,
            let center = centerClass
            .perform(NSSelectorFromString("sharedTestObservationCenter"))?
            .takeUnretainedValue() as? NSObject
        else {
            return
        }
        if let observationProtocol = NSProtocolFromString("XCTestObservation") {
            class_addProtocol(FidelityTestObserver.self, observationProtocol)
        }
        center.perform(NSSelectorFromString("addTestObserver:"), with: FidelityTestObserver.shared)
    }()
}

/// Bridges XCTestObservation callbacks (resolved at runtime) into `ParserFidelity`.
private final class FidelityTestObserver: NSObject {
    static let shared = FidelityTestObserver()

    @objc(testCaseDidFinish:)
    func testCaseDidFinish(_ testCase: AnyObject) {
        ParserFidelity.scorePendingRoots(testName: testCase.value(forKey: "name") as? String)
    }

    @objc(testBundleDidFinish:)
    func testBundleDidFinish(_ bundle: AnyObject) {
        let bundleName = (bundle.value(forKey: "bundlePath") as? String).map { ($0 as NSString).lastPathComponent } ?? "tests"
        ParserFidelity.finishBundle(named: bundleName)
    }
}
