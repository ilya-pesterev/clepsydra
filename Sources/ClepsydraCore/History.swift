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
    /// спрашиваем прежде, чем день записать в историю.
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

    /// Сколько времени заняли эти помидоры. `nil` — день времени не помнит: он
    /// пришёл из версии, которая длин не записывала, и придумать их задним
    /// числом нельзя.
    public let seconds: TimeInterval?

    public init(day: Day, sessions: Int, seconds: TimeInterval? = nil) {
        self.day = day
        self.sessions = sessions
        self.seconds = seconds
    }
}

/// Итог над списком дней в окне «История»: чем обернулись все накопленные дни
/// вместе. Считается по тем же дням, что и показаны списком.
public struct Summary: Equatable {

    /// Всего помидоров за всю историю.
    public let sessions: Int

    /// Сколько дней с записями. Дни без единого помидора записи не получают
    /// (ADR-0006), поэтому это не длина промежутка от первого дня до сегодня.
    public let days: Int

    /// Всего времени — по дням, которые его помнят. `nil` — не помнит ни один.
    public let seconds: TimeInterval?

    /// В истории есть и дни со временем, и дни без него: тогда `seconds`
    /// покрывает не всё, и итог обязан это оговорить.
    public let timeIsPartial: Bool

    /// День с наибольшим счётом. При равном счёте — тот, что был раньше:
    /// рекорд держит тот, кто поставил его первым.
    public let fullest: DayTally

    /// Самый ранний день с записью — с него идут наблюдения.
    public let first: Day

    /// Сколько помидоров в день в среднем. Делится на дни с записями, а не на
    /// календарные сутки: делить на отпуск — значит за него наказывать.
    public var averageSessions: Double { Double(sessions) / Double(days) }
}

/// Сколько помидоров закрыто в каждый из дней и сколько времени они заняли.
/// Полночь ничего не стирает: вчерашнее число остаётся в истории, а счёт за
/// сегодня начинается с нуля просто потому, что записи за сегодня ещё нет.
///
/// Глубина не ограничена — см. ADR-0006. День без единого закрытого помидора
/// записи не получает: счёт появляется по факту, а не заводится на каждые сутки.
///
/// Считаются только доведённые до конца помидоры. Сброшенный не считается —
/// прервали, значит потеряли целиком (см. ADR-0003); просроченный во сне тоже
/// не считается — он отменяется молча (см. ADR-0002). Те же правила у времени:
/// оно приходит из того же места и той же дорогой.
public struct History: Equatable {

    private static let sessionsKey = "sessions"
    private static let secondsKey = "seconds"

    private var tallies: [Day: DayTally]

    /// Пустая история: ни одного закрытого помидора.
    public init() {
        tallies = [:]
    }

    /// Восстановление после перезапуска. Ключ — день числом; значение — либо
    /// счёт числом, как писали прежние версии, либо словарь со счётом и
    /// временем. Значения приходят из `UserDefaults`, поэтому тип у них `Any`,
    /// и правило «день со счётом» проверяется здесь — единственном месте,
    /// которое знает, как история выглядит в хранилище.
    ///
    /// Всё, что под правило не подходит, пропускается: испорченная запись не
    /// повод терять остальные дни.
    public init(stored: [String: Any]) {
        tallies = [:]
        for (key, value) in stored {
            guard let stamp = Int(key) else { continue }
            let day = Day(stamp: stamp)
            guard let tally = Self.tally(of: day, stored: value) else { continue }
            tallies[day] = tally
        }
    }

    /// Переезд с прежнего хранения, где помнился ровно один день. Правило
    /// «день со счётом» то же самое, поэтому и вход тот же. Времени у такого
    /// дня нет и не появится: длин прежние версии не записывали.
    public init(day: Day, sessions: Int) {
        self.init(stored: [String(day.stamp): sessions])
    }

    /// Как день выглядит в хранилище. Счёт и время проверяются порознь, как
    /// длины в `Durations`: испорченное время не повод терять счёт за день.
    private static func tally(of day: Day, stored value: Any) -> DayTally? {
        // Прежнее хранение: одно число на день. Так же пишется и день, который
        // времени не помнит, — иначе оно завелось бы у него само собой.
        if let sessions = value as? Int {
            guard sessions > 0 else { return nil }
            return DayTally(day: day, sessions: sessions, seconds: nil)
        }
        guard let fields = value as? [String: Any],
              let sessions = fields[sessionsKey] as? Int, sessions > 0 else { return nil }
        let seconds = sane(fields[secondsKey], of: sessions)
        return DayTally(day: day, sessions: sessions, seconds: seconds)
    }

    /// Разумно ли время дня. Помидор длится от минуты до двух часов (ADR-0011),
    /// а время дня — сумма его помидоров: столько же, умноженное на счёт.
    ///
    /// Целое число тут так же законно, как дробное: приложение пишет секунды
    /// дробью, а `defaults write -int 3000` — целым.
    private static func sane(_ value: Any?, of sessions: Int) -> TimeInterval? {
        let seconds = (value as? TimeInterval) ?? (value as? Int).map(TimeInterval.init)
        guard let seconds else { return nil }
        let shortest = Durations.sanePomodoro.lowerBound * Double(sessions)
        let longest = Durations.sanePomodoro.upperBound * Double(sessions)
        guard (shortest...longest).contains(seconds) else { return nil }
        return seconds
    }

    /// Вид для хранения: словарь, который принимает `UserDefaults`.
    public var stored: [String: Any] {
        var result: [String: Any] = [:]
        for (day, tally) in tallies {
            guard let seconds = tally.seconds else {
                result[String(day.stamp)] = tally.sessions
                continue
            }
            result[String(day.stamp)] = [Self.sessionsKey: tally.sessions, Self.secondsKey: seconds]
        }
        return result
    }

    /// Помидор дошёл до конца — засчитываем его и его длину.
    ///
    /// **День, который времени не помнит, помнить его не начинает.** Обновились
    /// посреди дня — у дня уже есть помидоры без длины, и сумма покрывала бы не
    /// все: день из четырёх сессий объявил бы себя двадцатипятиминутным. Время
    /// дня известно целиком или неизвестно вовсе.
    public mutating func record(length: TimeInterval, at now: Date, calendar: Calendar = .current) {
        let day = Day(of: now, calendar: calendar)
        guard let known = tallies[day] else {
            tallies[day] = DayTally(day: day, sessions: 1, seconds: length)
            return
        }
        tallies[day] = DayTally(
            day: day,
            sessions: known.sessions + 1,
            seconds: known.seconds.map { $0 + length }
        )
    }

    /// Сколько закрыто в тот день, которому принадлежит `now`.
    public func sessions(at now: Date, calendar: Calendar = .current) -> Int {
        sessions(on: Day(of: now, calendar: calendar))
    }

    /// Сколько закрыто в этот день. День без записи — ноль.
    public func sessions(on day: Day) -> Int {
        tallies[day]?.sessions ?? 0
    }

    /// Запись за тот день, которому принадлежит `now`. `nil` — записи нет.
    public func tally(at now: Date, calendar: Calendar = .current) -> DayTally? {
        tally(on: Day(of: now, calendar: calendar))
    }

    /// Запись за этот день. `nil` — в этот день не закрыто ничего.
    public func tally(on day: Day) -> DayTally? {
        tallies[day]
    }

    /// Все дни со счётом, свежие сверху — включая сегодня: в окне оно строка
    /// наравне с прошедшими днями, а не повтор строки из меню.
    ///
    /// Предела нет: окно листается и не обязано помещаться, поэтому глубину
    /// показа больше не режет размер меню (ADR-0012).
    ///
    /// День, чьё число не похоже на дату, сюда не попадает: назвать его нельзя,
    /// а безымянный день ни в списке не покажешь, ни в итог не сложишь. В
    /// хранилище он при этом остаётся — выбрасывать на чтении значило бы стереть
    /// его при первой же записи, а он, может быть, ещё будет починен руками.
    public var days: [DayTally] {
        tallies.values.filter(\.day.looksLikeDate).sorted { $0.day > $1.day }
    }

    /// Итог над списком. `nil` — истории нет, и подводить нечего.
    public var summary: Summary? {
        let days = self.days
        guard var fullest = days.first, let earliest = days.last else { return nil }
        for tally in days where tally.sessions > fullest.sessions
            || (tally.sessions == fullest.sessions && tally.day < fullest.day) {
            fullest = tally
        }

        let timed = days.compactMap(\.seconds)
        return Summary(
            sessions: days.reduce(0) { $0 + $1.sessions },
            days: days.count,
            seconds: timed.isEmpty ? nil : timed.reduce(0, +),
            timeIsPartial: !timed.isEmpty && timed.count < days.count,
            fullest: fullest,
            // Дни идут свежими сверху, поэтому первый день наблюдений — последний.
            first: earliest.day
        )
    }
}
