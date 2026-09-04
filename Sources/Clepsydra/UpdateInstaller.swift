import AppKit
import Sparkle

/// Установка обновления на месте. Щелчок по «Обновить до 1.1» — и новая
/// версия скачивается, заменяет установленную и запускается уже новой: ни
/// браузера, ни перетаскивания, ни похода в «Конфиденциальность и
/// безопасность». Почему без этого не обойтись и чем за это заплачено —
/// в ADR-0010.
///
/// Окон не открывает ни одного. Sparkle приходит со своим интерфейсом —
/// окном «вышла новая версия», описанием выпуска, полосой загрузки, — и
/// весь этот интерфейс здесь заменён молчанием: экран остаётся единственным
/// местом, где приложение обращается к человеку (ADR-0001, ADR-0009).
/// Поэтому `SPUUserDriver` реализован целиком, и не показывает ничего ни один
/// его метод: где Sparkle ждёт ответа — отвечаем, где ждёт окна — молчим.
///
/// Если поставить не вышло — открываем страницу релиза, как раньше. Молчание
/// в ответ на щелчок было бы хуже брошенного дела: человек попросил, а не
/// проверка сходила в сеть сама.
@MainActor
final class UpdateInstaller: NSObject, SPUUserDriver {

    /// Что делать, когда установка не задалась: страница релиза в браузере —
    /// ровно то, что приложение умело до установщика.
    private let openReleasePage: () -> Void

    /// Заводится при первом щелчке, а не при запуске: пока человек не
    /// попросил, Sparkle в приложении не работает вовсе — ни проверок, ни
    /// расписания, ни сети. Автопроверка выключена и в `Info.plist`
    /// (`SUEnableAutomaticChecks`), но не заводить её вовсе надёжнее, чем
    /// выключать.
    private var updater: SPUUpdater?

    /// Идёт ли установка. Меню откроют снова, пока идёт загрузка, и второй
    /// щелчок по «Обновить» не должен начинать всё заново. Sparkle повторный
    /// вызов пропустила бы и сама, но полагаться на её внутреннюю проверку
    /// здесь нечем: у щелчка есть и запасной путь, и открывать страницу
    /// релиза посреди идущей установки было бы враньём.
    private var isInstalling = false

    init(openReleasePage: @escaping () -> Void) {
        self.openReleasePage = openReleasePage
    }

    /// Щелчок по «Обновить до 1.1».
    func install() {
        guard !isInstalling else { return }

        guard let updater = startedUpdater() else {
            openReleasePage()
            return
        }

        isInstalling = true
        updater.checkForUpdates()
    }

    /// Заведённый и запущенный установщик. Не завёлся — `nil`: сюда приходит
    /// и потерянный открытый ключ, и испорченный `Info.plist`, и всё это
    /// одинаково значит «поставить нечем».
    private func startedUpdater() -> SPUUpdater? {
        if let updater { return updater }

        let started = SPUUpdater(
            hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil
        )
        // Расписание Sparkle не нужно: раз в сутки фид спрашивает сама
        // Clepsydra, молча, и показывает ответ пунктом меню (ADR-0009).
        started.automaticallyChecksForUpdates = false
        started.automaticallyDownloadsUpdates = false

        do {
            try started.start()
        } catch {
            NSLog("Clepsydra: установщик обновлений не завёлся: \(error.localizedDescription)")
            return nil
        }

        updater = started
        return started
    }

    /// Установка кончилась ничем. Пункт меню остаётся прежним — его лицо
    /// решает тихая проверка, а не установщик, — и человек уходит на страницу
    /// релиза, откуда поставит руками.
    private func giveUp() {
        isInstalling = false
        openReleasePage()
    }

    // MARK: Интерфейс, которого нет

    // Спрашивать разрешение на автопроверки не о чем: их нет. Sparkle этого и
    // не спросит — `SUEnableAutomaticChecks` в `Info.plist` уже отвечает, —
    // но протокол обязателен целиком, и ответ здесь тот же.
    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    /// Выпуск найден — ставим не спрашивая: человек уже спросил, щёлкнув по
    /// пункту меню. Второго вопроса тому, кто и так попросил, не задают.
    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        // Выпуск, который нечего ставить: Sparkle зовёт такие «information
        // only» и ждёт, что человека отправят читать страницу. Отправляем.
        guard !appcastItem.isInformationOnlyUpdate else {
            reply(.dismiss)
            giveUp()
            return
        }
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    /// Установщик новее не нашёл, а пункт меню звал обновляться: два фида
    /// разошлись. Чинить это установленной копии нечем — остаётся страница
    /// релиза.
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        giveUp()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSLog("Clepsydra: обновление не поставилось: \(error.localizedDescription)")
        acknowledgement()
        giveUp()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    /// Скачано и распаковано — ставим и перезапускаемся. Спрашивать снова
    /// незачем: щелчок по «Обновить до 1.1» и был согласием.
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool, acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    /// Sparkle закончила — чем угодно. Отсюда путь один: забыть, что установка
    /// шла. Страницу здесь не открываем: сюда приходит и удачная установка.
    func dismissUpdateInstallation() {
        isInstalling = false
    }
}
