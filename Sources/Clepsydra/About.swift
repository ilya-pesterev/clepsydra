import AppKit

/// Окно «О программе». Берём системное: оно само подхватывает имя и версию из
/// Info.plist, выглядит как везде и не требует своей вёрстки.
enum About {

    static func show() {
        // Приложение фоновое, поэтому окно надо не только показать, но и
        // вывести вперёд — иначе оно откроется за чужими окнами.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 4

        let common: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: centered
        ]

        let text = NSMutableAttributedString(
            string: "Илья Пестерев\n",
            attributes: common.merging([.foregroundColor: NSColor.labelColor]) { $1 }
        )
        text.append(NSAttributedString(
            string: "ipesterev.ru",
            attributes: common.merging([.link: URL(string: "https://ipesterev.ru")!]) { $1 }
        ))
        return text
    }
}
