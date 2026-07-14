//
//  Copyright 2026 Block Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import FBSnapshotTestCase_Accessibility
import iOSSnapshotTestCase
import SwiftUI

/// Snapshot coverage for SwiftUI `.searchable()` — the hierarchy that motivated
/// the zero-frame non-clipping wrapper descent (#328): on iOS 26+, UIKit renders
/// the search field through SwiftUI bridging views inside
/// `_UIFloatingBarContainerView`, behind a zero-frame `_UIInheritedView` wrapper.
/// These snapshots pin whether the parser surfaces the search field across OS
/// versions and nav-bar layouts.
///
/// The content is a plain `VStack` rather than a `List`: SwiftUI List rows
/// alternate between two accessibility-frame renderings run-to-run (see
/// `SwiftUIListSectionTests`), and list rows are incidental to what these
/// snapshots pin.
final class SwiftUISearchableTests: SnapshotTestCase {
    @available(iOS 16.0, *)
    func testSearchableAlwaysVisible() {
        SnapshotVerifyAccessibility(
            SearchableFixtureView(placement: .navigationBarDrawer(displayMode: .always)),
            size: UIScreen.main.bounds.size
        )
    }

    @available(iOS 16.0, *)
    func testSearchableToolbarPlacement() {
        SnapshotVerifyAccessibility(
            SearchableFixtureView(placement: .toolbar),
            size: UIScreen.main.bounds.size
        )
    }
}

@available(iOS 16.0, *)
private struct SearchableFixtureView: View {
    let placement: SearchFieldPlacement

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Item 1")
                Text("Item 2")
                Text("Item 3")
                Spacer()
            }
            .padding()
            .navigationTitle("Searchable")
            .searchable(text: .constant(""), placement: placement, prompt: "Filter items")
        }
    }
}
