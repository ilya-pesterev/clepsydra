import Foundation

/// День календаря: число, а не момент. Момент начала суток зависит от часового
/// пояса, и перелёт через пояс среди дня стирал бы уже накопленный счёт.
public struct Day: Hashable, Comparable {

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

    public var year: Int { stamp / 10_000 }
    public var month: Int { (stamp / 100) % 100 }
    public var dayOfMonth: Int { stamp % 100 }

    /// Похоже ли число на день календаря. Хранилище правит человек и портит
    /// случай, а назвать месяц словом можно только у настоящей даты — поэтому
    /// спрашиваем перед тем, как день произнести.
    public var looksLikeDate: Bool {
        year > 0 && (1...12).contains(month) && (1...31).contains(dayOfMonth)
    }

    /// Порядок дней — порядок чисел: год, месяц и число сложены так, что
    /// сравнение чисел совпадает со сравнением дат.
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.stamp < rhs.stamp }
}

/// Счёт за один день: то, из чего состоит история и её строки в окне.
public struct DayTally: Equatable {

    public let day: Day
    public let sessions: Int

    public init(day: Day, sessions: Int) {
        self.day = day
        self.sessions = sessions
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

    /// Все дни со счётом, свежие сверху — включая сегодня: в окне оно строка
    /// наравне с прошедшими днями, а не повтор строки из меню.
    ///
    /// Предела нет: окно листается и не обязано помещаться, поэтому глубину
    /// показа больше не режет размер меню (ADR-0012).
    public var days: [DayTally] {
        counts
            .sorted { $0.key > $1.key }
            .map { DayTally(day: $0.key, sessions: $0.value) }
    }
}

/// Подписи счёта: строка про сегодня в меню и строки дней в окне «История».
/// Помидор в интерфейсе называется сессией — расхождение с кодом описано в
/// `CONTEXT.md`.
public enum TallyLabel {

    /// Строка про сегодня. `nil` — подписи нет: «Сегодня 0 сессий» это упрёк,
    /// а не сведения.
    public static func today(sessions: Int) -> String? {
        guard sessions > 0 else { return nil }
        return "Сегодня \(sessions) \(noun(for: sessions))"
    }

    /// Строка вместо пустого списка. Пустое окно человек читает как поломку, а
    /// «0 сессий» — как упрёк (ADR-0005); поэтому здесь сказано, как оно
    /// устроено, и не сказано, сколько он сделал.
    public static let empty = "Здесь появятся дни с законченными сессиями"

    /// Строка дня в окне: «2 сентября — 5 сессий». Одна и та же и для сегодня,
    /// и для прошедших дней — в окне они наравне. Склонение то же, что и в
    /// строке про сегодня.
    ///
    /// `nil` — дня назвать нельзя: число из хранилища не похоже на дату. Такую
    /// строку показ пропускает, счёт молча выпадает из списка. Уж лучше так,
    /// чем «14 месяца 99» между настоящими днями.
    public static func day(_ tally: DayTally, relativeTo today: Day) -> String? {
        guard let date = date(of: tally.day, relativeTo: today) else { return nil }
        return "\(date) — \(tally.sessions) \(noun(for: tally.sessions))"
    }

    /// Год дописывается только чужой: в пределах текущего года он лишний шум,
    /// а вот «5 сессий 2 сентября» позапрошлого года без года — обман.
    private static func date(of day: Day, relativeTo today: Day) -> String? {
        guard day.looksLikeDate else { return nil }
        let name = months[day.month - 1]
        guard day.year != today.year else { return "\(day.dayOfMonth) \(name)" }
        return "\(day.dayOfMonth) \(name) \(day.year)"
    }

    /// Месяцы в родительном падеже: день читается как «2 сентября», а не как
    /// строка из таблицы.
    private static let months = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ]

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
