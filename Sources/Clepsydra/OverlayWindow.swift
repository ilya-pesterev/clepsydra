import AppKit

/// Окно с цитатой: во весь экран, поверх всего, включая чужой полноэкранный
/// режим. Закрывается только кликом по кнопке — ни Esc, ни Cmd+W, ни Enter.
final class OverlayWindow: NSWindow {

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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Клавиатуру глотаем целиком: Enter — это рефлекс, которым экран закрыли бы
    // до того, как прочитали цитату. Выход всегда есть и всегда в один клик.
    override func keyDown(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}
