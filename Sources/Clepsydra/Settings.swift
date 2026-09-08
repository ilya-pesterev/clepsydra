import Foundation
import ClepsydraCore

/// То немногое, что переживает перезапуск: выбранные длительности, режим цитат,
/// напоминание, история по дням и результат последней проверки обновлений.
/// Запуск при входе живёт в системе, а не здесь; там же живёт и разрешение на
/// уведомления — здесь только то, что человек выбрал сам.
enum Settings {

    private static let durationsKey = "durations"
    private static let modeKey = "quoteMode"
    private static let reminderKey = "reminder"
    private static let historyKey = "history"
    private static let lastUpdateCheckKey = "lastUpdateCheck"
    private static let knownUpdateKey = "knownUpdate"
    // Прежнее хранение: один день и счёт за него. Читается один раз, при
    // переезде, и после этого стирается.
    private static let tallyDayKey = "tallyDay"
    private static let tallySessionsKey = "tallySessions"

    /// Выбранные длины помидора и перерыва. Пусто — прежние 25 и 5 минут;
    /// разумность значений проверяет сам `Durations`, см. ADR-0011.
    static var durations: Durations {
        get {
            Durations(stored: UserDefaults.standard.dictionary(forKey: durationsKey) ?? [:])
        }
        set {
            UserDefaults.standard.set(newValue.stored, forKey: durationsKey)
        }
    }

    static var quoteMode: QuoteMode {
        get {
            UserDefaults.standard.string(forKey: modeKey)
                .flatMap(QuoteMode.init(rawValue:)) ?? .philosophers
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    /// Включено ли напоминание. Выключено по умолчанию: обновившаяся копия не
    /// начинает говорить с теми, кто об этом не просил (ADR-0014).
    ///
    /// Разрешение системы здесь не хранится — его спрашивают у системы, см.
    /// `Reminders`. Включённый выбор при отозванном разрешении не врёт: пункт
    /// меню показывает третье лицо, а не галочку.
    static var reminderIsOn: Bool {
        get { UserDefaults.standard.bool(forKey: reminderKey) }
        set { UserDefaults.standard.set(newValue, forKey: reminderKey) }
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

    /// Когда фид ответил в последний раз. Пусто — не проверяли ни разу.
    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }

    /// Что фид сказал в последний раз. Хранится словарём, как история: пункт
    /// меню помнит вышедшую версию и после перезапуска, а не молчит до
    /// следующих суток.
    static var knownUpdate: Update? {
        get { Update(fields: UserDefaults.standard.dictionary(forKey: knownUpdateKey) ?? [:]) }
        set { UserDefaults.standard.set(newValue?.stored, forKey: knownUpdateKey) }
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
