import AppKit
import SwiftUI
import ClepsydraCore

/// Окно «История»: все дни со счётом, свежие сверху. Приходит по щелчку по
/// пункту меню и только по нему — само не разворачивается и поверх работы не
/// встаёт, см. ADR-0012. На круг не влияет: помидор под ним идёт своим ходом,
/// а экран с цитатой приходит поверх — он живёт уровнем `.screenSaver`.
final class HistoryController {

    /// Историю спрашиваем в момент показа, а не храним: между двумя открытиями
    /// окна помидоры успевают закрыться, а полночь — пройти.
    private let history: () -> History

    /// Окно одно на все щелчки: второй щелчок по пункту меню поднимает то же
    /// самое, а не заводит второе такое же.
    private var window: HistoryWindow?

    init(history: @escaping () -> History) {
        self.history = history
    }

    func show() {
        let window = self.window ?? HistoryWindow()
        self.window = window
        window.show(content: content())
    }

    /// История подросла. Окно на экране пересобираем на месте — молча, не
    /// поднимая его и не забирая фокус: помидор, закрытый под открытым окном,
    /// обязан попасть в список, иначе окно и строка в меню разойдутся в числах.
    /// Закрытого окна это не касается: оно соберётся заново при следующем
    /// щелчке.
    func refresh() {
        guard let window, window.isVisible else { return }
        window.render(content: content())
    }

    /// Что показывает окно: итог и строки дней. День, чьё число в хранилище не
    /// похоже на дату, выпадает молча — так же, как выпадал из подменю.
    private func content() -> HistoryContent {
        let history = self.history()
        let today = Day(of: Date())
        return HistoryContent(
            summary: history.summary.map { SummaryLabel.lines($0, relativeTo: today) } ?? [],
            rows: history.days.compactMap { TallyLabel.day($0, relativeTo: today) }
        )
    }
}

/// Содержимое окна: итог над списком и сам список. Одной величиной, а не двумя
/// параметрами, — итог и дни считаются вместе и вместе же обязаны меняться,
/// иначе окно покажет итог не тех дней, что показывает списком.
struct HistoryContent: Equatable {
    let summary: [String]
    let rows: [String]
}

/// Обычное окно, а не экран: с заголовком, красной кнопкой и ⌘W.
final class HistoryWindow: NSWindow {

    /// Код клавиши W. Спрашиваем сначала код, а символ — вторым: в кириллице
    /// та же клавиша отдаёт «ц», и по одному символу ⌘W не узнать.
    private static let wKeyCode: UInt16 = 13

    private static let size = NSSize(width: 360, height: 460)

    private let content = NSHostingView(
        rootView: HistoryView(content: HistoryContent(summary: [], rows: []))
    )

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Окно называется тем же словом, что и то, что оно показывает.
        title = "История"
        // Строка дня со временем — «2 сентября — 5 сессий, 2 часа 5 минут» —
        // самое длинное, что окно показывает; уже неё сужать нечего.
        minSize = NSSize(width: 300, height: 220)
        // Сворачивать нечего: окно открывают, читают и закрывают. Свёрнутое
        // окно было бы ещё одним состоянием, из которого пункт меню обязан
        // его доставать, — поэтому кнопки сворачивания у окна нет.

        // Красная кнопка окно закрывает, но не разрушает: за пунктом меню
        // остаётся то же самое окно.
        isReleasedWhenClosed = false

        // SwiftUI ставим внутрь контейнера, не отдавая ему право менять размер
        // окна: голый `NSHostingView` в роли `contentView` подгоняет окно под
        // свой контент — см. `OverlayWindow.install`.
        content.translatesAutoresizingMaskIntoConstraints = true
        content.frame = NSRect(origin: .zero, size: Self.size)
        content.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.autoresizesSubviews = true
        container.addSubview(content)
        contentView = container

        center()
    }

    /// Строки без окна: содержимое меняется, а само окно не двигается.
    func render(content: HistoryContent) {
        self.content.rootView = HistoryView(content: content)
    }

    /// Показывает окно с этим содержимым. Оно пересобирается на каждый щелчок:
    /// пока окно было закрыто, история могла подрасти.
    func show(content: HistoryContent) {
        render(content: content)
        // Приложение фоновое (.accessory), поэтому окно надо не только
        // показать, но и вывести вперёд — иначе оно откроется за чужими окнами.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// ⌘W закрывает окно. Само оно этого не умеет: комбинация работает от
    /// пункта «Закрыть» в главном меню, а у фонового приложения главного меню
    /// нет.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isW = event.keyCode == Self.wKeyCode
            || event.charactersIgnoringModifiers?.lowercased() == "w"
        guard pressed == .command, isW else {
            return super.performKeyEquivalent(with: event)
        }
        performClose(nil)
        return true
    }
}

/// Итог и список дней. Строки ничего не делают по щелчку: они сообщают, а не
/// действуют, — поэтому это текст, а не список с выделением.
struct HistoryView: View {

    let content: HistoryContent

    var body: some View {
        if content.rows.isEmpty {
            // Пустое окно человек читает как поломку, поэтому у пустой истории
            // есть своя строка.
            Text(TallyLabel.empty)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Итог не уезжает вместе со списком: он про всю историю, а не
                // про то место, до которого долистали.
                summary
                Divider()
                days
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(content.summary.enumerated()), id: \.offset) { place, line in
                // Первая строка — «Всего»: с неё читают, и она главная.
                Text(line)
                    .font(place == 0 ? .headline : .body)
                    .foregroundStyle(place == 0 ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var days: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                // Ключ — место в списке, а не сама строка: две одинаковые
                // строки список бы перепутал.
                ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}
