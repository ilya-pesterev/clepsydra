import Foundation
import ClepsydraCore

/// Время в истории: как оно записывается, как переживает перезапуск, чего нет у
/// дней из прежних версий и что из всего этого складывается в итог над списком.
func checkHistoryTime(_ t: Runner) {

    // MARK: Помидор записывает свою длину

    t.test("Закрытый помидор записывает время") {
        var history = History()
        history.record(length: 25 * 60, at: noon, calendar: utc)

        t.expect(history.tally(at: noon, calendar: utc),
                 DayTally(day: Day(of: noon, calendar: utc), sessions: 1, seconds: 25 * 60))
    }

    t.test("Помидоры за день складываются и штуками, и временем") {
        var history = History()
        history.record(length: 25 * 60, at: noon, calendar: utc)
        history.record(length: 45 * 60, at: noon.addingTimeInterval(60 * 60), calendar: utc)

        let day = history.tally(at: noon, calendar: utc)
        t.expect(day?.sessions, 2)
        t.expect(day?.seconds, 70 * 60, "длины разные — время у дня общее")
    }

    t.test("Новый день начинает время заново") {
        var history = History()
        history.record(length: 45 * 60, at: noon, calendar: utc)
        history.record(length: 15 * 60, at: nextMorning, calendar: utc)

        t.expect(history.tally(at: noon, calendar: utc)?.seconds, 45 * 60)
        t.expect(history.tally(at: nextMorning, calendar: utc)?.seconds, 15 * 60)
    }

    t.test("Дня без помидоров в истории нет") {
        t.expect(History().tally(at: noon, calendar: utc), nil, "спрашивать нечего")
    }

    /// История, в которую сложили всё, что автомат насчитал, — так же, как это
    /// делает `AppDelegate` с эффектами.
    func recorded(_ effects: [Effect]) -> History {
        var history = History()
        for case .pomodoroFinished(let length) in effects {
            history.record(length: length, at: noon, calendar: utc)
        }
        return history
    }

    t.test("Сброшенный помидор ни счёта, ни времени не добавляет") {
        var machine = TimerMachine()
        _ = machine.start(at: t0)

        t.expect(recorded(machine.reset()), History(), "прервали — потеряли целиком")
    }

    t.test("Просроченный во сне помидор ни счёта, ни времени не добавляет") {
        var machine = TimerMachine()
        _ = machine.start(at: t0)

        // Закрыл крышку на третьей минуте, открыл через час.
        t.expect(recorded(machine.advance(to: after(63 * 60))), History())
    }

    t.test("Законченный помидор доносит до истории свою длину") {
        var machine = TimerMachine(durations: Durations(pomodoro: 45 * 60, breakInterval: 5 * 60))
        _ = machine.start(at: t0)

        let history = recorded(machine.advance(to: after(45 * 60)))
        t.expect(history.tally(at: noon, calendar: utc)?.seconds, 45 * 60)
    }

    // MARK: Дни из прежних версий

    t.test("День из прежней версии показывает счёт и молчит про время") {
        // Прежнее хранение помнило одно число на день — счёт.
        let history = History(stored: ["20231114": 3])

        t.expect(history.tally(at: noon, calendar: utc),
                 DayTally(day: Day(stamp: 20231114), sessions: 3, seconds: nil),
                 "какой длины были те помидоры, никто не знает")
    }

    t.test("Времени у старого дня не появляется задним числом") {
        // Обновились посреди дня: три помидора этого дня записаны без длины, и
        // время всего дня остаётся неизвестным. Иначе день из четырёх сессий
        // объявил бы себя двадцатипятиминутным.
        var history = History(stored: ["20231114": 3])
        history.record(length: 25 * 60, at: noon, calendar: utc)

        let day = history.tally(at: noon, calendar: utc)
        t.expect(day?.sessions, 4, "счёт растёт как раньше")
        t.expect(day?.seconds, nil, "время дня известно только целиком")
    }

    t.test("Переезд с прежнего хранения времени не выдумывает") {
        let history = History(day: Day(stamp: 20231114), sessions: 3)

        t.expect(history.tally(at: noon, calendar: utc)?.seconds, nil)
        t.expect(history.tally(at: noon, calendar: utc)?.sessions, 3, "счёт не теряется")
    }

    // MARK: Хранилище

    t.test("Время переживает перезапуск") {
        var history = History()
        history.record(length: 25 * 60, at: noon, calendar: utc)
        history.record(length: 45 * 60, at: noon, calendar: utc)
        history.record(length: 15 * 60, at: nextMorning, calendar: utc)

        t.expect(History(stored: history.stored), history,
                 "хранимый вид восстанавливается без потерь")
    }

    t.test("День без времени хранится по-прежнему — одним числом") {
        // Читать это придётся и прежним версиям, и следующим: день, у которого
        // времени нет, в хранилище выглядит ровно так, как выглядел всегда.
        let history = History(stored: ["20231114": 3])

        t.expect(history.stored as NSDictionary, ["20231114": 3] as NSDictionary)
    }

    t.test("Испорченное время не отнимает у дня счёт") {
        // Величины проверяются порознь, как длины в `Durations`.
        func seconds(_ value: Any) -> TimeInterval? {
            History(stored: ["20231114": ["sessions": 2, "seconds": value]])
                .tally(on: Day(stamp: 20231114))?.seconds
        }
        func sessions(_ value: Any) -> Int? {
            History(stored: ["20231114": ["sessions": 2, "seconds": value]])
                .tally(on: Day(stamp: 20231114))?.sessions
        }

        t.expect(sessions("много"), 2, "день со счётом остаётся днём со счётом")
        t.expect(seconds("много"), nil)
        t.expect(seconds(-60), nil)
        t.expect(seconds(0), nil)
        // Помидор длится от минуты до двух часов (ADR-0011), поэтому у двух
        // помидоров время лежит между двумя минутами и четырьмя часами.
        t.expect(seconds(60), nil, "минута на два помидора короче самого короткого")
        t.expect(seconds(5 * 3600), nil, "пять часов на два помидора длиннее самого длинного")
        t.expect(seconds(2 * 60), 2 * 60, "две минуты — два помидора по минуте")
        t.expect(seconds(4 * 3600), 4 * 3600)
    }

    t.test("Целое число секунд так же законно, как дробное") {
        // Приложение пишет секунды дробью, а `defaults write -int 3000` — целым.
        t.expect(History(stored: ["20231114": ["sessions": 2, "seconds": 3000]])
            .tally(on: Day(stamp: 20231114))?.seconds, 3000)
    }

    t.test("Испорченный счёт роняет день целиком") {
        t.expect(History(stored: ["20231114": ["seconds": 3000]]), History(),
                 "время без счёта — не день")
        t.expect(History(stored: ["20231114": ["sessions": 0, "seconds": 3000]]), History())
    }

    t.test("День, чьё число не похоже на дату, в список не попадает") {
        // Ключи в хранилище правит человек и портит случай. День, который
        // нельзя назвать, нельзя и сложить в итог: иначе «всего» разошлось бы с
        // видимыми строками.
        let history = History(stored: ["20239914": 2, "20231100": 3, "20231114": 1])

        t.expect(history.days, [DayTally(day: Day(stamp: 20231114), sessions: 1, seconds: nil)])
        t.expect(history.summary?.sessions, 1, "в итог складываются те же дни, что и в список")
    }

    t.test("Но из хранилища такой день не пропадает") {
        // Выбросить его на чтении значило бы стереть его первой же записью —
        // а он, может быть, ещё будет починен руками.
        let history = History(stored: ["20239914": 2, "20231114": 1])

        t.expect(history.stored as NSDictionary, ["20239914": 2, "20231114": 1] as NSDictionary)
    }

    // MARK: Строка дня

    t.test("Строка дня показывает счёт и время") {
        t.expect(TallyLabel.day(DayTally(day: Day(stamp: 20230902), sessions: 5, seconds: 125 * 60),
                                relativeTo: Day(stamp: 20230903)),
                 "2 сентября — 5 сессий, 2 часа 5 минут")
    }

    t.test("День без времени показывает один счёт") {
        t.expect(TallyLabel.day(DayTally(day: Day(stamp: 20230902), sessions: 5, seconds: nil),
                                relativeTo: Day(stamp: 20230903)),
                 "2 сентября — 5 сессий",
                 "ни нуля, ни выдумки")
    }

    // MARK: Часы и минуты

    t.test("Час без минут пишется часом") {
        t.expect(TimeLabel.text(for: 2 * 3600), "2 часа")
        t.expect(TimeLabel.text(for: 3600), "1 час")
    }

    t.test("Меньше часа — одни минуты") {
        t.expect(TimeLabel.text(for: 45 * 60), "45 минут")
        t.expect(TimeLabel.text(for: 60), "1 минута")
    }

    t.test("Часы и минуты склоняются") {
        t.expect(TimeLabel.text(for: 3600 + 60), "1 час 1 минута")
        t.expect(TimeLabel.text(for: 2 * 3600 + 2 * 60), "2 часа 2 минуты")
        t.expect(TimeLabel.text(for: 5 * 3600 + 5 * 60), "5 часов 5 минут")
        t.expect(TimeLabel.text(for: 11 * 3600 + 11 * 60), "11 часов 11 минут",
                 "одиннадцать — не один")
        t.expect(TimeLabel.text(for: 21 * 3600 + 21 * 60), "21 час 21 минута")
        t.expect(TimeLabel.text(for: 22 * 3600 + 22 * 60), "22 часа 22 минуты")
    }

    t.test("Время округляется до минуты, а пустое время не называется") {
        t.expect(TimeLabel.text(for: 25 * 60 + 20), "25 минут")
        t.expect(TimeLabel.text(for: 0), nil)
        t.expect(TimeLabel.text(for: -60), nil)
        t.expect(TimeLabel.text(for: 20), nil, "меньше половины минуты — не время")
    }

    // MARK: Итог

    /// История из трёх дней подряд: 12, 13 и 14 ноября.
    func threeDays() -> History {
        History(stored: [
            "20231112": ["sessions": 2, "seconds": 50 * 60],
            "20231113": ["sessions": 5, "seconds": 125 * 60],
            "20231114": ["sessions": 2, "seconds": 50 * 60]
        ])
    }

    t.test("Пустая история итога не получает") {
        t.expect(History().summary, nil, "подводить нечего")
    }

    t.test("Итог складывает сессии и время") {
        let summary = threeDays().summary

        t.expect(summary?.sessions, 9)
        t.expect(summary?.seconds, 225 * 60)
        t.expect(summary?.days, 3)
    }

    t.test("Среднее делится на дни с записями, а не на календарные сутки") {
        // Между 12 и 14 ноября есть 13-е, но отпуск между записями делить не на
        // что: дни без единого помидора записи не получают (ADR-0006).
        let history = History(stored: ["20231112": 2, "20231114": 4])

        t.expect(history.summary?.days, 2)
        t.expect(history.summary?.averageSessions, 3)
    }

    t.test("Самый полный день — с наибольшим счётом") {
        t.expect(threeDays().summary?.fullest,
                 DayTally(day: Day(stamp: 20231113), sessions: 5, seconds: 125 * 60))
    }

    t.test("При равном счёте самый полный день — тот, что был раньше") {
        // Рекорд держит тот, кто поставил его первым.
        let history = History(stored: ["20231112": 4, "20231114": 4])

        t.expect(history.summary?.fullest.day, Day(stamp: 20231112))
    }

    t.test("Наблюдения идут с самого раннего дня") {
        t.expect(threeDays().summary?.first, Day(stamp: 20231112))
    }

    t.test("Итог считает время по дням, которые его помнят") {
        let history = History(stored: [
            "20231112": 3,
            "20231114": ["sessions": 2, "seconds": 50 * 60]
        ])

        t.expect(history.summary?.sessions, 5, "счёт — по всем дням")
        t.expect(history.summary?.seconds, 50 * 60, "время — только по дню, который его помнит")
        t.expect(history.summary?.timeIsPartial, true)
    }

    t.test("Когда времени не помнит ни один день, итог о нём молчит") {
        let history = History(stored: ["20231112": 3, "20231114": 2])

        t.expect(history.summary?.seconds, nil)
        t.expect(history.summary?.timeIsPartial, false, "оговаривать нечего: времени в итоге нет")
    }

    t.test("Когда время помнят все дни, оговорки нет") {
        t.expect(threeDays().summary?.timeIsPartial, false)
    }

    // MARK: Подписи итога

    /// Итог истории, названный словами, — так его читают в окне.
    func lines(_ history: History, today: Day = Day(stamp: 20231114)) -> [String] {
        guard let summary = history.summary else { return [] }
        return SummaryLabel.lines(summary, relativeTo: today)
    }

    t.test("Итог называет всё, что подвёл") {
        t.expect(lines(threeDays()), [
            "Всего 9 сессий, 3 часа 45 минут",
            "В среднем 3 сессии в день",
            "Самый полный день — 13 ноября, 5 сессий",
            "Наблюдения с 12 ноября"
        ])
    }

    t.test("Дробное среднее пишется дробью и склоняется по ней") {
        // 11 сессий за 3 дня — 3,7 в день; при дробном числе существительное
        // стоит в родительном: «3,7 сессии», а не «3,7 сессий».
        let history = History(stored: ["20231112": 2, "20231113": 5, "20231114": 4])

        t.expect(lines(history)[1], "В среднем 3,7 сессии в день")
    }

    t.test("Итог оговаривает время, если помнят его не все дни") {
        let history = History(stored: [
            "20231112": 3,
            "20231114": ["sessions": 2, "seconds": 50 * 60]
        ])

        t.expect(lines(history), [
            "Всего 5 сессий, 50 минут",
            "В среднем 2,5 сессии в день",
            "Самый полный день — 12 ноября, 3 сессии",
            "Наблюдения с 12 ноября",
            "Время — по дням, которые его помнят"
        ])
    }

    t.test("Без времени итог о нём не заговаривает") {
        let history = History(stored: ["20231112": 3, "20231114": 2])

        t.expect(lines(history), [
            "Всего 5 сессий",
            "В среднем 2,5 сессии в день",
            "Самый полный день — 12 ноября, 3 сессии",
            "Наблюдения с 12 ноября"
        ])
    }

    t.test("Одному дню итог не пересказывает его же строку") {
        // Среднее, самый полный и первый день — это один и тот же день, и он
        // уже написан строкой ниже.
        let history = History(stored: ["20231114": ["sessions": 2, "seconds": 50 * 60]])

        t.expect(lines(history), ["Всего 2 сессии, 50 минут"])
    }

    t.test("Чужой год в итоге дописывается") {
        let history = History(stored: ["20211231": 1, "20230105": 2])

        t.expect(lines(history, today: Day(stamp: 20230105))[3], "Наблюдения с 31 декабря 2021")
    }

    t.test("Сессии в итоге склоняются") {
        func total(_ sessions: Int) -> String {
            lines(History(stored: ["20231114": sessions]))[0]
        }
        t.expect(total(1), "Всего 1 сессия")
        t.expect(total(2), "Всего 2 сессии")
        t.expect(total(5), "Всего 5 сессий")
        t.expect(total(11), "Всего 11 сессий", "одиннадцать — не одна")
        t.expect(total(21), "Всего 21 сессия")
    }
}
