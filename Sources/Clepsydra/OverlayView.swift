import SwiftUI
import ClepsydraCore

/// Кнопка на полноэкранном экране.
struct OverlayAction: Identifiable {
    let id = UUID()
    let title: String
    let isPrimary: Bool
    let run: () -> Void
}

/// Экран между помидорами: цитата, автор и кнопки. На мониторах без курсора
/// кнопок нет — там остаётся только цитата.
struct OverlayView: View {

    let quote: Quote
    let actions: [OverlayAction]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(quote.text)
                .font(.system(size: 34, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)

            Text(quote.author)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 28)

            Spacer()

            HStack(spacing: 16) {
                ForEach(actions) { action in
                    Button(action: action.run) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .medium))
                            .frame(minWidth: 132)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(OverlayButtonStyle(isPrimary: action.isPrimary))
                }
            }
            .padding(.bottom, 88)
            .opacity(actions.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct OverlayButtonStyle: ButtonStyle {

    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isPrimary ? 0.95 : 0.55))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(isPrimary ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(isPrimary ? 0.22 : 0.1), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
