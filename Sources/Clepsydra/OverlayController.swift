import AppKit
import SwiftUI
import ClepsydraCore

/// Держит полноэкранные окна — по одному на каждый монитор. Кнопки живут только
/// на том экране, где сейчас курсор; цитата, отсчёт и подсказка — на всех.
///
/// Содержимое отделено от окон: за один показ оно меняется — кнопка «Отдохнуть»
/// уступает место отсчёту перерыва, — а пересобирать при этом окна незачем.
final class OverlayController {

    private var windows: [OverlayWindow] = []
    private var model: OverlayModel?

    /// Что делать по ⌘⇧0. Задаётся один раз при запуске.
    var onEscape: (() -> Void)?

    var isVisible: Bool { model != nil }

    /// Показать экран или, если он уже висит, сменить его содержимое без
    /// повторного проявления.
    func present(content: OverlayContent, actions: [OverlayAction]) {
        if let model {
            model.content = content
            model.countdown = nil
            model.actions = actions
            return
        }
        model = OverlayModel(content: content, actions: actions)
        build(animated: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Перерыв пошёл: кнопки убираем, вместо них — отсчёт.
    func showCountdown(_ text: String) {
        guard let model else { return }
        if !model.actions.isEmpty { model.actions = [] }
        if model.countdown != text { model.countdown = text }
    }

    func dismiss() {
        model = nil
        tearDown()
        // Фокус мы забрали силой — возвращаем его тому, кто работал до нас,
        // иначе после «Начать» человек сядет печатать в пустоту.
        NSApp.deactivate()
    }

    /// Подключили или отключили монитор — пересобираем набор окон, иначе на
    /// новом экране остался бы голый рабочий стол с недоступным меню-баром.
    func screenConfigurationChanged() {
        guard isVisible else { return }
        build(animated: false)
    }

    // MARK: Окна

    private func build(animated: Bool) {
        guard let model else { return }
        tearDown()

        // Список экранов берём один раз: NSScreen.screens возвращает новый
        // массив на каждый вызов, и сравнивать по ссылке элементы разных
        // вызовов нельзя. Промахнёмся — кнопок не будет ни на одном экране.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let pointer = NSEvent.mouseLocation
        let withActions = screens.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0

        for (index, screen) in screens.enumerated() {
            let window = OverlayWindow(screen: screen)
            window.onEscape = { [weak self] in self?.onEscape?() }
            let view = OverlayView(
                model: model,
                showsActions: index == withActions,
                screenWidth: screen.frame.width
            )
            window.install(view, on: screen)
            window.alphaValue = animated ? 0 : 1
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Ключевым делаем именно окно с кнопками: иначе первый клик уйдёт на
        // то, чтобы сделать окно ключевым, и до кнопки не дойдёт.
        windows[withActions].makeKey()

        guard animated else { return }
        // Мгновенная тёмная вспышка на весь экран физически неприятна.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func tearDown() {
        windows.forEach {
            $0.contentView = nil
            $0.orderOut(nil)
        }
        windows = []
    }
}
