import SwiftUI

@available(iOS 14.0, *)
struct SwiftUIScrollProbeView: View {
    @State private var showScrollView = true

    var body: some View {
        if showScrollView {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0 ..< 50, id: \.self) { index in
                        Text("ScrollView Item \(index)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemBackground))
                    }
                }
            }
            .navigationTitle("ScrollView Probe")
            .toolbar {
                Button("List") { showScrollView = false }
            }
        } else {
            List(0 ..< 50, id: \.self) { index in
                Text("List Item \(index)")
            }
            .navigationTitle("List Probe")
            .toolbar {
                Button("ScrollView") { showScrollView = true }
            }
        }
    }
}
