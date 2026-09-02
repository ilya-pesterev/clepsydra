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
    /// Растёт с каждой новой репликой. Появление привязано к нему, а не к
    /// созданию окна: экран может остаться на месте, а содержимое смениться —
    /// так бывает, когда перерыв кончился, а окно так и висит.
    @Published var generation: Int = 0

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

            ScreenContent(model: model, showsActions: showsActions, unit: unit)
                // Новая реплика — вид пересобирается, и появление
                // проигрывается заново.
                .id(model.generation)
        }
    }
}

/// Содержимое экрана вместе с его появлением. Отделено от `OverlayView`,
/// потому что состояние появления должно сбрасываться при смене реплики,
/// а сбрасывается оно пересборкой вида по `.id`.
private struct ScreenContent: View {

    @ObservedObject var model: OverlayModel
    let showsActions: Bool
    let unit: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Group {
            switch model.content {
            case .philosopher(let quote, let portrait):
                philosopher(quote, portrait: portrait)
            case .sticker(let quote, let palette, let photo):
                stickers(quote, palette: palette, photo: photo)
            }
        }
        .onAppear { shown = true }
    }

    // MARK: Философы — тихое всплытие

    private func philosopher(_ quote: Quote, portrait: NSImage?) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Портрет — противоположность наклейке: ни канта, ни тени, ни
            // цвета. Обесцвечен, чтобы не спорить с тихой антиквой под ним.
            if let portrait {
                Image(nsImage: portrait)
                    .resizable()
                    .scaledToFit()
                    .grayscale(1)
                    .opacity(0.8)
                    .frame(height: 9 * unit)
                    .padding(.bottom, 38)
                    .modifier(rise(delay: 0.08))
            }

            Text(quote.text)
                .font(.system(size: 34, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(rise(delay: 0.2))

            Text(quote.author)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 28)
                .modifier(rise(delay: 0.32))

            Spacer()

            footer(delay: 0.48)
        }
        .padding(.bottom, 72)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Наклейки

    private func stickers(_ quote: StickerQuote, palette: StickerPalette, photo: NSImage?) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Фигура целиком на экране, а не вылетает за край: над текстом
            // обрезанная снизу фигура читается не как наклеенная поверх,
            // а просто как обрезанная.
            if let photo {
                DieCutPhoto(photo: photo, height: 15 * unit, ring: 0.9 * unit)
                    .padding(.bottom, 2.4 * unit)
                    .modifier(Stamp(
                        fromScale: 0.68, fromRotation: -7, rotation: 0,
                        delay: 0.06, shown: shown, reduce: reduceMotion
                    ))
            }

            StickerQuoteView(
                quote: quote, palette: palette, unit: unit,
                shown: shown, reduce: reduceMotion
            )

            Spacer()

            footer(delay: 0.54)
        }
        .padding(.bottom, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Низ экрана — одинаковый в обоих режимах

    /// Кнопка приходит последней и без движения: по едущей кнопке легко
    /// промахнуться, а экран существует ради текста, а не ради неё.
    private func footer(delay: Double) -> some View {
        VStack(spacing: 0) {
            controls
                .frame(height: 43)

            Text("⌘⇧0 — закрыть")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 22)
        }
        .opacity(shown ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.34).delay(delay),
            value: shown
        )
    }

    private func rise(delay: Double) -> Rise {
        Rise(distance: 1.4 * unit, delay: delay, shown: shown, reduce: reduceMotion)
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
/// смещением. Наклеены по одной, а не набраны абзацем.
private struct StickerQuoteView: View {

    let quote: StickerQuote
    let palette: StickerPalette
    let unit: CGFloat
    let shown: Bool
    let reduce: Bool

    /// Наклоны и смещения повторяются по кругу — так строки не выстраиваются
    /// по линейке, но и не пляшут случайно при каждом показе. Смещения
    /// разнонаправленные: лесенка вправо превратила бы колонку в кашу.
    private static let tilts: [Double] = [-2.1, 1.1, -1.2, 0.8]
    private static let shifts: [CGFloat] = [-1.1, 1.4, -0.6, 0.9]

    var body: some View {
        VStack(spacing: 0.7 * unit) {
            ForEach(Array(quote.lines.enumerated()), id: \.offset) { index, line in
                let tilt = Self.tilts[index % Self.tilts.count]
                pill(line, isLast: index == quote.lines.count - 1)
                    // Наклон анимируется вместе с масштабом, поэтому живёт
                    // внутри шлепка, а не отдельным модификатором.
                    .modifier(Stamp(
                        fromScale: 0.62, fromRotation: tilt * 3.2, rotation: tilt,
                        // 70 мс между строками: глаз успевает заметить очередь,
                        // но не начинает ждать.
                        delay: 0.24 + 0.07 * Double(index),
                        shown: shown, reduce: reduce
                    ))
                    .offset(x: Self.shifts[index % Self.shifts.count] * unit)
            }
        }
    }

    /// Последняя строка — ударная, поэтому другого цвета. Одностроч­ная реплика
    /// вся ударная: делить в ней нечего.
    private func pill(_ line: String, isLast: Bool) -> some View {
        Text(line)
            .font(.system(size: 2.9 * unit, weight: .black, design: .rounded))
            .foregroundStyle(isLast ? palette.accentInk : palette.baseInk)
            .padding(.horizontal, 2.4 * unit)
            .padding(.top, 1.15 * unit)
            .padding(.bottom, 1.35 * unit)
            .background(Capsule().fill(isLast ? palette.accent : palette.base))
            // Кант — не обводка внутрь, а белая капсула снаружи: она шире
            // ровно на толщину канта и повторяет то же скругление.
            .padding(0.55 * unit)
            .background(Capsule().fill(.white))
            // Без схлопывания тень ложится на каждый слой фона отдельно, и
            // внутренняя цветная капсула затеняет белый кант до серого.
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 1.4 * unit, y: 0.85 * unit)
    }
}

/// Шлепок: приходит крупнее нужного, с перекрученным наклоном, и садится на
/// место с перелётом. Пружина недодемпфирована нарочно — без перелёта это уже
/// не шлепок, а просто масштабирование.
private struct Stamp: ViewModifier {

    let fromScale: CGFloat
    let fromRotation: Double
    let rotation: Double
    let delay: Double
    let shown: Bool
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(shown || reduce ? rotation : fromRotation))
            .scaleEffect(shown || reduce ? 1 : fromScale)
            .opacity(shown ? 1 : 0)
            .animation(
                reduce
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.38, dampingFraction: 0.58).delay(delay),
                value: shown
            )
    }
}

/// Всплытие: то же появление, но без масштаба и без перелёта — для тихого
/// режима, где ничего не шлёпается.
private struct Rise: ViewModifier {

    let distance: CGFloat
    let delay: Double
    let shown: Bool
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduce ? 0 : distance)
            .opacity(shown ? 1 : 0)
            .animation(
                reduce
                    ? .easeOut(duration: 0.2)
                    : .easeOut(duration: 0.52).delay(delay),
                value: shown
            )
    }
}

/// Прямоугольник со скруглённым низом. Снимки обрезаны по грудь, и ровная
/// линия снизу выдаёт кадрирование; скругление читается как край наклейки.
private struct BottomRounded: Shape {

    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Фотография, вырезанная по контуру: белый кант — это восемь копий силуэта
/// со смещением под самим снимком. Силуэт берётся из альфа-канала, поэтому
/// PNG обязан быть с прозрачным фоном.
///
/// Маска низа накладывается до канта: иначе кант обошёл бы исходный
/// прямоугольник и скругление осталось бы незаметным.
private struct DieCutPhoto: View {

    let photo: NSImage
    let height: CGFloat
    let ring: CGFloat

    private static let directions: [(CGFloat, CGFloat)] = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
        (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7)
    ]

    /// Ширина считается из пикселей файла: у NSImage.size она зависит от DPI,
    /// а снимки приходят разные.
    private var aspect: CGFloat {
        if let rep = photo.representations.first, rep.pixelsHigh > 0 {
            return CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
        }
        return photo.size.height > 0 ? photo.size.width / photo.size.height : 1
    }

    var body: some View {
        let width = height * aspect
        let mask = BottomRounded(radius: width * 0.3)

        ZStack {
            ForEach(Array(Self.directions.enumerated()), id: \.offset) { _, direction in
                Image(nsImage: photo)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .mask(mask)
                    .offset(x: direction.0 * ring, y: direction.1 * ring)
            }
            Image(nsImage: photo)
                .resizable()
                .scaledToFit()
                .mask(mask)
        }
        .frame(width: width, height: height)
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
