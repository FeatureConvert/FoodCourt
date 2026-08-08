import SwiftUI

/// A segmented control built from plain SwiftUI buttons rather than `Picker(.segmented)`.
///
/// The native segmented style bridges to `UISegmentedControl`, and inside a `ScrollView` (every
/// sheet uses one via `SheetScaffold`) its tap gesture competes with the scroll view's pan
/// recognizer - the control visibly depresses but the selection doesn't always change, so a tap
/// has to be repeated. Plain buttons don't have that conflict.
struct SegmentedTabs<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Tab.allCases)) { tab in
                Button {
                    guard tab != selection else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = tab
                    }
                } label: {
                    Text(title(tab))
                        .font(Theme.body(12, weight: .black))
                        .foregroundStyle(tab == selection ? Theme.ink : Theme.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tab == selection ? Theme.coin : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink.opacity(0.5)))
    }
}
