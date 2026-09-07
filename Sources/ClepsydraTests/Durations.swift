import Foundation
import ClepsydraCore

/// Длительности: выбор, хранение и то, что смена не трогает идущий интервал.
func checkDurations(_ t: Runner) {

    // MARK: Что предлагается выбрать

    t.test("По умолчанию — 25 и 5 минут") {
        t.expect(Durations.standard.pomodoro, 25 * 60)
        t.expect(Durations.standard.breakInterval, 5 * 60)
        t.expect(TimerMachine().durations, .standard, "не выбирали — работают прежние длины")
    }

    t.test("Выбор идёт от короткого к длинному и без повторов") {
        t.expect(Durations.pomodoroChoices, Durations.pomodoroChoices.sorted())
        t.expect(Durations.breakChoices, Durations.breakChoices.sorted())
        t.expect(Set(Durations.pomodoroChoices).count, Durations.pomodoroChoices.count)
        t.expect(Set(Durations.breakChoices).count, Durations.breakChoices.count)
    }

    t.test("Прежние длины остались среди предложенных") {
        // Иначе у того, кто ничего не выбирал, в меню не было бы галочки.
        t.expect(Durations.pomodoroChoices.contains(Durations.standard.pomodoro), true)
        t.expect(Durations.breakChoices.contains(Durations.standard.breakInterval), true)
    }

    t.test("Все предложенные длины проходят проверку хранилища") {
        for length in Durations.pomodoroChoices {
            t.expect(Durations(stored: ["pomodoro": length]).pomodoro, length)
        }
        for length in Durations.breakChoices {
            t.expect(Durations(stored: ["break": length]).breakInterval, length)
        }
    }

    // MARK: Автомат считает по выбранной длине

    t.test("Помидор идёт столько, сколько выбрали") {
        var machine = TimerMachine(durations: Durations(pomodoro: 45 * 60, breakInterval: 15 * 60))
        _ = machine.start(at: t0)

        t.expect(machine.phase, .pomodoro(until: after(45 * 60), length: 45 * 60))
        t.expect(machine.advance(to: after(25 * 60)), [], "прежние 25 минут больше ничего не значат")
        t.expect(machine.advance(to: after(45 * 60)), [.pomodoroFinished(length: 45 * 60)])
    }

    t.test("Перерыв идёт столько, сколько выбрали") {
        var machine = TimerMachine(durations: Durations(pomodoro: 45 * 60, breakInterval: 15 * 60))
        _ = machine.start(at: t0)
        _ = machine.advance(to: after(45 * 60))
        _ = machine.takeBreak(at: after(45 * 60))

        t.expect(machine.phase, .onBreak(until: after(60 * 60)))
        t.expect(machine.advance(to: after(60 * 60)), [.breakFinished])
    }

    t.test("Допуск на сон не зависит от выбранной длины") {
        var machine = TimerMachine(durations: Durations(pomodoro: 15 * 60, breakInterval: 5 * 60))
        _ = machine.start(at: t0)

        t.expect(machine.advance(to: after(15 * 60 + 20)), [.pomodoroFinished(length: 15 * 60)],
                 "подтормозивший тик — не сон")

        var slept = TimerMachine(durations: Durations(pomodoro: 15 * 60, breakInterval: 5 * 60))
        _ = slept.start(at: t0)
        t.expect(slept.advance(to: after(15 * 60 + 61)), [], "просроченный во сне отменяется молча")
        t.expect(slept.phase, .idle)
    }

    // MARK: Смена на ходу

    t.test("Смена длительности не сдвигает идущий помидор") {
        var machine = TimerMachine()
        _ = machine.start(at: t0)

        machine.durations = Durations(pomodoro: 45 * 60, breakInterval: 5 * 60)

        t.expect(machine.phase, .pomodoro(until: after(25 * 60), length: 25 * 60),
                 "финиш уже назначен, и он не переезжает")
        t.expect(machine.remaining(at: after(60)), 24 * 60)
        t.expect(machine.advance(to: after(25 * 60)), [.pomodoroFinished(length: 25 * 60)],
                 "звеним, когда обещали")
        // Записывать в историю 45 минут значило бы записать помидор, которого
        // не было: выбор посреди помидора его не тронул.
    }

    t.test("Смена длительности не сдвигает идущий перерыв") {
        var machine = machineOnBreak()

        machine.durations = Durations(pomodoro: 25 * 60, breakInterval: 15 * 60)

        t.expect(machine.phase, .onBreak(until: after(30 * 60)))
        t.expect(machine.advance(to: after(30 * 60)), [.breakFinished])
    }

    t.test("Новая длина работает со следующего интервала") {
        var machine = TimerMachine()
        _ = machine.start(at: t0)
        machine.durations = Durations(pomodoro: 45 * 60, breakInterval: 15 * 60)
        _ = machine.advance(to: after(25 * 60))

        _ = machine.takeBreak(at: after(25 * 60))
        t.expect(machine.phase, .onBreak(until: after(40 * 60)), "перерыв уже новый")

        _ = machine.advance(to: after(40 * 60))
        _ = machine.start(at: after(40 * 60))
        t.expect(machine.phase, .pomodoro(until: after(85 * 60), length: 45 * 60),
                 "и следующий помидор тоже")
    }

    t.test("Смена длительности в простое ничего не запускает") {
        var machine = TimerMachine()
        machine.durations = Durations(pomodoro: 45 * 60, breakInterval: 15 * 60)

        t.expect(machine.phase, .idle)
        t.expect(machine.advance(to: after(60 * 60)), [])
    }

    // MARK: Хранение

    t.test("Выбор переживает перезапуск") {
        let chosen = Durations(pomodoro: 45 * 60, breakInterval: 15 * 60)

        t.expect(Durations(stored: chosen.stored), chosen)
    }

    t.test("Пустое хранилище — прежние длины") {
        t.expect(Durations(stored: [:]), .standard, "не выбирали — 25 и 5 минут")
    }

    t.test("Испорченная запись не тянет за собой вторую") {
        t.expect(Durations(stored: ["pomodoro": 45 * 60, "break": "пять"]),
                 Durations(pomodoro: 45 * 60, breakInterval: 5 * 60),
                 "перерыв вернулся к прежнему, помидор остался выбранным")
        t.expect(Durations(stored: ["pomodoro": 0, "break": 15 * 60]),
                 Durations(pomodoro: 25 * 60, breakInterval: 15 * 60))
    }

    t.test("Бессмысленные длины хранилище не принимает") {
        // Ключи правит человек, а помидор в ноль секунд звенел бы без остановки.
        for nonsense in [0, -60, 0.5, 121 * 60] as [TimeInterval] {
            t.expect(Durations(stored: ["pomodoro": nonsense]).pomodoro, 25 * 60, "помидор \(nonsense)")
        }
        for nonsense in [0, -60, 0.5, 61 * 60] as [TimeInterval] {
            t.expect(Durations(stored: ["break": nonsense]).breakInterval, 5 * 60, "перерыв \(nonsense)")
        }
    }

    t.test("Разумную длину мимо меню хранилище принимает") {
        // В меню тридцати минут нет, но `defaults write` — законный путь:
        // галочки в подменю тогда просто не будет ни у одной строки. Секунды
        // тут целые: так их кладёт `defaults write -int`.
        t.expect(Durations(stored: ["pomodoro": 30 * 60, "break": 7 * 60]),
                 Durations(pomodoro: 30 * 60, breakInterval: 7 * 60))
    }

    // MARK: Подписи в меню

    t.test("Минуты склоняются по-русски") {
        t.expect(DurationLabel.minutes(60), "1 минута")
        t.expect(DurationLabel.minutes(2 * 60), "2 минуты")
        t.expect(DurationLabel.minutes(4 * 60), "4 минуты")
        t.expect(DurationLabel.minutes(5 * 60), "5 минут")
        t.expect(DurationLabel.minutes(11 * 60), "11 минут", "одиннадцать — не одна")
        t.expect(DurationLabel.minutes(14 * 60), "14 минут")
        t.expect(DurationLabel.minutes(21 * 60), "21 минута")
        t.expect(DurationLabel.minutes(22 * 60), "22 минуты")
        t.expect(DurationLabel.minutes(25 * 60), "25 минут")
        t.expect(DurationLabel.minutes(45 * 60), "45 минут")
    }

    t.test("Неполная минута округляется до целой") {
        // В подменю секунд нет: там выбирают минуты.
        t.expect(DurationLabel.minutes(90), "2 минуты")
        t.expect(DurationLabel.minutes(30), "1 минута", "меньше минуты всё равно называем минутой")
    }

    t.test("Каждая предложенная длина называется без запинки") {
        let named = (Durations.pomodoroChoices + Durations.breakChoices).map(DurationLabel.minutes)
        t.expect(named.contains(where: \.isEmpty), false)
    }
}
