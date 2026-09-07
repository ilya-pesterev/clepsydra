import Foundation

// Как история называется словами: строка про сегодня в меню, строки дней в
// окне и итог над ними. Отдельно от `History`: та знает, что хранится и как
// складывается, а здесь — русская грамматика и порядок слов.

/// Склонение при числе: одна сессия, две сессии, пять сессий. Правило одно на
/// всё приложение — его спрашивают и счёт, и часы, и минуты в подменю
/// «Длительность».
enum Plural {

    static func of(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        // Второй десяток склоняется не как остальные: одиннадцать сессий, но
        // двадцать одна сессия.
        if (11...14).contains(count % 100) { return many }
        switch count % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}

/// Накопленное время словами: «2 часа 5 минут». Не `DurationLabel` — тот
/// называет длину, которую выбирают в меню, и меряет её минутами, потому что
/// выбирают минуты. Здесь время не выбирают, а копят, и часов в нём больше,
/// чем минут.
public enum TimeLabel {

    /// `nil` — времени нет: ни «0 минут», ни «меньше минуты».
    public static func text(for seconds: TimeInterval) -> String? {
        let total = Int((seconds / 60).rounded())
        guard total > 0 else { return nil }

        let hours = total / 60
        let minutes = total % 60
        let hoursText = "\(hours) \(Plural.of(hours, "час", "часа", "часов"))"
        let minutesText = "\(minutes) \(Plural.of(minutes, "минута", "минуты", "минут"))"

        if hours == 0 { return minutesText }
        // Час без минут пишется часом, а не «2 часа 0 минут».
        if minutes == 0 { return hoursText }
        return "\(hoursText) \(minutesText)"
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
        return "Сегодня \(sessionsText(sessions))"
    }

    /// Строка вместо пустого списка. Пустое окно человек читает как поломку, а
    /// «0 сессий» — как упрёк (ADR-0005); поэтому здесь сказано, как оно
    /// устроено, и не сказано, сколько он сделал.
    public static let empty = "Здесь появятся дни с законченными сессиями"

    /// Строка дня в окне: «2 сентября — 5 сессий, 2 часа 5 минут». Одна и та же
    /// и для сегодня, и для прошедших дней — в окне они наравне.
    ///
    /// День, времени не помнящий, показывает один счёт: ни нуля, ни выдумки.
    ///
    /// `nil` — дня назвать нельзя: число из хранилища не похоже на дату. Такие
    /// дни отсеивает `History.days`, но подпись проверяет и сама: «14 месяца 99»
    /// между настоящими днями хуже, чем пропущенная строка.
    public static func day(_ tally: DayTally, relativeTo today: Day) -> String? {
        guard tally.day.looksLikeDate else { return nil }
        let sessions = sessionsText(tally.sessions)
        let date = dateText(of: tally.day, relativeTo: today)
        guard let seconds = tally.seconds, let time = TimeLabel.text(for: seconds) else {
            return "\(date) — \(sessions)"
        }
        return "\(date) — \(sessions), \(time)"
    }

    /// Год дописывается только чужой: в пределах текущего года он лишний шум,
    /// а вот «5 сессий 2 сентября» позапрошлого года без года — обман.
    ///
    /// Спрашивается у дня, который назвать можно: непохожие на дату отсеяны
    /// раньше, в `History.days`.
    fileprivate static func dateText(of day: Day, relativeTo today: Day) -> String {
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

    /// Слово, которым в интерфейсе называется помидор, — во всех трёх формах.
    private static let sessions = (one: "сессия", few: "сессии", many: "сессий")

    /// Дробное число ставит слово в ту же форму, что и «две»: «3,7 сессии».
    fileprivate static let sessionsAfterFraction = sessions.few

    fileprivate static func sessionsText(_ count: Int) -> String {
        "\(count) \(Plural.of(count, sessions.one, sessions.few, sessions.many))"
    }
}

/// Подписи итога — строки над списком в окне «История».
public enum SummaryLabel {

    public static func lines(_ summary: Summary, relativeTo today: Day) -> [String] {
        var lines = [total(summary)]

        // Одному дню пересказывать нечего: среднее, самый полный и первый день
        // — это он сам, и он уже написан строкой ниже.
        guard summary.days > 1 else { return lines }

        lines.append("В среднем \(average(summary.averageSessions)) в день")

        let fullest = TallyLabel.dateText(of: summary.fullest.day, relativeTo: today)
        let sessions = TallyLabel.sessionsText(summary.fullest.sessions)
        lines.append("Самый полный день — \(fullest), \(sessions)")
        lines.append("Наблюдения с \(TallyLabel.dateText(of: summary.first, relativeTo: today))")

        // Время сложено не по всем дням — про это надо сказать, иначе итог
        // выдаёт часть за целое.
        if summary.timeIsPartial {
            lines.append("Время — по дням, которые его помнят")
        }
        return lines
    }

    private static func total(_ summary: Summary) -> String {
        let sessions = "Всего \(TallyLabel.sessionsText(summary.sessions))"
        guard let seconds = summary.seconds,
              let time = TimeLabel.text(for: seconds) else { return sessions }
        return "\(sessions), \(time)"
    }

    /// Среднее — с одним знаком после запятой: округлённое до целого, оно
    /// путало бы день из полутора сессий с днём из двух.
    private static func average(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let whole = tenths / 10
        guard tenths % 10 != 0 else { return TallyLabel.sessionsText(whole) }
        return "\(whole),\(tenths % 10) \(TallyLabel.sessionsAfterFraction)"
    }
}
