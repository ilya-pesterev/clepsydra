import Foundation

/// Длительности v1 — зашиты, настроек нет.
public enum Durations {
    /// Помидор — 25 минут работы.
    public static let pomodoro: TimeInterval = 25 * 60
    /// Перерыв — 5 минут.
    public static let breakInterval: TimeInterval = 5 * 60

    /// Насколько поздно может прийти тик, чтобы это всё ещё считалось нормальной
    /// работой таймера. Всё, что позже, — Mac спал: срок вышел без нас, и
    /// показывать цитату «пора отдохнуть» уже нелепо.
    public static let overdueGrace: TimeInterval = 60
}

/// Где мы в круге. Помидор и перерыв держат не остаток, а дату финиша: пока
/// Mac спит, счётчик тикать перестаёт, а дата остаётся верной.
public enum Phase: Equatable {
    case idle
    case pomodoro(until: Date)
    /// Помидор кончился, на экране цитата и кнопка «Отдохнуть».
    case awaitingBreak
    case onBreak(until: Date)
    /// Перерыв кончился, на экране цитата и кнопки «Начать» и «Хватит».
    case awaitingPomodoro
}

/// Что должно произойти снаружи автомата: звук, окно, всё остальное — не его дело.
public enum Effect: Equatable {
    case pomodoroFinished
    case breakFinished
    case dismissOverlay
}

/// Круг «помидор → перерыв → помидор». Чистый тип: ни окон, ни таймеров, ни
/// системного времени внутри — момент всегда приходит снаружи параметром.
public struct TimerMachine {

    public private(set) var phase: Phase

    public init() {
        phase = .idle
    }

    // MARK: Действия человека

    /// «Начать помидор» в меню или «Начать» на экране после перерыва.
    public mutating func start(at now: Date) -> [Effect] {
        switch phase {
        case .idle:
            phase = .pomodoro(until: now + Durations.pomodoro)
            return []
        case .awaitingPomodoro:
            phase = .pomodoro(until: now + Durations.pomodoro)
            return [.dismissOverlay]
        case .pomodoro, .awaitingBreak, .onBreak:
            return []
        }
    }

    /// «Отдохнуть» на экране после помидора.
    public mutating func takeBreak(at now: Date) -> [Effect] {
        guard case .awaitingBreak = phase else { return [] }
        phase = .onBreak(until: now + Durations.breakInterval)
        return [.dismissOverlay]
    }

    /// «Хватит» на экране после перерыва — выход из круга.
    public mutating func stop() -> [Effect] {
        guard case .awaitingPomodoro = phase else { return [] }
        phase = .idle
        return [.dismissOverlay]
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
        case .pomodoro(let until):
            guard now >= until else { return [] }
            guard now.timeIntervalSince(until) <= Durations.overdueGrace else {
                phase = .idle
                return []
            }
            phase = .awaitingBreak
            return [.pomodoroFinished]

        case .onBreak(let until):
            guard now >= until else { return [] }
            guard now.timeIntervalSince(until) <= Durations.overdueGrace else {
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
        case .pomodoro(let until), .onBreak(let until):
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
