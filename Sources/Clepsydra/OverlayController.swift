import AppKit
import SwiftUI
import ClepsydraCore

/// Первый клик должен попадать в кнопку, а не тратиться на то, чтобы сделать
/// окно ключевым. `acceptsFirstMouse` живёт на вью, а не на окне.
private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Держит полноэкранные окна — по одному на каждый монитор. Кнопки живут только
/// на том экране, где сейчас курсор; остальные показывают ту же цитату.
final class OverlayController {

    private struct Presentation {
        let quote: Quote
        let actions: [OverlayAction]
    }

    private var windows: [OverlayWindow] = []
    private var presentation: Presentation?

    var isVisible: Bool { presentation != nil }

    func show(quote: Quote, actions: [OverlayAction]) {
        presentation = Presentation(quote: quote, actions: actions)
        build(animated: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        presentation = nil
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
        guard let presentation else { return }
        tearDown()

        // Список экранов берём один раз: NSScreen.screens возвращает новый
        // массив на каждый вызов, и сравнивать по ссылке элементы разных
        // вызовов нельзя. Промахнёмся — кнопок не будет ни на одном экране,
        // а экран без кнопок закрыть нечем.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let pointer = NSEvent.mouseLocation
        let withActions = screens.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0

        for (index, screen) in screens.enumerated() {
            let window = OverlayWindow(screen: screen)
            let view = OverlayView(
                quote: presentation.quote,
                actions: index == withActions ? presentation.actions : []
            )
            window.contentView = OverlayHostingView(rootView: view)
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
