import SwiftUI

/// Shared chrome for every modal so the sheets read as one family.
struct SheetScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.title(24))
                            .foregroundStyle(Theme.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.body(12, weight: .medium))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.panelRaised))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 12) { content() }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Theme.body(11, weight: .black))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .padding(.top, 6)
    }
}
