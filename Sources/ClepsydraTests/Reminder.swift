import Foundation
import ClepsydraCore

/// Напоминание: правило «пора ли окликать» и слова, которыми оно говорит.
/// Живёт в `ClepsydraCore` — без уведомлений, без системных часов и без IOKit,
/// момент и время последнего касания приходят снаружи параметром, — и поэтому
/// покрыто проверками целиком (ADR-0014).
func checkReminder(_ t: Runner) {

    /// Человек за Mac: касание только что.
    let present: TimeInterval = 0
    /// За Mac никого: с последнего касания прошло больше порога.
    let away = Reminder.presence + 1

    // MARK: Срок

    t.test("Срок один и из списка не выбирается") {
        t.expect(Reminder.interval, 15 * 60)
        t.expect(Reminder.presence, 5 * 60)
        t.expect(Reminder.presence < Reminder.interval, true,
                 "порог присутствия должен быть заметно короче срока")
    }

    t.test("Пятнадцать минут простоя при человеке за Mac — пора окликать") {
        var rule = Reminder(from: t0)
        t.expect(fires(&rule, through: 20 * 60), [15 * 60])
    }

    t.test("За секунду до срока не окликаем") {
        var rule = Reminder(from: t0)
        t.expect(fires(&rule, through: 15 * 60 - 1), [])
    }

    t.test("Второй оклик приходит через пятнадцать минут после первого") {
        var rule = Reminder(from: t0)
        t.expect(fires(&rule, through: 40 * 60), [15 * 60, 30 * 60])
    }

    // MARK: Когда окликать нечего

    t.test("Под помидором, под перерывом и под экраном ожидания напоминание молчит") {
        for phase in [
            Phase.pomodoro(until: after(25 * 60), length: 25 * 60),
            .onBreak(until: after(5 * 60)),
            .awaitingBreak,
            .awaitingPomodoro
        ] {
            var rule = Reminder(from: t0)
            t.expect(fires(&rule, through: 60 * 60, phase: { _ in phase }), [],
                     "окликать нечего: круг идёт")
        }
    }

    t.test("Mac, которого не касались дольше порога, оклика не получает") {
        // Пустой Mac не окликают, и за ночь пачка баннеров не копится.
        var rule = Reminder(from: t0)
        t.expect(fires(&rule, through: 8 * 60 * 60, idle: { _ in away }), [])
    }

    t.test("На самом пороге ещё окликают") {
        var rule = Reminder(from: t0)
        t.expect(fires(&rule, through: 20 * 60, idle: { _ in Reminder.presence }), [15 * 60])
    }

    // MARK: Отсчёт заново

    t.test("Пропущенный оклик ничего не откладывает") {
        // Человека нет первые двадцать минут. Оклик на пятнадцатой пропал, но
        // следующий приходит на тридцатой — по своему сроку, а не через
        // пятнадцать минут после возвращения (это была бы 35-я).
        var rule = Reminder(from: t0)
        let fired = fires(&rule, through: 40 * 60,
                          idle: { $0 < 20 * 60 ? TimeInterval($0) : present })
        t.expect(fired, [30 * 60])
    }

    t.test("Запуск помидора отсчитывает пятнадцать минут заново") {
        // Помидор идёт с пятой минуты по тридцатую; оклик ждём на сорок пятой,
        // а не на тридцать пятой.
        var rule = Reminder(from: t0)
        let fired = fires(&rule, through: 50 * 60, phase: {
            (5 * 60...30 * 60).contains($0)
                ? .pomodoro(until: after(30 * 60), length: 25 * 60) : .idle
        })
        t.expect(fired, [45 * 60])
    }

    t.test("Сброс отсчитывает пятнадцать минут заново") {
        // Помидор сброшен на десятой минуте — оклик на двадцать пятой.
        var rule = Reminder(from: t0)
        let fired = fires(&rule, through: 30 * 60, phase: {
            $0 <= 10 * 60 ? .pomodoro(until: after(25 * 60), length: 25 * 60) : .idle
        })
        t.expect(fired, [25 * 60])
    }

    t.test("«Хватит» отсчитывает пятнадцать минут заново") {
        // Из круга вышли с экрана после перерыва на десятой минуте.
        var rule = Reminder(from: t0)
        let fired = fires(&rule, through: 30 * 60, phase: {
            $0 <= 10 * 60 ? .awaitingPomodoro : .idle
        })
        t.expect(fired, [25 * 60])
    }

    // MARK: Сон и часы

    t.test("После сна пропущенные оклики не выдаются пачкой") {
        var rule = Reminder(from: t0)
        let wake = 8 * 60 * 60

        // Разрыв между тиками больше минуты — Mac спал, а не подтормозил: та
        // же мерка, которой автомат отличает сон (ADR-0002).
        t.expect(rule.advance(to: after(TimeInterval(wake)), phase: .idle, idleFor: present),
                 false, "проснулись — считаем заново")
        t.expect(fires(&rule, from: wake + 1, through: wake + 20 * 60), [wake + 15 * 60])
    }

    t.test("Сон длиной ровно в срок оклика не выдаёт") {
        // Самый коварный сон: проснулись, когда срок только-только вышел.
        // Опоздания от срока тут нет вовсе — сон виден только по разрыву между
        // тиками. Иначе человек, разбудивший Mac, получал бы баннер про
        // пятнадцать минут, прошедшие во сне.
        var rule = Reminder(from: t0)
        _ = fires(&rule, through: 60)

        t.expect(rule.advance(to: after(15 * 60 + 10), phase: .idle, idleFor: present), false)
        t.expect(fires(&rule, from: 15 * 60 + 11, through: 31 * 60), [30 * 60 + 10],
                 "и дальше считаем от пробуждения")
    }

    t.test("Тик, опоздавший на секунды, сном не считается") {
        // Подтормозившая система — не сон: срок пришёл, оклик приходит.
        var rule = Reminder(from: t0)
        _ = fires(&rule, through: 15 * 60 - 1)
        t.expect(rule.advance(to: after(15 * 60 + 30), phase: .idle, idleFor: present), true)
    }

    t.test("Часы, отмотанные назад, не запирают оклик") {
        var rule = Reminder(from: t0)
        t.expect(rule.advance(to: after(-60 * 60), phase: .idle, idleFor: present), false)
        t.expect(fires(&rule, from: -60 * 60 + 1, through: -40 * 60), [-45 * 60])
    }

    // MARK: Слова

    t.test("Пункт меню не ставит галочку, когда разрешения нет") {
        // Включённый пункт при отозванном разрешении — молчащее напоминание,
        // которое человек считает поломкой.
        t.expect(ReminderLabel.isOn(.on), true)
        t.expect(ReminderLabel.isOn(.off), false)
        t.expect(ReminderLabel.isOn(.silenced), false, "молчащая галочка была бы враньём")
    }

    t.test("Запрет виден в названии пункта") {
        t.expect(ReminderLabel.menu(for: .off), ReminderLabel.menu(for: .on),
                 "выключенный и включённый пункт зовутся одинаково — разница в галочке")
        t.expect(ReminderLabel.menu(for: .silenced) == ReminderLabel.menu(for: .on), false)
    }

    t.test("Уведомление говорит одну вещь — что сессия не запущена") {
        let notice = ReminderLabel.notice.lowercased()
        t.expect(notice.contains("сесси"), true)
        t.expect(notice.contains("помидор"), false, "на экран слово «помидор» не выходит")
        t.expect(notice.contains("сегодня"), false, "счёта за день в уведомлении нет")
        t.expect(notice.contains("верси"), false, "про обновление уведомление молчит")
        t.expect(notice.contains("вчера"), false, "вчерашнего сравнения в уведомлении нет")
    }

    t.test("Кнопка в уведомлении зовётся глаголом") {
        t.expect(ReminderLabel.noticeAction, "Запустить")
    }
}

/// Прогон секунда за секундой — так правило и живёт: висит на том же тике,
/// что и отсчёт в меню-баре. Возвращает секунды, в которые пришёл оклик.
private func fires(
    _ rule: inout Reminder,
    from first: Int = 1,
    through last: Int,
    phase: (Int) -> Phase = { _ in .idle },
    idle: (Int) -> TimeInterval = { _ in 0 }
) -> [Int] {
    var fired: [Int] = []
    for second in first...last
    where rule.advance(to: after(TimeInterval(second)), phase: phase(second), idleFor: idle(second)) {
        fired.append(second)
    }
    return fired
}
