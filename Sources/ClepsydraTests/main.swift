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

// MARK: Счёт за день

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

t.test("Новый счёт пуст") {
    let tally = DailyTally()
    t.expect(tally.sessions(at: noon, calendar: utc), 0)
}

t.test("Закрытый помидор увеличивает счёт") {
    var tally = DailyTally()
    tally.record(at: noon, calendar: utc)

    t.expect(tally.sessions(at: noon, calendar: utc), 1)
}

t.test("Помидоры за один день складываются") {
    var tally = DailyTally()
    tally.record(at: noon, calendar: utc)
    tally.record(at: noon.addingTimeInterval(30 * 60), calendar: utc)
    tally.record(at: noon.addingTimeInterval(60 * 60), calendar: utc)

    t.expect(tally.sessions(at: noon.addingTimeInterval(60 * 60), calendar: utc), 3)
}

t.test("В полночь счёт начинается заново") {
    var tally = DailyTally()
    tally.record(at: noon, calendar: utc)

    let nextMorning = noon.addingTimeInterval(21 * 3600)
    t.expect(tally.sessions(at: nextMorning, calendar: utc), 0, "вчерашнее число сегодня не показываем")

    tally.record(at: nextMorning, calendar: utc)
    t.expect(tally.sessions(at: nextMorning, calendar: utc), 1, "новый день считается с единицы")
}

t.test("Ночной помидор до полуночи достаётся вчерашнему дню") {
    var tally = DailyTally()
    let beforeMidnight = noon.addingTimeInterval(11 * 3600 + 59 * 60)
    tally.record(at: beforeMidnight, calendar: utc)

    t.expect(tally.sessions(at: beforeMidnight, calendar: utc), 1)
    t.expect(tally.sessions(at: beforeMidnight.addingTimeInterval(120), calendar: utc), 0)
}

t.test("Счёт переживает перезапуск") {
    var tally = DailyTally()
    tally.record(at: noon, calendar: utc)
    tally.record(at: noon, calendar: utc)

    let restored = DailyTally(day: Day(stamp: tally.day.stamp), sessions: tally.storedSessions)
    t.expect(restored.sessions(at: noon, calendar: utc), 2)
}

t.test("Смена часового пояса счёт не стирает") {
    var moscow = Calendar(identifier: .gregorian)
    moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
    var london = Calendar(identifier: .gregorian)
    london.timeZone = TimeZone(identifier: "Europe/London")!

    // Полдень в Москве и в Лондоне — один и тот же день календаря, хотя сутки
    // там начались в разные моменты.
    var tally = DailyTally()
    tally.record(at: noon, calendar: moscow)

    t.expect(tally.sessions(at: noon, calendar: london), 1, "перелёт среди дня — не новый день")
}

t.test("День — число календаря, а не момент") {
    var moscow = Calendar(identifier: .gregorian)
    moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!

    t.expect(Day(of: noon, calendar: utc).stamp, 20231114)
    t.expect(Day(of: noon, calendar: moscow).stamp, 20231114)
    t.expect(Day.none.stamp, 0, "дня ещё не было")
}

t.test("Подписи склоняются по-русски") {
    t.expect(TallyLabel.text(for: 1), "Сегодня 1 сессия")
    t.expect(TallyLabel.text(for: 2), "Сегодня 2 сессии")
    t.expect(TallyLabel.text(for: 4), "Сегодня 4 сессии")
    t.expect(TallyLabel.text(for: 5), "Сегодня 5 сессий")
    t.expect(TallyLabel.text(for: 11), "Сегодня 11 сессий", "одиннадцать — не одна")
    t.expect(TallyLabel.text(for: 14), "Сегодня 14 сессий")
    t.expect(TallyLabel.text(for: 21), "Сегодня 21 сессия")
    t.expect(TallyLabel.text(for: 22), "Сегодня 22 сессии")
    t.expect(TallyLabel.text(for: 25), "Сегодня 25 сессий")
    t.expect(TallyLabel.text(for: 101), "Сегодня 101 сессия")
}

t.test("Пустой день подписи не получает") {
    t.expect(TallyLabel.text(for: 0), nil, "«0 сессий» — упрёк, а не сведения")
}

t.finish()
