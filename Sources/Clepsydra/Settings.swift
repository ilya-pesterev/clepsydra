import Foundation
import ClepsydraCore

/// То немногое, что переживает перезапуск. Длительности зашиты, поэтому здесь
/// только режим цитат и счёт за день; запуск при входе живёт в системе, а не
/// здесь.
enum Settings {

    private static let modeKey = "quoteMode"
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

    /// Счёт хранится днём и числом, а не списком дней: приложение не ведёт
    /// дневник — вчерашнее число ему уже не нужно.
    static var dailyTally: DailyTally {
        get {
            let defaults = UserDefaults.standard
            let stamp = defaults.integer(forKey: tallyDayKey)
            guard stamp > 0 else { return DailyTally() }
            return DailyTally(day: Day(stamp: stamp), sessions: defaults.integer(forKey: tallySessionsKey))
        }
        set {
            UserDefaults.standard.set(newValue.day.stamp, forKey: tallyDayKey)
            UserDefaults.standard.set(newValue.storedSessions, forKey: tallySessionsKey)
        }
    }
}
