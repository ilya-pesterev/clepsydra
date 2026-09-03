import Foundation
import ClepsydraCore

/// То немногое, что переживает перезапуск. Длительности зашиты, поэтому здесь
/// только режим цитат и история по дням; запуск при входе живёт в системе, а не
/// здесь.
enum Settings {

    private static let modeKey = "quoteMode"
    private static let historyKey = "history"
    // Прежнее хранение: один день и счёт за него. Читается один раз, при
    // переезде, и после этого стирается.
    private static let tallyDayKey = "tallyDay"
    private static let tallySessionsKey = "tallySessions"

    static var quoteMode: QuoteMode {
        get {
            UserDefaults.standard.string(forKey: modeKey)
                .flatMap(QuoteMode.init(rawValue:)) ?? .philosophers
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    /// История хранится словарём «день — счёт»: приложение копит числа по дням
    /// и не отсекает старые, см. ADR-0006.
    static var history: History {
        get {
            History(stored: UserDefaults.standard.dictionary(forKey: historyKey) ?? [:])
        }
        set {
            UserDefaults.standard.set(newValue.stored, forKey: historyKey)
        }
    }

    /// Переезд с прежнего хранения, где помнился один день. Зовётся при запуске
    /// и только там: старые ключи стираются сразу, поэтому во второй раз
    /// переезжать уже нечему.
    static func migrateLegacyTally() {
        let defaults = UserDefaults.standard
        let tally = History(
            day: Day(stamp: defaults.integer(forKey: tallyDayKey)),
            sessions: defaults.integer(forKey: tallySessionsKey)
        )
        defaults.removeObject(forKey: tallyDayKey)
        defaults.removeObject(forKey: tallySessionsKey)

        // Пустой счёт — это чистая установка либо уже состоявшийся переезд;
        // затирать им накопленную историю нельзя.
        guard tally != History(), defaults.object(forKey: historyKey) == nil else { return }
        history = tally
    }
}
