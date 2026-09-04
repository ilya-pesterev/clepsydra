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
        let checkForUpdates: () -> Void
        let openUpdate: () -> Void
        let showAbout: () -> Void
        let quit: () -> Void
    }

    /// Сколько прошедших дней показывать. Хранение глубину не ограничивает
    /// (ADR-0006), а меню обязано помещаться на экран — предел ставим здесь.
    /// Неделя: столько дней человек ещё помнит, и столько строк подменю не
    /// перерастает даже на ноутбучном экране.
    private static let recentDaysShown = 7

    private let item: NSStatusItem
    private let actions: Actions
    /// Историю спрашиваем в момент открытия меню, а не храним: тогда полночь
    /// сама сдвигает и счёт за сегодня, и список прошедших дней — без
    /// будильника на 00:00.
    private let history: () -> History
    /// Что известно об обновлении — спрашиваем так же, в момент открытия меню:
    /// тихая проверка могла ответить, пока меню было закрыто.
    private let updateState: () -> UpdateState
    private var phase: Phase = .idle

    init(
        actions: Actions,
        history: @escaping () -> History,
        updateState: @escaping () -> UpdateState
    ) {
        self.actions = actions
        self.history = history
        self.updateState = updateState
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

        let history = self.history()
        let today = Day(of: Date())

        // Счёт за день — строкой над пунктами: он сообщает, а не делает, и без
        // действия сереет сам. Пустой день строки не получает, см. TallyLabel.
        let tally = TallyLabel.today(sessions: history.sessions(on: today))
        if let tally {
            menu.addItem(NSMenuItem(title: tally, action: nil, keyEquivalent: ""))
        }

        // Прошедшие дни — подменю под этой строкой: отдельного окна под них
        // не заводим, см. ADR-0007.
        let recent = history.recent(before: today, limit: Self.recentDaysShown)
        if !recent.isEmpty {
            menu.addItem(recentDays(recent, relativeTo: today))
        }

        // Пока показывать нечего, полоски в пустоте не рисуем.
        if tally != nil || !recent.isEmpty {
            menu.addItem(.separator())
        }

        // Разделитель ставит тот, кто добавил пункт: иначе в фазах с экраном
        // меню начиналось бы с полоски в пустоте.
        switch phase {
        case .idle:
            menu.addItem(entry("Запустить сессию", #selector(start)))
            menu.addItem(.separator())
        case .pomodoro, .onBreak:
            menu.addItem(entry("Сбросить", #selector(reset)))
            menu.addItem(.separator())
        case .awaitingBreak, .awaitingPomodoro:
            // Меню под полноэкранным экраном недостижимо, но пустым его не оставляем.
            break
        }

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
        // Обновление стоит рядом с «О программе»: оба про версию, которая
        // сейчас установлена.
        menu.addItem(updateEntry())
        menu.addItem(entry("О программе", #selector(showAbout)))
        menu.addItem(entry("Выйти", #selector(quit)))
    }

    /// Пункт обновления. Лицо у него одно на все фазы: меню под экраном
    /// недостижимо по построению, и отличать его поведение от остальных
    /// пунктов не за что.
    ///
    /// Меню — единственное место, где проверка отвечает: окон она не
    /// открывает (см. ADR-0009). Поэтому ответ на щелчок человек видит,
    /// открыв меню снова, — щелчок его закрывает.
    private func updateEntry() -> NSMenuItem {
        let state = updateState()
        // Знаем про новую версию — ведём на страницу релиза; во всех
        // остальных лицах пункт проверяет. «Установлена последняя версия» —
        // и ответ на прошлый щелчок, и приглашение спросить снова.
        if case .ready = state {
            return entry(UpdateLabel.title(for: state), #selector(openUpdate))
        }
        return entry(UpdateLabel.title(for: state), #selector(checkForUpdates))
    }

    /// Подменю с прошедшими днями, свежие сверху. Строки без действия: они
    /// сообщают, а не действуют, — и сереют сами, как строка про сегодня.
    /// Пункт с подменю AppKit оставляет доступным и при серых строках внутри.
    private func recentDays(_ recent: [DayTally], relativeTo today: Day) -> NSMenuItem {
        let days = NSMenuItem(title: "Последние дни", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for title in recent.compactMap({ TallyLabel.past($0, relativeTo: today) }) {
            submenu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        days.submenu = submenu
        return days
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
    @objc private func checkForUpdates() { actions.checkForUpdates() }
    @objc private func openUpdate() { actions.openUpdate() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }
}
