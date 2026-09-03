import Foundation

/// День календаря: число, а не момент. Момент начала суток зависит от часового
/// пояса, и перелёт через пояс среди дня стирал бы уже накопленный счёт.
public struct Day: Hashable {

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

/// Сколько помидоров закрыто в каждый из дней. Полночь ничего не стирает:
/// вчерашнее число остаётся в истории, а счёт за сегодня начинается с нуля
/// просто потому, что записи за сегодня ещё нет.
///
/// Глубина не ограничена — см. ADR-0006. День без единого закрытого помидора
/// записи не получает: счёт появляется по факту, а не заводится на каждые сутки.
///
/// Считаются только доведённые до конца помидоры. Сброшенный не считается —
/// прервали, значит потеряли целиком (см. ADR-0003); просроченный во сне тоже
/// не считается — он отменяется молча (см. ADR-0002).
public struct History: Equatable {

    private var counts: [Day: Int]

    /// Пустая история: ни одного закрытого помидора.
    public init() {
        counts = [:]
    }

    /// Восстановление после перезапуска: ключ — день числом, значение — счёт.
    /// Значения приходят из `UserDefaults`, поэтому тип у них `Any`, и правило
    /// «день со счётом» проверяется здесь — единственном месте, которое знает,
    /// как история выглядит в хранилище. Всё, что под правило не подходит,
    /// пропускается: испорченная запись не повод терять остальные дни.
    public init(stored: [String: Any]) {
        counts = [:]
        for (key, value) in stored {
            guard let stamp = Int(key), stamp > 0,
                  let sessions = value as? Int, sessions > 0 else { continue }
            counts[Day(stamp: stamp)] = sessions
        }
    }

    /// Переезд с прежнего хранения, где помнился ровно один день. Правило
    /// «день со счётом» то же самое, поэтому и вход тот же.
    public init(day: Day, sessions: Int) {
        self.init(stored: [String(day.stamp): sessions])
    }

    /// Вид для хранения: словарь, который принимает `UserDefaults`.
    public var stored: [String: Int] {
        var result: [String: Int] = [:]
        for (day, sessions) in counts {
            result[String(day.stamp)] = sessions
        }
        return result
    }

    /// Помидор дошёл до конца.
    public mutating func record(at now: Date, calendar: Calendar = .current) {
        counts[Day(of: now, calendar: calendar), default: 0] += 1
    }

    /// Сколько закрыто в тот день, которому принадлежит `now`.
    public func sessions(at now: Date, calendar: Calendar = .current) -> Int {
        sessions(on: Day(of: now, calendar: calendar))
    }

    /// Сколько закрыто в этот день. День без записи — ноль.
    public func sessions(on day: Day) -> Int {
        counts[day] ?? 0
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
