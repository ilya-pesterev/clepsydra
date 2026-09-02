import SwiftUI
import ClepsydraCore

/// Кнопка на полноэкранном экране.
struct OverlayAction: Identifiable {
    let id = UUID()
    let title: String
    let isPrimary: Bool
    let run: () -> Void
}

/// Содержимое экрана. Живёт отдельно от окон: за перерыв оно меняется дважды —
/// кнопка уступает место отсчёту, — а окна при этом остаются те же.
final class OverlayModel: ObservableObject {
    @Published var quote: Quote
    /// Отсчёт перерыва. `nil` — вместо него показываем кнопки.
    @Published var countdown: String?
    @Published var actions: [OverlayAction]

    init(quote: Quote, countdown: String? = nil, actions: [OverlayAction] = []) {
        self.quote = quote
        self.countdown = countdown
        self.actions = actions
    }
}

/// Экран между помидорами: цитата, автор и то, что сейчас важнее — кнопки или
/// отсчёт перерыва. Кнопки только на мониторе с курсором; цитата, отсчёт и
/// подсказка — на всех.
struct OverlayView: View {

    @ObservedObject var model: OverlayModel
    let showsActions: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(model.quote.text)
                .font(.system(size: 34, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.quote.author)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 28)

            Spacer()

            controls
                .frame(height: 43)

            Text("⌘⇧0 — закрыть")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 22)
        }
        .padding(.bottom, 72)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var controls: some View {
        if let countdown = model.countdown {
            // Идёт перерыв: экран остаётся, но нажимать на нём нечего.
            Text(countdown)
                .font(.system(size: 34, weight: .thin, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        } else if showsActions {
            HStack(spacing: 16) {
                ForEach(model.actions) { action in
                    Button(action: action.run) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .medium))
                            .frame(minWidth: 132)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(OverlayButtonStyle(isPrimary: action.isPrimary))
                }
            }
        } else {
            Color.clear
        }
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
