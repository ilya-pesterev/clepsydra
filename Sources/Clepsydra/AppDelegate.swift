import AppKit
import ClepsydraCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var machine = TimerMachine()
    private var statusItem: StatusItemController!
    private let overlay = OverlayController()
    private var ticker: Timer?
    private var lastQuote: Quote?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = StatusItemController(actions: .init(
            start: { [weak self] in self?.update { $0.start(at: Date()) } },
            reset: { [weak self] in self?.update { $0.reset() } },
            toggleLaunchAtLogin: { LaunchAtLogin.toggle() },
            quit: { NSApp.terminate(nil) }
        ))

        // Запасной выход с экрана: работает из любой фазы с экраном и всегда
        // возвращает в простой.
        overlay.onEscape = { [weak self] in self?.update { $0.escape() } }

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
        update { $0.advance(to: Date()) }
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
        case .pomodoroFinished:
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
        let quote = Quotes.next(after: lastQuote)
        lastQuote = quote
        overlay.show(quote: quote, actions: actions)
    }

    private func refresh() {
        statusItem.render(phase: machine.phase, remaining: machine.remaining(at: Date()))
    }
}
