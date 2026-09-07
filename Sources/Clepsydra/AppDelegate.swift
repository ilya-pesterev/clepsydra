import AppKit
import ClepsydraCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var machine = TimerMachine(durations: Settings.durations)
    private var statusItem: StatusItemController!
    private let overlay = OverlayController()
    private var ticker: Timer?
    private var lastQuote: Quote?
    private var lastSticker: StickerQuote?
    private var mode: QuoteMode = Settings.quoteMode
    private var history: History = Settings.history
    private var historyWindow: HistoryController!
    private let updates = UpdateChecker()
    private var installer: UpdateInstaller!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Установщик обновлений. Заводится тут, но до первого щелчка по
        // «Обновить до 1.1» ничего не делает — ни сети, ни расписания.
        installer = UpdateInstaller(openReleasePage: { [weak self] in
            self?.updates.openReleasePage()
        })

        // Окно «История». Как и установщик, до первого щелчка по пункту меню
        // ничего не делает: окна не заводится, пока его не попросили.
        historyWindow = HistoryController(history: { [weak self] in
            self?.history ?? History()
        })

        statusItem = StatusItemController(actions: .init(
            start: { [weak self] in self?.update { $0.start(at: Date()) } },
            reset: { [weak self] in self?.update { $0.reset() } },
            setDurations: { [weak self] in self?.setDurations($0) },
            toggleLaunchAtLogin: { LaunchAtLogin.toggle() },
            setMode: { [weak self] in self?.setMode($0) },
            showHistory: { [weak self] in self?.historyWindow.show() },
            checkForUpdates: { [weak self] in self?.updates.checkNow() },
            installUpdate: { [weak self] in self?.installer.install() },
            showAbout: { About.show() },
            quit: { NSApp.terminate(nil) }
        ), history: { [weak self] in
            self?.history ?? History()
        }, updateState: { [weak self] in
            self?.updates.state ?? .unknown
        }, durations: { [weak self] in
            self?.machine.durations ?? .standard
        })

        // Запасной выход с экрана. Во время перерыва он лишь убирает экран:
        // отдых продолжается и досчитывает в меню-баре. В остальных случаях —
        // выводит из круга целиком.
        overlay.onEscape = { [weak self] in
            guard let self else { return }
            if case .onBreak = machine.phase {
                overlay.dismiss()
            } else {
                update { $0.escape() }
            }
        }

        startTicking()

        // Пробуждение из сна и ручная смена времени — те же вопросы к автомату,
        // что и обычный тик: сколько прошло с даты финиша.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(timeMayHaveMoved),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(timeMayHaveMoved),
            name: .NSSystemClockDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
    }

    // MARK: Ход времени

    private func startTicking() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.timeMayHaveMoved()
        }
        // .common — чтобы отсчёт не замирал, пока открыто меню.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        refresh()
    }

    @objc private func timeMayHaveMoved() {
        let now = Date()
        update { $0.advance(to: now) }
        // Тихая проверка обновлений висит на том же тике: вопрос к ней тот же —
        // сколько прошло с прошлого раза, — и сон она переживает так же. При
        // запуске в лицо ничего не проверяется: спросить фид и промолчать — это
        // и есть тихая проверка.
        updates.checkIfDue(now: now)
    }

    @objc private func screensChanged() {
        overlay.screenConfigurationChanged()
    }

    // MARK: Автомат и последствия

    /// Единственный вход в автомат: применили действие, разобрали эффекты,
    /// перерисовали меню-бар.
    private func update(_ action: (inout TimerMachine) -> [Effect]) {
        let effects = action(&machine)
        for effect in effects { apply(effect) }
        refresh()
    }

    private func apply(_ effect: Effect) {
        switch effect {
        case .pomodoroFinished(let length):
            // Считается только доведённый до конца помидор: сброшенный потерян
            // целиком (ADR-0003), просроченный во сне отменён молча (ADR-0002),
            // и сюда ни тот, ни другой не приходят.
            //
            // Длину берём у закончившегося помидора, а не у выбранной сейчас:
            // выбрать в меню другую могли посреди этого же помидора, и его она
            // не тронула.
            history.record(length: length, at: Date())
            Settings.history = history
            // Окно, открытое прямо сейчас, обязано узнать про этот помидор:
            // иначе оно и строка в меню разойдутся в числах.
            historyWindow.refresh()

            Sounds.pomodoroFinished()
            showOverlay(actions: [
                OverlayAction(title: "Отдохнуть", isPrimary: true) { [weak self] in
                    self?.update { $0.takeBreak(at: Date()) }
                }
            ])

        case .breakFinished:
            Sounds.breakFinished()
            showOverlay(actions: [
                OverlayAction(title: "Начать", isPrimary: true) { [weak self] in
                    self?.update { $0.start(at: Date()) }
                },
                OverlayAction(title: "Хватит", isPrimary: false) { [weak self] in
                    self?.update { $0.stop() }
                }
            ])

        case .dismissOverlay:
            overlay.dismiss()
        }
    }

    private func showOverlay(actions: [OverlayAction]) {
        overlay.present(content: nextContent(), actions: actions)
    }

    private func nextContent() -> OverlayContent {
        switch mode {
        case .philosophers:
            let quote = Quotes.next(after: lastQuote)
            lastQuote = quote
            return .philosopher(quote, portrait: PhilosopherPortraits.image(for: quote.author))
        case .statham:
            let quote = StathamQuotes.next(after: lastSticker)
            lastSticker = quote
            return .sticker(quote, palette: .random(), photo: StathamPhotos.random())
        }
    }

    /// Выбранные в меню длины. Идущий интервал не трогаем: он держит дату
    /// финиша, и сдвигать её посреди помидора значило бы обмануть отсчёт в
    /// меню-баре. Новая длина работает со следующего интервала.
    ///
    /// Пишем без сравнения с прежним: щелчок по длине, которая уже стоит,
    /// стоит одной записи в `UserDefaults` — а сравнение стоило бы того, что
    /// правка мимо меню осталась бы в хранилище неперебитой.
    private func setDurations(_ chosen: Durations) {
        update {
            $0.durations = chosen
            return []
        }
        Settings.durations = chosen
    }

    private func setMode(_ newMode: QuoteMode) {
        guard newMode != mode else { return }
        mode = newMode
        Settings.quoteMode = newMode
        // Экран, который висит прямо сейчас, переобувать не станем: человек
        // читает его в эту секунду. Переключатель сработает со следующего.
    }

    private func refresh() {
        let now = Date()
        let remaining = machine.remaining(at: now)
        statusItem.render(phase: machine.phase, remaining: remaining)

        // Экран, оставшийся на перерыв, показывает тот же отсчёт, что и меню-бар.
        if case .onBreak = machine.phase, overlay.isVisible, let remaining {
            overlay.showCountdown(Countdown.text(for: remaining))
        }
    }
}
