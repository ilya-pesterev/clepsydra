import AppKit
import UserNotifications
import ClepsydraCore

/// Второй голос приложения (ADR-0014): уведомление тому, кто за Mac и сессию
/// не запустил. Здесь живёт всё нечистое — разрешение, центр уведомлений и
/// счётчик простоя; правило «пора ли окликать» в `ClepsydraCore`, где оно
/// покрыто прогоном.
///
/// Устроено как тихая проверка обновлений: висит на том же тике, что и
/// отсчёт, и само решает, пора ли.
final class ReminderVoice: NSObject, UNUserNotificationCenterDelegate {

    /// Уведомление в Центре одно, и вид у него один: идентификатор общий и у
    /// запроса, и у вида. Новое уведомление заменяет прежнее, а не копится
    /// пачкой к утру.
    private static let identifier = "reminder"
    private static let startAction = "start"

    /// Как часто сверяемся с системой, разрешено ли нам говорить. Разрешение
    /// отзывают в системных настройках, и приложению об этом не сообщают —
    /// спросить приходится самим. Раз в минуту, а не каждый тик: это вопрос
    /// через XPC, а не чтение поля.
    private static let permissionInterval: TimeInterval = 60

    /// Что система ответила про разрешение. Три ответа, а не два: «не
    /// спрашивали» и «отказали» — разные вещи, и пункт меню у них разный.
    private enum Permission {
        case unknown
        case allowed
        case denied
    }

    /// Центр уведомлений спрашивают только у бандла: без `CFBundleIdentifier`
    /// `UNUserNotificationCenter.current()` роняет приложение, а из
    /// `swift run` идентификатора как раз и нет. Тогда напоминание молчит
    /// целиком — тот же случай, что и отказ в разрешении.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : .current()

    /// Что делает «Запустить» в уведомлении — ровно то же, что и пункт меню.
    private let start: () -> Void

    private var rule = Reminder(from: Date())
    private var permission: Permission = .unknown
    private var lastPermissionCheck: Date?
    /// Висит ли уведомление в Центре. Центр держит его, пока не уберут, —
    /// значит, убрать его должны мы.
    private var isShowing = false

    init(start: @escaping () -> Void) {
        self.start = start
        super.init()

        guard let center else { return }
        center.delegate = self

        // Кнопка в уведомлении. Пустые `options` нарочно: `.foreground` подняло
        // бы приложение — с иконкой в Dock и окном. Помидор начинается молча,
        // как из меню.
        let action = UNNotificationAction(
            identifier: Self.startAction, title: ReminderLabel.noticeAction, options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.identifier, actions: [action],
                intentIdentifiers: [], options: []
            )
        ])
    }

    /// Что показывает пункт меню прямо сейчас — и, через `ReminderLabel.isOn`,
    /// то же самое решает, говорить ли: галочка и голос обязаны сходиться.
    ///
    /// Система запретила — пункт говорит это, включали его или нет: молчащая
    /// галочка и мёртвый пункт врут одинаково. Пока система не ответила, пункт
    /// верит хранилищу: полсекунды после запуска — не повод объявлять
    /// напоминание запрещённым.
    var state: ReminderState {
        guard permission != .denied else { return .silenced }
        return Settings.reminderIsOn ? .on : .off
    }

    /// Тик. Висит на том же тике, что и отсчёт: вопрос к правилу тот же —
    /// сколько прошло, — поэтому пробуждение из сна отдельного случая не
    /// требует.
    func advance(to now: Date, phase: Phase) {
        refreshPermission(now: now)

        // Круг пошёл — снимаем висящее уведомление: «Сессия не запущена»
        // поверх идущей сессии врёт, а Центр держит его, пока не уберут.
        if phase != .idle { withdraw() }

        // Говорим ровно тогда, когда в меню стоит галочка, — и спрашиваем это
        // одной и той же функцией. Порознь эти два вопроса разошлись: пункт
        // считал себя включённым, пока система не отказала, а голос требовал
        // прямого разрешения, — и в состоянии «не спрашивали» галочка стояла
        // над молчанием. Врать так пункту запрещает ADR-0014.
        //
        // Не спрашивали — говорим всё равно: человек напоминание включил, а
        // распорядиться сказанным — дело системы. Она же прячет баннер в «Не
        // беспокоить», и там наше молчание тоже не наше.
        guard ReminderLabel.isOn(state) else {
            rule.restart(at: now)
            return
        }
        guard rule.advance(to: now, phase: phase, idleFor: Self.idleSeconds()) else { return }
        deliver()
    }

    /// Щелчок по пункту меню. Выключенный пункт тем же щелчком спрашивает
    /// разрешение у системы: приложение, которое просит разрешений на старте, —
    /// противоположность тихому (ADR-0014).
    func toggle() {
        guard !Settings.reminderIsOn else {
            Settings.reminderIsOn = false
            // Голос отобрали — договорить ему нечего.
            withdraw()
            return
        }

        // Отказали — пункт не включается, и второй раз в тот же щелчок никто
        // не переспрашивает. Система, у которой разрешение уже спрашивали и
        // получили «нет», отвечает сразу и окна не показывает — но пункт после
        // этого зовётся третьим лицом и ведёт в системные настройки, а не
        // остаётся мёртвым.
        ask { [weak self] allowed in
            guard let self else { return }
            permission = allowed ? .allowed : .denied
            guard allowed else { return }
            Settings.reminderIsOn = true
            rule.restart(at: Date())
        }
    }

    /// Третье лицо пункта: разрешение отозвали в системных настройках, и
    /// починить это внутри приложения нечем — отправляем туда, где отзывали.
    func openSystemSettings() {
        guard let settings = URL(
            string: "x-apple.systempreferences:com.apple.preference.notifications"
        ) else { return }
        NSWorkspace.shared.open(settings)
    }

    // MARK: Система

    private func ask(_ answer: @escaping (Bool) -> Void) {
        guard let center else { return answer(false) }
        // Только баннер: звука напоминание не просит. Оклик раз в пятнадцать
        // минут — не сигнал конца помидора, и перебивать работу ему нечем.
        center.requestAuthorization(options: [.alert]) { allowed, _ in
            DispatchQueue.main.async { answer(allowed) }
        }
    }

    /// Сверка с системой. Идёт и при выключенном напоминании: пункт меню
    /// обязан говорить правду и до того, как его включили, — иначе первый
    /// щелчок после отказа уходит в пустоту.
    private func refreshPermission(now: Date) {
        guard let center else { return }
        // Часы, отмотанные назад, иначе заперли бы вопрос до конца минуты.
        if let lastPermissionCheck, now >= lastPermissionCheck,
           now < lastPermissionCheck + Self.permissionInterval { return }
        lastPermissionCheck = now

        center.getNotificationSettings { [weak self] settings in
            let answer: Permission
            switch settings.authorizationStatus {
            case .authorized, .provisional: answer = .allowed
            case .denied: answer = .denied
            // «Не спрашивали» и всё, чего мы не знаем, — не отказ: объявлять
            // напоминание запрещённым не за что.
            default: answer = .unknown
            }
            DispatchQueue.main.async { self?.permission = answer }
        }
    }

    private func deliver() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = ReminderLabel.notice
        content.categoryIdentifier = Self.identifier
        center.add(UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: nil
        ))
        isShowing = true
    }

    private func withdraw() {
        guard isShowing else { return }
        isShowing = false
        center?.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    /// Сколько прошло с последнего касания клавиатуры или мыши. Разрешения на
    /// этот вопрос система не спрашивает: это не наблюдение за тем, что человек
    /// делает, а один счётчик секунд.
    ///
    /// `~0` — это `kCGAnyInputEventType`: любое касание, а не событие одного
    /// вида. Именованной константы для него в Swift нет, поэтому число.
    ///
    /// Счётчика не оказалось — молчим: ошибаться тут положено в сторону
    /// молчания, оклик в пустую комнату стоит дороже непришедшего (ADR-0014).
    private static func idleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    // MARK: Ответ на уведомление

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Щелчок по самому уведомлению не делает ничего: экрана он не
        // разворачивает (ADR-0014), а других дел у него нет. Помидор начинает
        // кнопка, и только она.
        if response.actionIdentifier == Self.startAction {
            DispatchQueue.main.async { [weak self] in self?.start() }
        }
        completionHandler()
    }
}
