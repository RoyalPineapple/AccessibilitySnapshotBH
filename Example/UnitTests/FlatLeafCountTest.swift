@testable import AccessibilitySnapshotParser
import UIKit
import XCTest

final class FlatLeafCountTest: XCTestCase, UITableViewDataSource {
    func testFlatLeafCountOnTableView() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 400))
        let table = UITableView(frame: root.bounds, style: .plain)
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        root.addSubview(table)

        let window = UIWindow(frame: root.frame)
        window.addSubview(root)
        window.makeKeyAndVisible()
        root.layoutIfNeeded()
        table.layoutIfNeeded()

        let sel = NSSelectorFromString("_accessibilityLeafDescendantsWithOptions:")
        let optionsClass = NSClassFromString("UIAccessibilityElementTraversalOptions") as? NSObject.Type
        let options = optionsClass?.init()
        options?.setValue(true, forKey: "sorted")

        // Flat leaf (no scanner groups) on the TABLE VIEW itself
        let fromTable = table.perform(sel, with: options)?.takeUnretainedValue() as? [NSObject] ?? []
        // Flat leaf on the ROOT VIEW
        let fromRoot = root.perform(sel, with: options)?.takeUnretainedValue() as? [NSObject] ?? []

        let tableLabels = fromTable.compactMap { $0.accessibilityLabel }
        let rootLabels = fromRoot.compactMap { $0.accessibilityLabel }

        NSLog("[TEST] From UITableView directly: \(fromTable.count) elements — \(tableLabels.joined(separator: ", "))")
        NSLog("[TEST] From root UIView: \(fromRoot.count) elements — \(rootLabels.joined(separator: ", "))")

        window.isHidden = true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 30 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        cell.textLabel?.text = "Row \(indexPath.row)"
        cell.accessibilityLabel = "Row \(indexPath.row)"
        return cell
    }
}
