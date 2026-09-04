import Foundation
import ClepsydraCore

/// Точка отсчёта для всех сценариев — конкретная дата, чтобы прогон не зависел
/// от того, когда его запускают.
let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func after(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// Автомат, доведённый до экрана после помидора обычным путём — без чёрного
/// хода к внутреннему состоянию.
func machineAwaitingBreak() -> TimerMachine {
    var machine = TimerMachine()
    _ = machine.start(at: t0)
    _ = machine.advance(to: after(25 * 60))
    return machine
}

/// Перерыв идёт: финиш на 30-й минуте от t0.
func machineOnBreak() -> TimerMachine {
    var machine = machineAwaitingBreak()
    _ = machine.takeBreak(at: after(25 * 60))
    return machine
}

/// Экран после перерыва.
func machineAwaitingPomodoro() -> TimerMachine {
    var machine = machineOnBreak()
    _ = machine.advance(to: after(30 * 60))
    return machine
}

let t = Runner()

// MARK: Обычный круг

t.test("Начинаем в простое") {
    let machine = TimerMachine()
    t.expect(machine.phase, .idle)
    t.expect(machine.remaining(at: t0), nil)
}

t.test("Старт ставит финиш на 25 минут вперёд") {
    var machine = TimerMachine()
    let effects = machine.start(at: t0)

    t.expect(machine.phase, .pomodoro(until: after(25 * 60)))
    t.expect(effects, [])
    t.expect(machine.remaining(at: after(60)), 24 * 60)
}

t.test("Помидор дошёл до нуля — просим отдохнуть") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.advance(to: after(25 * 60 - 1)), [], "за секунду до конца ничего не происходит")
    t.expect(machine.advance(to: after(25 * 60)), [.pomodoroFinished])
    t.expect(machine.phase, .awaitingBreak)
    t.expect(machine.remaining(at: after(25 * 60)), nil, "на экране с цитатой отсчёта нет")
}

t.test("Второй раз не звеним") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)
    _ = machine.advance(to: after(25 * 60))

    t.expect(machine.advance(to: after(25 * 60 + 1)), [])
}

t.test("«Отдохнуть» запускает пять минут, не убирая экран") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)
    _ = machine.advance(to: after(25 * 60))

    let effects = machine.takeBreak(at: after(25 * 60 + 4))

    t.expect(effects, [], "экран остаётся на весь перерыв и показывает отсчёт")
    t.expect(machine.phase, .onBreak(until: after(25 * 60 + 4 + 5 * 60)))
}

t.test("Перерыв дошёл до нуля — предлагаем следующий помидор") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)
    _ = machine.advance(to: after(25 * 60))
    _ = machine.takeBreak(at: after(25 * 60))

    t.expect(machine.advance(to: after(30 * 60)), [.breakFinished])
    t.expect(machine.phase, .awaitingPomodoro)
}

t.test("Круг замыкается: «Начать» с экрана после перерыва") {
    var machine = machineAwaitingPomodoro()

    let effects = machine.start(at: t0)

    t.expect(effects, [.dismissOverlay], "экран убираем — помидор уже пошёл")
    t.expect(machine.phase, .pomodoro(until: after(25 * 60)))
}

// MARK: Выходы из круга

t.test("«Хватит» выводит из круга") {
    var machine = machineAwaitingPomodoro()

    t.expect(machine.stop(), [.dismissOverlay])
    t.expect(machine.phase, .idle)
}

t.test("После помидора «Хватит» нет") {
    var machine = machineAwaitingBreak()

    t.expect(machine.stop(), [], "у экрана после помидора одна кнопка — «Отдохнуть»")
    t.expect(machine.phase, .awaitingBreak)
}

t.test("Сброс отменяет идущий помидор") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.reset(), [])
    t.expect(machine.phase, .idle)
}

t.test("Сброс отменяет и идущий перерыв") {
    var machine = machineOnBreak()

    t.expect(machine.reset(), [])
    t.expect(machine.phase, .idle)
}

t.test("⌘⇧0 уводит в простой с экрана после помидора") {
    var machine = machineAwaitingBreak()

    t.expect(machine.escape(), [.dismissOverlay])
    t.expect(machine.phase, .idle)
}

t.test("⌘⇧0 уводит в простой и с экрана после перерыва") {
    var machine = machineAwaitingPomodoro()

    t.expect(machine.escape(), [.dismissOverlay])
    t.expect(machine.phase, .idle)
}

t.test("⌘⇧0 без экрана ничего не делает") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.escape(), [], "идущий помидор комбинацией не отменяют — для этого «Сбросить»")
    t.expect(machine.phase, .pomodoro(until: after(25 * 60)))
}

// MARK: Сон

t.test("Просроченный во сне помидор отменяется молча") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    // Закрыл крышку на третьей минуте, открыл через час.
    let effects = machine.advance(to: after(63 * 60))

    t.expect(effects, [], "цитату через час после закрытия крышки показывать нелепо")
    t.expect(machine.phase, .idle)
}

t.test("Просроченный во сне перерыв отменяется молча") {
    var machine = machineOnBreak()

    t.expect(machine.advance(to: after(120 * 60)), [])
    t.expect(machine.phase, .idle)
}

t.test("Опоздавший тик в пределах допуска — это не сон") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    // Система подтормозила, тик пришёл на 20 секунд позже.
    t.expect(machine.advance(to: after(25 * 60 + 20)), [.pomodoroFinished])
    t.expect(machine.phase, .awaitingBreak)
}

t.test("Экран переживает сон") {
    var machine = machineAwaitingBreak()

    t.expect(machine.advance(to: after(10 * 60 * 60)), [], "окно висит, сколько бы ни прошло")
    t.expect(machine.phase, .awaitingBreak)
}

// MARK: Запрещённые переходы

t.test("Повторный старт не сдвигает финиш") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.start(at: after(60)), [])
    t.expect(machine.phase, .pomodoro(until: after(25 * 60)))
}

t.test("«Отдохнуть» вне экрана ничего не делает") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.takeBreak(at: after(60)), [])
    t.expect(machine.phase, .pomodoro(until: after(25 * 60)))
}

t.test("Под экраном сброса нет") {
    var machine = machineAwaitingBreak()

    t.expect(machine.reset(), [], "до меню-бара из-под экрана всё равно не дотянуться")
    t.expect(machine.phase, .awaitingBreak)
}

t.test("Остаток не уходит в минус") {
    var machine = TimerMachine()
    _ = machine.start(at: t0)

    t.expect(machine.remaining(at: after(26 * 60)), 0)
}

// MARK: Отсчёт в меню-баре

t.test("Округляем вверх — первая секунда показывает полную длительность") {
    t.expect(Countdown.text(for: 25 * 60), "25:00")
    t.expect(Countdown.text(for: 25 * 60 - 0.4), "25:00")
}

t.test("Ширина отсчёта всегда пять знаков") {
    t.expect(Countdown.text(for: 4 * 60 + 12), "04:12")
    t.expect(Countdown.text(for: 59), "00:59")
    t.expect(Countdown.text(for: 0), "00:00")
}

t.test("Отрицательный остаток прижимаем к нулю") {
    t.expect(Countdown.text(for: -5), "00:00")
}

// MARK: Цитаты

t.test("Цитат ровно 50, и все с автором") {
    t.expect(Quotes.all.count, 50)
    t.expect(Quotes.all.contains { $0.text.isEmpty || $0.author.isEmpty }, false)
}

t.test("Цитаты не повторяются в списке") {
    t.expect(Set(Quotes.all.map(\.text)).count, Quotes.all.count)
}

t.test("Следующая цитата никогда не равна предыдущей") {
    var previous = Quotes.all[0]
    for _ in 0..<500 {
        let next = Quotes.next(after: previous)
        t.expect(next == previous, false)
        previous = next
    }
}

t.test("У каждого автора есть имя файла с портретом") {
    let authors = Set(Quotes.all.map(\.author))
    let unmapped = authors.filter { Quotes.portraitName(for: $0) == nil }.sorted()
    t.expect(unmapped, [], "иначе портрет молча не найдётся")
    t.expect(Set(Quotes.portraits.keys), authors, "лишние записи так же вредны, как недостающие")
}

t.test("Имена файлов не повторяются") {
    t.expect(Set(Quotes.portraits.values).count, Quotes.portraits.count)
}

// MARK: Режим Стетхема

t.test("Семнадцать реплик, все разбиты на строки") {
    t.expect(StathamQuotes.all.count, 17)
    t.expect(StathamQuotes.all.contains { $0.lines.isEmpty }, false)
    t.expect(StathamQuotes.all.contains { $0.lines.contains(where: \.isEmpty) }, false)
}

t.test("Реплики не повторяются в списке") {
    t.expect(Set(StathamQuotes.all.map { $0.lines.joined(separator: " ") }).count, StathamQuotes.all.count)
}

t.test("Строка помещается в плашку") {
    // Больше тридцати знаков — плашка перестаёт влезать в отведённые 56% экрана.
    let tooLong = StathamQuotes.all.flatMap(\.lines).filter { $0.count > 30 }
    t.expect(tooLong, [])
}

t.test("Следующая реплика никогда не равна предыдущей") {
    var previous = StathamQuotes.all[0]
    for _ in 0..<500 {
        let next = StathamQuotes.next(after: previous)
        t.expect(next == previous, false)
        previous = next
    }
}

// MARK: История по дням

/// Календарь с фиксированным поясом: иначе прогон зависел бы от того, где стоит
/// машина, и полночь в тестах приходила бы в разное время.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Полдень 14 ноября 2023 года по UTC и соседние с ним моменты — так видно,
/// что переход считается по суткам, а не по «прошло 24 часа».
let noon = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-10 * 3600 - 13 * 60 - 20)

/// Следующее утро: то же время суток, но уже за полночью.
let nextMorning = noon.addingTimeInterval(21 * 3600)

t.test("Новая история пуста") {
    let history = History()
    t.expect(history.sessions(at: noon, calendar: utc), 0)
    t.expect(history.stored.isEmpty, true)
}

t.test("Закрытый помидор увеличивает счёт") {
    var history = History()
    history.record(at: noon, calendar: utc)

    t.expect(history.sessions(at: noon, calendar: utc), 1)
}

t.test("Помидоры за один день складываются") {
    var history = History()
    history.record(at: noon, calendar: utc)
    history.record(at: noon.addingTimeInterval(30 * 60), calendar: utc)
    history.record(at: noon.addingTimeInterval(60 * 60), calendar: utc)

    t.expect(history.sessions(at: noon.addingTimeInterval(60 * 60), calendar: utc), 3)
}

t.test("Новый день считается с единицы") {
    var history = History()
    history.record(at: noon, calendar: utc)

    t.expect(history.sessions(at: nextMorning, calendar: utc), 0, "вчерашнее число сегодня не показываем")

    history.record(at: nextMorning, calendar: utc)
    t.expect(history.sessions(at: nextMorning, calendar: utc), 1, "новый день считается с единицы")
}

t.test("Вчерашний день полночь не стирает") {
    var history = History()
    history.record(at: noon, calendar: utc)
    history.record(at: nextMorning, calendar: utc)

    t.expect(history.sessions(on: Day(of: noon, calendar: utc)), 1, "вчера осталось в истории")
    t.expect(history.sessions(on: Day(of: nextMorning, calendar: utc)), 1, "сегодня считается отдельно")
}

t.test("День без помидоров в истории не появляется") {
    var history = History()
    history.record(at: noon, calendar: utc)

    // Между этими днями сутки, в которые не закрыто ничего.
    history.record(at: noon.addingTimeInterval(48 * 3600), calendar: utc)

    t.expect(history.stored.count, 2, "пустые сутки в хранилище не попадают")
}

t.test("Ночной помидор до полуночи достаётся вчерашнему дню") {
    var history = History()
    let beforeMidnight = noon.addingTimeInterval(11 * 3600 + 59 * 60)
    history.record(at: beforeMidnight, calendar: utc)

    t.expect(history.sessions(at: beforeMidnight, calendar: utc), 1)
    t.expect(history.sessions(at: beforeMidnight.addingTimeInterval(120), calendar: utc), 0)
}

t.test("История переживает перезапуск") {
    var history = History()
    history.record(at: noon, calendar: utc)
    history.record(at: noon, calendar: utc)
    history.record(at: nextMorning, calendar: utc)

    let restored = History(stored: history.stored)
    t.expect(restored, history, "хранимый вид восстанавливается без потерь")
    t.expect(restored.sessions(at: noon, calendar: utc), 2)
    t.expect(restored.sessions(at: nextMorning, calendar: utc), 1)
}

t.test("Испорченное хранилище не роняет историю") {
    let history = History(stored: ["20231114": 2, "позавчера": 3, "20231115": 0, "0": 4, "20231116": "три"])

    t.expect(history.stored as NSDictionary, ["20231114": 2] as NSDictionary,
             "в историю попадают только дни с помидорами")
}

t.test("Прежний счёт переезжает в историю") {
    // Прежнее хранение помнило один день: число дня и счёт.
    let history = History(day: Day(stamp: 20231114), sessions: 3)

    t.expect(history.sessions(at: noon, calendar: utc), 3, "сегодняшний счёт не теряется")
    t.expect(history.stored.count, 1)
}

t.test("Переезжать нечему, когда прежнего счёта не было") {
    t.expect(History(day: .none, sessions: 0), History())
    t.expect(History(day: Day(stamp: 20231114), sessions: 0), History(), "день без помидоров не запись")
}

t.test("Смена часового пояса счёт не стирает") {
    var moscow = Calendar(identifier: .gregorian)
    moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
    var london = Calendar(identifier: .gregorian)
    london.timeZone = TimeZone(identifier: "Europe/London")!

    // Полдень в Москве и в Лондоне — один и тот же день календаря, хотя сутки
    // там начались в разные моменты.
    var history = History()
    history.record(at: noon, calendar: moscow)
    history.record(at: noon.addingTimeInterval(60), calendar: london)

    t.expect(history.sessions(at: noon, calendar: london), 2, "перелёт среди дня — не новый день")
    t.expect(history.stored.count, 1, "второй записи за тот же день не появилось")
}

t.test("День — число календаря, а не момент") {
    var moscow = Calendar(identifier: .gregorian)
    moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!

    t.expect(Day(of: noon, calendar: utc).stamp, 20231114)
    t.expect(Day(of: noon, calendar: moscow).stamp, 20231114)
    t.expect(Day.none.stamp, 0, "дня ещё не было")
}

t.test("Подписи склоняются по-русски") {
    t.expect(TallyLabel.today(sessions: 1), "Сегодня 1 сессия")
    t.expect(TallyLabel.today(sessions: 2), "Сегодня 2 сессии")
    t.expect(TallyLabel.today(sessions: 4), "Сегодня 4 сессии")
    t.expect(TallyLabel.today(sessions: 5), "Сегодня 5 сессий")
    t.expect(TallyLabel.today(sessions: 11), "Сегодня 11 сессий", "одиннадцать — не одна")
    t.expect(TallyLabel.today(sessions: 14), "Сегодня 14 сессий")
    t.expect(TallyLabel.today(sessions: 21), "Сегодня 21 сессия")
    t.expect(TallyLabel.today(sessions: 22), "Сегодня 22 сессии")
    t.expect(TallyLabel.today(sessions: 25), "Сегодня 25 сессий")
    t.expect(TallyLabel.today(sessions: 101), "Сегодня 101 сессия")
}

t.test("Пустой день подписи не получает") {
    t.expect(TallyLabel.today(sessions: 0), nil, "«0 сессий» — упрёк, а не сведения")
}

// MARK: Последние дни

/// Дни подряд: 12, 13 и 14 ноября 2023 года.
let twelfth = Day(stamp: 20231112)
let thirteenth = Day(stamp: 20231113)
let fourteenth = Day(stamp: 20231114)

/// История, в которой за каждый перечисленный день закрыто столько помидоров,
/// сколько сказано.
func historyOf(days: [Day: Int]) -> History {
    var stored: [String: Any] = [:]
    for (day, sessions) in days { stored[String(day.stamp)] = sessions }
    return History(stored: stored)
}

t.test("Последние дни идут свежими сверху") {
    let history = historyOf(days: [twelfth: 1, thirteenth: 5, fourteenth: 2])

    t.expect(history.recent(before: Day(stamp: 20231115), limit: 7), [
        DayTally(day: fourteenth, sessions: 2),
        DayTally(day: thirteenth, sessions: 5),
        DayTally(day: twelfth, sessions: 1)
    ])
}

t.test("Сегодня в список не попадает") {
    let history = historyOf(days: [thirteenth: 5, fourteenth: 2])

    t.expect(history.recent(before: fourteenth, limit: 7),
             [DayTally(day: thirteenth, sessions: 5)],
             "сегодня уже написано строкой выше")
}

t.test("Пока прошедших дней нет, список пуст") {
    t.expect(History().recent(before: fourteenth, limit: 7), [])
    t.expect(historyOf(days: [fourteenth: 3]).recent(before: fourteenth, limit: 7), [],
             "один сегодняшний день — это ещё не история")
    t.expect(historyOf(days: [twelfth: 1]).recent(before: fourteenth, limit: 0), [],
             "нулевой предел — пустой список, а не падение")
}

t.test("Длина списка ограничена при любом объёме хранилища") {
    var days: [Day: Int] = [:]
    for number in 1...28 { days[Day(stamp: 20231100 + number)] = number }
    let history = historyOf(days: days)

    let recent = history.recent(before: Day(stamp: 20231129), limit: 7)
    t.expect(recent.count, 7, "меню обязано помещаться на экран")
    t.expect(recent.first, DayTally(day: Day(stamp: 20231128), sessions: 28), "и это самые свежие дни")
    t.expect(recent.last, DayTally(day: Day(stamp: 20231122), sessions: 22))
}

t.test("Дни считаются по календарю, а не по расстоянию до сегодня") {
    // Между записями разрыв в год: в списке они всё равно соседние.
    let history = historyOf(days: [Day(stamp: 20221231): 1, Day(stamp: 20230101): 2])

    t.expect(history.recent(before: fourteenth, limit: 7), [
        DayTally(day: Day(stamp: 20230101), sessions: 2),
        DayTally(day: Day(stamp: 20221231), sessions: 1)
    ])
}

t.test("Строка прошедшего дня — дата и счёт") {
    t.expect(TallyLabel.past(DayTally(day: twelfth, sessions: 5), relativeTo: fourteenth),
             "12 ноября — 5 сессий")
    t.expect(TallyLabel.past(DayTally(day: Day(stamp: 20230902), sessions: 5), relativeTo: Day(stamp: 20230903)),
             "2 сентября — 5 сессий")
}

t.test("Сессии в подменю склоняются так же, как в строке про сегодня") {
    func label(_ sessions: Int) -> String? {
        TallyLabel.past(DayTally(day: twelfth, sessions: sessions), relativeTo: fourteenth)
    }
    t.expect(label(1), "12 ноября — 1 сессия")
    t.expect(label(2), "12 ноября — 2 сессии")
    t.expect(label(5), "12 ноября — 5 сессий")
    t.expect(label(11), "12 ноября — 11 сессий", "одиннадцать — не одна")
    t.expect(label(21), "12 ноября — 21 сессия")
    t.expect(label(22), "12 ноября — 22 сессии")
}

t.test("Все двенадцать месяцев названы по-русски") {
    let named: [String?] = (1...12).map {
        TallyLabel.past(DayTally(day: Day(stamp: 20230000 + $0 * 100 + 1), sessions: 1), relativeTo: Day(stamp: 20231114))
    }
    t.expect(named, [
        "1 января — 1 сессия", "1 февраля — 1 сессия", "1 марта — 1 сессия",
        "1 апреля — 1 сессия", "1 мая — 1 сессия", "1 июня — 1 сессия",
        "1 июля — 1 сессия", "1 августа — 1 сессия", "1 сентября — 1 сессия",
        "1 октября — 1 сессия", "1 ноября — 1 сессия", "1 декабря — 1 сессия"
    ])
}

t.test("Чужой год дописывается, свой — нет") {
    let tally = DayTally(day: Day(stamp: 20211231), sessions: 3)

    t.expect(TallyLabel.past(tally, relativeTo: Day(stamp: 20230105)), "31 декабря 2021 — 3 сессии",
             "без года это был бы обман")
    t.expect(TallyLabel.past(tally, relativeTo: Day(stamp: 20211231)), "31 декабря — 3 сессии")
}

t.test("День, который не дата, назвать нельзя") {
    // Ключи в хранилище правит человек и портит случай: «14 месяца 99» между
    // настоящими днями хуже, чем пропущенная строка.
    t.expect(TallyLabel.past(DayTally(day: Day(stamp: 20239914), sessions: 1), relativeTo: fourteenth), nil)
    t.expect(TallyLabel.past(DayTally(day: Day(stamp: 20231100), sessions: 1), relativeTo: fourteenth), nil)
    t.expect(TallyLabel.past(DayTally(day: .none, sessions: 1), relativeTo: fourteenth), nil,
             "дня ещё не было")
}

t.test("Дни сравниваются как даты") {
    t.expect(twelfth < thirteenth, true)
    t.expect(Day(stamp: 20221231) < Day(stamp: 20230101), true, "новый год — не откат назад")
    t.expect(fourteenth < fourteenth, false)
}

checkBuildNumber(t)
checkDmgName(t)
checkReleaseTag(t)
checkReleaseGate(t)
checkReleaseNotes(t)
checkOriginRepo(t)
checkBundlePictures(t)
checkReadme(t)
checkUpdates(t)
checkUpdateFeed(t)

t.finish()
