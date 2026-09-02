import SwiftUI
import ClepsydraCore

/// Кнопка на полноэкранном экране.
struct OverlayAction: Identifiable {
    let id = UUID()
    let title: String
    let isPrimary: Bool
    let run: () -> Void
}

/// Что показываем: тихую цитату философа или наклейки.
enum OverlayContent {
    case philosopher(Quote, portrait: NSImage?)
    case sticker(StickerQuote, palette: StickerPalette, photo: NSImage?)
}

/// Содержимое экрана. Живёт отдельно от окон: за перерыв оно меняется —
/// кнопка уступает место отсчёту, — а окна при этом остаются те же.
final class OverlayModel: ObservableObject {
    @Published var content: OverlayContent
    /// Отсчёт перерыва. `nil` — вместо него показываем кнопки.
    @Published var countdown: String?
    @Published var actions: [OverlayAction]

    init(content: OverlayContent, countdown: String? = nil, actions: [OverlayAction] = []) {
        self.content = content
        self.countdown = countdown
        self.actions = actions
    }
}

/// Экран между помидорами. Кнопки только на мониторе с курсором; всё
/// остальное — на всех.
struct OverlayView: View {

    @ObservedObject var model: OverlayModel
    let showsActions: Bool
    let screenWidth: CGFloat

    /// Единица вёрстки наклеек — сотая доля ширины экрана. Зажата с двух сторон,
    /// чтобы на маленьком мониторе плашки не съезжали, а на большом не разрастались.
    private var unit: CGFloat { min(max(screenWidth / 100, 9), 26) }

    var body: some View {
        ZStack {
            Color.black

            switch model.content {
            case .philosopher(let quote, let portrait):
                philosopher(quote, portrait: portrait)
            case .sticker(let quote, let palette, let photo):
                stickers(quote, palette: palette, photo: photo)
            }
        }
    }

    // MARK: Философы — как было

    private func philosopher(_ quote: Quote, portrait: NSImage?) -> some View {
        ZStack {
            // Портрет — противоположность наклейке: ни канта, ни цвета, ни
            // тени. Обесцвечен и приглушён до присутствия, а не до картинки.
            if let portrait {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Image(nsImage: portrait)
                            .resizable()
                            .scaledToFit()
                            .grayscale(1)
                            .opacity(0.3)
                            .frame(width: 30 * unit)
                            .padding(.trailing, 2 * unit)
                    }
                }
            }

            quoteColumn(quote)
                // Освобождаем место под портрет, иначе на узком мониторе
                // строки цитаты налезут на него.
                .padding(.trailing, portrait != nil ? 30 * unit : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quoteColumn(_ quote: Quote) -> some View {
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

            footer
        }
        .padding(.bottom, 72)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Наклейки

    private func stickers(_ quote: StickerQuote, palette: StickerPalette, photo: NSImage?) -> some View {
        ZStack {
            // Фигура прижата к правому нижнему углу и вылетает за края:
            // так она выглядит наклеенной поверх, а не вставленной внутрь.
            if let photo {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DieCutPhoto(photo: photo, ring: 0.9 * unit)
                            .frame(width: 32 * unit)
                            .rotationEffect(.degrees(3))
                            .padding(.trailing, 1.5 * unit)
                            .padding(.bottom, -unit)
                    }
                }
            }

            // Реплика: с фигурой — слева, без неё — по центру.
            HStack(spacing: 0) {
                StickerQuoteView(quote: quote, palette: palette, unit: unit)
                if photo != nil { Spacer(minLength: 0) }
            }
            .padding(.leading, photo != nil ? 6 * unit : 0)
            .padding(.bottom, 9 * unit)

            VStack(spacing: 0) {
                Spacer()
                footer
            }
            .padding(.bottom, 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Низ экрана — одинаковый в обоих режимах

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            controls
                .frame(height: 43)

            Text("⌘⇧0 — закрыть")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 22)
        }
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

/// Реплика наклейками: каждая строка — своя плашка со своим наклоном и
/// отступом. Наклеены по одной, а не набраны абзацем.
private struct StickerQuoteView: View {

    let quote: StickerQuote
    let palette: StickerPalette
    let unit: CGFloat

    /// Наклоны и отступы повторяются по кругу — так строки не выстраиваются
    /// в ровную колонку, но и не пляшут случайно при каждом показе.
    private static let tilts: [Double] = [-2.1, 1.1, -1.2, 0.8]
    private static let insets: [CGFloat] = [0, 3.4, 1.1, 2.6]

    var body: some View {
        VStack(alignment: .leading, spacing: 0.75 * unit) {
            ForEach(Array(quote.lines.enumerated()), id: \.offset) { index, line in
                pill(line, isLast: index == quote.lines.count - 1)
                    .rotationEffect(.degrees(Self.tilts[index % Self.tilts.count]))
                    .padding(.leading, Self.insets[index % Self.insets.count] * unit)
            }

            signature
                .padding(.top, 1.9 * unit)
                .padding(.leading, 1.6 * unit)
        }
    }

    /// Последняя строка — ударная, поэтому другого цвета. Одностроч­ная реплика
    /// вся ударная: делить в ней нечего.
    private func pill(_ line: String, isLast: Bool) -> some View {
        let useAccent = isLast
        return Text(line)
            .font(.system(size: 3.4 * unit, weight: .black, design: .rounded))
            .foregroundStyle(useAccent ? palette.accentInk : palette.baseInk)
            .padding(.horizontal, 2.6 * unit)
            .padding(.vertical, 1.45 * unit)
            .background(Capsule().fill(useAccent ? palette.accent : palette.base))
            // Кант — не обводка внутрь, а белая капсула снаружи: она шире
            // ровно на толщину канта и повторяет то же скругление.
            .padding(0.66 * unit)
            .background(Capsule().fill(.white))
            // Без схлопывания тень ложится на каждый слой фона отдельно, и
            // внутренняя цветная капсула затеняет белый кант до серого.
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 1.5 * unit, y: 0.9 * unit)
    }

    private var signature: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.7 * unit) {
            Text("Джейсон Стетхем")
                .font(.system(size: 1.25 * unit, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("не говорил, но мог бы")
                .font(.system(size: 0.95 * unit, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 1.5 * unit)
        .padding(.vertical, 0.75 * unit)
        .background(Capsule().fill(Color(red: 0.063, green: 0.063, blue: 0.071)))
        .padding(0.38 * unit)
        .background(Capsule().fill(.white))
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 1 * unit, y: 0.6 * unit)
        .rotationEffect(.degrees(1.7))
    }
}

/// Фотография, вырезанная по контуру: белый кант — это восемь копий силуэта
/// со смещением под самим снимком. Силуэт берётся из альфа-канала, поэтому
/// PNG обязан быть с прозрачным фоном.
private struct DieCutPhoto: View {

    let photo: NSImage
    let ring: CGFloat

    private static let directions: [(CGFloat, CGFloat)] = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
        (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.directions.enumerated()), id: \.offset) { _, direction in
                Image(nsImage: photo)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .offset(x: direction.0 * ring, y: direction.1 * ring)
            }
            Image(nsImage: photo)
                .resizable()
                .scaledToFit()
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.85), radius: 2.2 * ring, y: 1.3 * ring)
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
