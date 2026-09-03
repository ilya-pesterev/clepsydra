import Foundation

/// Сколько помидоров закрыто сегодня. Помнит ровно один день: наступила
/// полночь — счёт начинается заново, вчерашнее число никуда не переносится.
///
/// Хранить историю по дням было бы честнее, но приложение не ведёт дневник:
/// счёт нужен, чтобы к вечеру видеть, сколько сделано, и утром начать с чистого.
///
/// Считаются только доведённые до конца помидоры. Сброшенный не считается —
/// прервали, значит потеряли целиком (см. ADR-0003); просроченный во сне тоже
/// не считается — он отменяется молча (см. ADR-0002).
/// День календаря: число, а не момент. Момент начала суток зависит от часового
/// пояса, и перелёт через пояс среди дня стирал бы уже накопленный счёт.
public struct Day: Equatable {

    /// Год, месяц и число одним числом: 3 сентября 2026 — это 20260903. В таком
    /// виде день ложится в `UserDefaults` и сравнивается без календаря.
    public let stamp: Int

    /// Дня ещё не было.
    public static let none = Day(stamp: 0)

    public init(stamp: Int) {
        self.stamp = stamp
    }

    public init(of moment: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        stamp = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}

public struct DailyTally: Equatable {

    /// День, к которому относится счёт.
    public private(set) var day: Day
    /// Число за этот день без оглядки на то, какой день сейчас. Наружу нужно
    /// только для сохранения; читать счёт следует через `sessions(at:)`.
    public private(set) var storedSessions: Int

    /// Пустой счёт: никакого дня ещё не было.
    public init() {
        day = .none
        storedSessions = 0
    }

    /// Восстановление после перезапуска.
    public init(day: Day, sessions: Int) {
        self.day = day
        self.storedSessions = max(0, sessions)
    }

    /// Помидор дошёл до конца.
    public mutating func record(at now: Date, calendar: Calendar = .current) {
        let today = Day(of: now, calendar: calendar)
        if today == day {
            storedSessions += 1
        } else {
            day = today
            storedSessions = 1
        }
    }

    /// Сколько закрыто в тот день, которому принадлежит `now`. Другой день —
    /// ноль: полночь обнуляет счёт сама, отдельного будильника для этого нет.
    public func sessions(at now: Date, calendar: Calendar = .current) -> Int {
        Day(of: now, calendar: calendar) == day ? storedSessions : 0
    }
}

/// Подпись счёта в меню. Помидор в интерфейсе называется сессией — расхождение
/// с кодом описано в `CONTEXT.md`.
public enum TallyLabel {

    /// `nil` — подписи нет: «Сегодня 0 сессий» это упрёк, а не сведения.
    public static func text(for sessions: Int) -> String? {
        guard sessions > 0 else { return nil }
        return "Сегодня \(sessions) \(noun(for: sessions))"
    }

    private static func noun(for count: Int) -> String {
        // Второй десяток склоняется не как остальные: одиннадцать сессий, но
        // двадцать одна сессия.
        if (11...14).contains(count % 100) { return "сессий" }
        switch count % 10 {
        case 1: return "сессия"
        case 2, 3, 4: return "сессии"
        default: return "сессий"
        }
    }
}
