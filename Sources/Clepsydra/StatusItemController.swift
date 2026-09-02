import AppKit
import ClepsydraCore

/// Иконка в меню-баре и меню под ней. Иконка на месте всегда — приложение не
/// должно «исчезать» в простое; отсчёт появляется рядом, только когда он есть.
final class StatusItemController: NSObject, NSMenuDelegate {

    /// Что делать по пунктам меню — решает AppDelegate.
    struct Actions {
        let start: () -> Void
        let reset: () -> Void
        let toggleLaunchAtLogin: () -> Void
        let setMode: (QuoteMode) -> Void
        let showAbout: () -> Void
        let quit: () -> Void
    }

    private let item: NSStatusItem
    private let actions: Actions
    private var phase: Phase = .idle

    init(actions: Actions) {
        self.actions = actions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        item.button?.toolTip = "Clepsydra"
        item.button?.imagePosition = .imageLeading
        // Моноширинные цифры: иначе 09:59 → 10:00 дёргает соседние иконки.
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        render(phase: .idle, remaining: nil)
    }

    func render(phase: Phase, remaining: TimeInterval?) {
        self.phase = phase
        item.button?.image = Self.icon(for: phase)
        item.button?.title = remaining.map { " " + Countdown.text(for: $0) } ?? ""
    }

    private static func icon(for phase: Phase) -> NSImage? {
        let name: String
        switch phase {
        case .idle, .pomodoro, .awaitingPomodoro:
            name = "hourglass"
        case .onBreak, .awaitingBreak:
            name = "cup.and.saucer.fill"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Clepsydra")
        image?.isTemplate = true
        return image
    }

    // MARK: Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        switch phase {
        case .idle:
            menu.addItem(entry("Запустить сессию", #selector(start)))
        case .pomodoro, .onBreak:
            menu.addItem(entry("Сбросить", #selector(reset)))
        case .awaitingBreak, .awaitingPomodoro:
            // Меню под полноэкранным экраном недостижимо, но пустым его не оставляем.
            break
        }

        menu.addItem(.separator())

        // Режимы — группой с галочкой у выбранного: так видно, что их два и
        // какой сейчас работает. Одного переключателя для этого мало.
        let mode = Settings.quoteMode

        let philosophers = entry("Режим философов", #selector(selectPhilosophers))
        philosophers.state = mode == .philosophers ? .on : .off
        menu.addItem(philosophers)

        let statham = entry("Режим Стетхема", #selector(selectStatham))
        statham.state = mode == .statham ? .on : .off
        menu.addItem(statham)

        menu.addItem(.separator())

        let launch = entry("Запускать при входе", #selector(toggleLaunchAtLogin))
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        menu.addItem(entry("О программе", #selector(showAbout)))
        menu.addItem(entry("Выйти", #selector(quit)))
    }

    private func entry(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func start() { actions.start() }
    @objc private func reset() { actions.reset() }
    @objc private func toggleLaunchAtLogin() { actions.toggleLaunchAtLogin() }
    @objc private func selectPhilosophers() { actions.setMode(.philosophers) }
    @objc private func selectStatham() { actions.setMode(.statham) }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }
}
