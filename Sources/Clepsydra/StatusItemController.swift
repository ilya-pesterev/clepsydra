import AppKit
import ClepsydraCore

/// Иконка в меню-баре и меню под ней. Иконка на месте всегда — приложение не
/// должно «исчезать» в простое; отсчёт появляется рядом, только когда он есть.
final class StatusItemController: NSObject, NSMenuDelegate {

    /// Что делать по пунктам меню — решает AppDelegate.
    struct Actions {
        let start: () -> Void
        let reset: () -> Void
        let setDurations: (Durations) -> Void
        let toggleLaunchAtLogin: () -> Void
        let toggleReminder: () -> Void
        let openReminderSettings: () -> Void
        let setMode: (QuoteMode) -> Void
        let showHistory: () -> Void
        let checkForUpdates: () -> Void
        let installUpdate: () -> Void
        let showAbout: () -> Void
        let quit: () -> Void
    }

    private let item: NSStatusItem
    private let actions: Actions
    /// Историю спрашиваем в момент открытия меню, а не храним: тогда полночь
    /// сама сдвигает счёт за сегодня — без будильника на 00:00.
    private let history: () -> History
    /// Что известно об обновлении — спрашиваем так же, в момент открытия меню:
    /// тихая проверка могла ответить, пока меню было закрыто.
    private let updateState: () -> UpdateState
    /// Какие длины работают прямо сейчас. Спрашиваем автомат, а не хранилище:
    /// длину правят и мимо меню (ADR-0011), и до перезапуска автомат живёт со
    /// старой. Галочка обязана стоять у той длины, по которой идёт отсчёт.
    private let durations: () -> Durations
    /// Что известно про напоминание. Спрашиваем в момент открытия меню, но
    /// ответ приходит из кэша: разрешение сверяется с системой на тике, раз в
    /// минуту, — спрашивать её на открытии меню значило бы ждать ответа с
    /// нарисованным пунктом.
    private let reminderState: () -> ReminderState
    private var phase: Phase = .idle

    init(
        actions: Actions,
        history: @escaping () -> History,
        updateState: @escaping () -> UpdateState,
        durations: @escaping () -> Durations,
        reminderState: @escaping () -> ReminderState
    ) {
        self.actions = actions
        self.history = history
        self.updateState = updateState
        self.durations = durations
        self.reminderState = reminderState
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

        // Прошедшие дни живут окном, а не подменю: список не обязан помещаться
        // в меню, см. ADR-0012. Пункт стоит на месте и при пустой истории —
        // исчезающий пункт меню человек считает поломкой.
        menu.addItem(entry("История", #selector(showHistory)))

        menu.addItem(.separator())

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

        // Длительности — подменю, а не строки в корне: выбирают их редко, а
        // шесть строк выдавили бы вниз всё остальное (ADR-0011).
        menu.addItem(lengths())

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

        // Переключателей в корне меню два: напоминание и запуск при входе.
        // Окна настроек это не заводит — ADR-0011 в силе.
        menu.addItem(reminderEntry())

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
        // Знаем про новую версию — ставим её; во всех остальных лицах пункт
        // проверяет. «Установлена последняя версия» — и ответ на прошлый
        // щелчок, и приглашение спросить снова.
        if case .ready = state {
            return entry(UpdateLabel.title(for: state), #selector(installUpdate))
        }
        return entry(UpdateLabel.title(for: state), #selector(checkForUpdates))
    }

    /// Пункт напоминания. Лиц у него, как у пункта обновления, больше одного:
    /// разрешение отзывают в системных настройках, и включённый пункт при
    /// отозванном разрешении — молчащее напоминание, которое человек считает
    /// поломкой (ADR-0014). Третье лицо ведёт туда, где запрет и снимают.
    private func reminderEntry() -> NSMenuItem {
        let state = reminderState()
        let action = state == .silenced
            ? #selector(openReminderSettings) : #selector(toggleReminder)
        let item = entry(ReminderLabel.menu(for: state), action)
        item.state = ReminderLabel.isOn(state) ? .on : .off
        return item
    }

    /// Подменю с длинами: сначала помидор, потом перерыв, у выбранных длин —
    /// галочка.
    ///
    /// Галочки может не оказаться ни одной: длину правят и мимо меню, через
    /// `defaults write`. Тогда подменю честно показывает, что ни одна из
    /// предложенных сейчас не работает.
    private func lengths() -> NSMenuItem {
        let chosen = durations()
        let submenu = NSMenu()

        group(titled: "Сессия", choices: Durations.pomodoroChoices, current: chosen.pomodoro,
              in: submenu) { Durations(pomodoro: $0, breakInterval: chosen.breakInterval) }

        submenu.addItem(.separator())

        group(titled: "Перерыв", choices: Durations.breakChoices, current: chosen.breakInterval,
              in: submenu) { Durations(pomodoro: chosen.pomodoro, breakInterval: $0) }

        let item = NSMenuItem(title: "Длительность", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Группа длин под серой строкой-заголовком. Заголовок обязателен: без него
    /// «5 минут» под «45 минут» не отличить от четвёртой длины помидора.
    ///
    /// `chosen` собирает пару целиком — щёлкнули по длине помидора, перерыв
    /// остался прежним. Пара едет в `representedObject`: иначе под каждую длину
    /// пришлось бы заводить свой `@objc`-метод.
    private func group(
        titled title: String,
        choices: [TimeInterval],
        current: TimeInterval,
        in submenu: NSMenu,
        chosen: (TimeInterval) -> Durations
    ) {
        submenu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        for length in choices {
            let item = entry(DurationLabel.minutes(length), #selector(selectDurations))
            item.representedObject = chosen(length)
            item.state = length == current ? .on : .off
            submenu.addItem(item)
        }
    }

    private func entry(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func start() { actions.start() }
    @objc private func reset() { actions.reset() }

    @objc private func selectDurations(_ sender: NSMenuItem) {
        guard let chosen = sender.representedObject as? Durations else { return }
        actions.setDurations(chosen)
    }

    @objc private func toggleLaunchAtLogin() { actions.toggleLaunchAtLogin() }
    @objc private func toggleReminder() { actions.toggleReminder() }
    @objc private func openReminderSettings() { actions.openReminderSettings() }
    @objc private func selectPhilosophers() { actions.setMode(.philosophers) }
    @objc private func selectStatham() { actions.setMode(.statham) }
    @objc private func checkForUpdates() { actions.checkForUpdates() }
    @objc private func installUpdate() { actions.installUpdate() }
    @objc private func showHistory() { actions.showHistory() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }
}
