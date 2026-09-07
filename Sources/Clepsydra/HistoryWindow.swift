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
        window.show(rows: rows())
    }

    /// История подросла. Окно на экране пересобираем на месте — молча, не
    /// поднимая его и не забирая фокус: помидор, закрытый под открытым окном,
    /// обязан попасть в список, иначе окно и строка в меню разойдутся в числах.
    /// Закрытого окна это не касается: оно соберётся заново при следующем
    /// щелчке.
    func refresh() {
        guard let window, window.isVisible else { return }
        window.render(rows: rows())
    }

    /// Строки окна. День, чьё число в хранилище не похоже на дату, выпадает
    /// молча — так же, как выпадал из подменю.
    private func rows() -> [String] {
        let today = Day(of: Date())
        return history().days.compactMap { TallyLabel.day($0, relativeTo: today) }
    }
}

/// Обычное окно, а не экран: с заголовком, красной кнопкой и ⌘W.
final class HistoryWindow: NSWindow {

    /// Код клавиши W. Спрашиваем сначала код, а символ — вторым: в кириллице
    /// та же клавиша отдаёт «ц», и по одному символу ⌘W не узнать.
    private static let wKeyCode: UInt16 = 13

    private static let size = NSSize(width: 320, height: 420)

    private let content = NSHostingView(rootView: HistoryView(rows: []))

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Окно называется тем же словом, что и то, что оно показывает.
        title = "История"
        minSize = NSSize(width: 260, height: 200)
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
    func render(rows: [String]) {
        content.rootView = HistoryView(rows: rows)
    }

    /// Показывает окно с этими строками. Содержимое пересобирается на каждый
    /// щелчок: пока окно было закрыто, история могла подрасти.
    func show(rows: [String]) {
        render(rows: rows)
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

/// Список дней. Строки ничего не делают по щелчку: они сообщают, а не
/// действуют, — поэтому это текст, а не список с выделением.
struct HistoryView: View {

    let rows: [String]

    var body: some View {
        if rows.isEmpty {
            // Пустое окно человек читает как поломку, поэтому у пустой истории
            // есть своя строка.
            Text(TallyLabel.empty)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    // Ключ — место в списке, а не сама строка: две одинаковые
                    // строки список бы перепутал.
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}
