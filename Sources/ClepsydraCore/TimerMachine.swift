import Foundation

/// Длина помидора и длина перерыва — пара, которую выбирают в меню и которая
/// переживает перезапуск. Одна на всё приложение: разных длин у разных кругов
/// не бывает.
public struct Durations: Equatable {

    /// Помидор — сколько работы.
    public let pomodoro: TimeInterval
    /// Перерыв — сколько отдыха после помидора.
    public let breakInterval: TimeInterval

    /// Ничего не выбирали: 25 и 5 минут, длины v1.
    public static let standard = Durations(pomodoro: 25 * 60, breakInterval: 5 * 60)

    /// Из чего выбирают помидор в меню. Три строки, а не ползунок: см. ADR-0011.
    public static let pomodoroChoices: [TimeInterval] = [15 * 60, 25 * 60, 45 * 60]
    /// Из чего выбирают перерыв.
    public static let breakChoices: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60]

    /// Пределы разумного. Ими проверяется хранилище, а не меню: в меню строки
    /// заведомо разумные, а `defaults write` правит человек и портит случай.
    /// Помидор в ноль секунд звенел бы без остановки.
    ///
    /// Пределы помидора спрашивает и `History`: время дня — сумма его
    /// помидоров, и разумно оно ровно настолько же.
    public static let sanePomodoro: ClosedRange<TimeInterval> = 60...(120 * 60)
    private static let saneBreak: ClosedRange<TimeInterval> = 60...(60 * 60)

    private static let pomodoroKey = "pomodoro"
    private static let breakKey = "break"

    public init(pomodoro: TimeInterval, breakInterval: TimeInterval) {
        self.pomodoro = pomodoro
        self.breakInterval = breakInterval
    }

    /// Восстановление после перезапуска. Значения приходят из `UserDefaults`,
    /// поэтому тип у них `Any`, и разумность проверяется здесь — в единственном
    /// месте, которое знает, как выбор выглядит в хранилище.
    ///
    /// Длины проверяются порознь: испорченный перерыв не повод возвращать к
    /// прежним 25 минутам выбранный помидор.
    public init(stored: [String: Any]) {
        pomodoro = Self.sane(stored[Self.pomodoroKey], within: Self.sanePomodoro)
            ?? Self.standard.pomodoro
        breakInterval = Self.sane(stored[Self.breakKey], within: Self.saneBreak)
            ?? Self.standard.breakInterval
    }

    /// Вид для хранения: словарь, который принимает `UserDefaults`.
    public var stored: [String: TimeInterval] {
        [Self.pomodoroKey: pomodoro, Self.breakKey: breakInterval]
    }

    /// Целое число тут так же законно, как дробное: приложение пишет секунды
    /// дробью, а `defaults write -int 2700` — целым, и второе не повод считать
    /// запись испорченной.
    private static func sane(_ value: Any?, within limits: ClosedRange<TimeInterval>) -> TimeInterval? {
        let length = (value as? TimeInterval) ?? (value as? Int).map(TimeInterval.init)
        guard let length, limits.contains(length) else { return nil }
        return length
    }
}

/// Как длина называется в меню. Минуты, а не «25:00»: там выбирают, а не считают.
///
/// Склоняется по-настоящему, хотя все шесть предложенных длин попадают в одну
/// форму — «минут». Длину правят и мимо меню (см. ADR-0011), а туда попадает
/// и минута, и полторы: подпись должна называть и их.
public enum DurationLabel {

    public static func minutes(_ interval: TimeInterval) -> String {
        // Округляем вверх: полторы минуты — «2 минуты», ноль минут не название.
        let count = max(1, Int(ceil(interval / 60)))
        return "\(count) \(Plural.of(count, "минута", "минуты", "минут"))"
    }
}

/// Где мы в круге. Помидор и перерыв держат не остаток, а дату финиша: пока
/// Mac спит, счётчик тикать перестаёт, а дата остаётся верной.
public enum Phase: Equatable {
    case idle
    /// Помидор держит и длину, а не только дату финиша: длину записывает в
    /// историю финиш, а к тому времени выбранная в меню может быть уже другой —
    /// смена длины идущий интервал не трогает.
    case pomodoro(until: Date, length: TimeInterval)
    /// Помидор кончился, на экране цитата и кнопка «Отдохнуть».
    case awaitingBreak
    case onBreak(until: Date)
    /// Перерыв кончился, на экране цитата и кнопки «Начать» и «Хватит».
    case awaitingPomodoro
}

/// Что должно произойти снаружи автомата: звук, окно, всё остальное — не его дело.
public enum Effect: Equatable {
    /// Длина закончившегося помидора — то, что запишет в историю день.
    case pomodoroFinished(length: TimeInterval)
    case breakFinished
    case dismissOverlay
}

/// Круг «помидор → перерыв → помидор». Чистый тип: ни окон, ни таймеров, ни
/// системного времени внутри — момент всегда приходит снаружи параметром.
public struct TimerMachine {

    /// Насколько поздно может прийти тик, чтобы это всё ещё считалось нормальной
    /// работой таймера. Всё, что позже, — Mac спал: срок вышел без нас, и
    /// показывать цитату «пора отдохнуть» уже нелепо.
    ///
    /// Живёт у автомата, а не у `Durations`: это не третья длина, которую
    /// выбирают, а мерка, которой автомат отличает сон от подтормозившей
    /// системы. От выбранной длины она не зависит — вопрос тут не «долго ли шёл
    /// интервал», а «жив ли был Mac последнюю минуту».
    public static let overdueGrace: TimeInterval = 60

    public private(set) var phase: Phase

    /// Выбранные длины. Меняются на ходу — прямо из меню, посреди помидора.
    /// Идущий интервал от этого не сдвигается: он держит дату финиша, а она
    /// уже назначена. Новая длина работает со следующего интервала.
    public var durations: Durations

    public init(durations: Durations = .standard) {
        phase = .idle
        self.durations = durations
    }

    // MARK: Действия человека

    /// «Начать помидор» в меню или «Начать» на экране после перерыва.
    public mutating func start(at now: Date) -> [Effect] {
        switch phase {
        case .idle:
            phase = .pomodoro(until: now + durations.pomodoro, length: durations.pomodoro)
            return []
        case .awaitingPomodoro:
            phase = .pomodoro(until: now + durations.pomodoro, length: durations.pomodoro)
            return [.dismissOverlay]
        case .pomodoro, .awaitingBreak, .onBreak:
            return []
        }
    }

    /// «Отдохнуть» на экране после помидора. Экран не убираем: он остаётся на
    /// весь перерыв и показывает отсчёт вместо кнопки.
    public mutating func takeBreak(at now: Date) -> [Effect] {
        guard case .awaitingBreak = phase else { return [] }
        phase = .onBreak(until: now + durations.breakInterval)
        return []
    }

    /// «Хватит» на экране после перерыва — выход из круга.
    public mutating func stop() -> [Effect] {
        guard case .awaitingPomodoro = phase else { return [] }
        phase = .idle
        return [.dismissOverlay]
    }

    /// Аварийный выход с экрана по ⌘⇧0. В отличие от кнопок, работает из любой
    /// фазы с экраном и всегда возвращает в простой: это запасной выход, а не
    /// часть круга.
    public mutating func escape() -> [Effect] {
        switch phase {
        case .awaitingBreak, .awaitingPomodoro:
            phase = .idle
            return [.dismissOverlay]
        case .idle, .pomodoro, .onBreak:
            return []
        }
    }

    /// «Сбросить» в меню. Из-под полноэкранного экрана до меню не дотянуться,
    /// поэтому там сброс невозможен по построению.
    public mutating func reset() -> [Effect] {
        switch phase {
        case .pomodoro, .onBreak:
            phase = .idle
            return []
        case .idle, .awaitingBreak, .awaitingPomodoro:
            return []
        }
    }

    // MARK: Ход времени

    /// Тик раз в секунду и пробуждение из сна — одно и то же событие: обе ветки
    /// сводятся к вопросу «сколько времени прошло с даты финиша».
    public mutating func advance(to now: Date) -> [Effect] {
        switch phase {
        case .pomodoro(let until, let length):
            guard now >= until else { return [] }
            guard now.timeIntervalSince(until) <= Self.overdueGrace else {
                phase = .idle
                return []
            }
            phase = .awaitingBreak
            return [.pomodoroFinished(length: length)]

        case .onBreak(let until):
            guard now >= until else { return [] }
            guard now.timeIntervalSince(until) <= Self.overdueGrace else {
                phase = .idle
                return []
            }
            phase = .awaitingPomodoro
            return [.breakFinished]

        case .idle, .awaitingBreak, .awaitingPomodoro:
            return []
        }
    }

    /// Сколько осталось до финиша. `nil` — отсчёта сейчас нет.
    public func remaining(at now: Date) -> TimeInterval? {
        switch phase {
        case .pomodoro(let until, _), .onBreak(let until):
            return max(0, until.timeIntervalSince(now))
        case .idle, .awaitingBreak, .awaitingPomodoro:
            return nil
        }
    }
}

/// Отсчёт в меню-баре. Ширина всегда пять знаков, чтобы `09:59` → `10:00`
/// не дёргало соседние иконки.
public enum Countdown {
    public static func text(for remaining: TimeInterval) -> String {
        let seconds = Int(ceil(max(0, remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
