import AppKit
import SwiftUI

/// Первый клик должен попадать в кнопку, а не тратиться на то, чтобы сделать
/// окно ключевым. `acceptsFirstMouse` живёт на вью, а не на окне.
private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Окно с цитатой: во весь экран, поверх всего, включая чужой полноэкранный
/// режим. Закрывается только кликом по кнопке — ни Esc, ни Cmd+W, ни Enter.
final class OverlayWindow: NSWindow {

    /// Код клавиши «0» в верхнем ряду. Проверяем именно код, а не символ:
    /// с зажатым Shift раскладка отдаёт «)», а в кириллице — своё.
    private static let zeroKeyCode: UInt16 = 29

    /// Запасной выход по ⌘⇧0.
    var onEscape: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)

        // Выше строки меню и выше чужого fullscreen.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    /// Ставит SwiftUI внутрь окна, не отдавая ему право менять размер окна.
    /// Голый `NSHostingView` в роли `contentView` подгоняет окно под свой
    /// контент: экран 2304×1296 превращался в окно 2304×2165 со сдвигом вниз,
    /// и кнопка уезжала за нижнюю кромку — цитата видна, нажать нечего.
    func install<Content: View>(_ view: Content, on screen: NSScreen) {
        let hosting = OverlayHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizesSubviews = true
        container.addSubview(hosting)

        contentView = container
        // Контент уже на месте — возвращаем окну размер экрана на случай, если
        // вёрстка всё же попыталась его подвинуть.
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Клавиатуру глотаем целиком: Enter — это рефлекс, которым экран закрыли бы
    // до того, как прочитали цитату. Единственное исключение — ⌘⇧0: комбинация
    // нарочно неудобная, её не нажмёшь мимоходом, но она есть, если кнопка
    // почему-то недоступна.
    override func keyDown(with event: NSEvent) {
        _ = handleEscape(event)
    }

    override func cancelOperation(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        _ = handleEscape(event)
        return true
    }

    private func handleEscape(_ event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.command, .shift]
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard pressed.isSuperset(of: required) else { return false }

        let isZero = event.keyCode == Self.zeroKeyCode
            || event.charactersIgnoringModifiers == "0"
            || event.charactersIgnoringModifiers == ")"
        guard isZero else { return false }

        onEscape?()
        return true
    }
}
