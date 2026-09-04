import AppKit
import ClepsydraCore

/// Тихая проверка обновлений. Раз в сутки спрашивает фид, кладёт ответ в
/// хранилище и отдаёт меню одной строкой — ни окон, ни звука, ни значков в
/// углу: меню сообщает, а не обращается к человеку (см. ADR-0009).
///
/// Сеть и часы живут здесь; правила — когда пора и что показывать — в
/// `ClepsydraCore`, где они покрыты проверками.
final class UpdateChecker {

    /// Что показывает пункт меню прямо сейчас.
    private(set) var state: UpdateState

    /// Установленная сборка: `CFBundleVersion`, то самое число, по которому
    /// идёт сравнение. Подставляет его `build.sh`.
    private let installed: String

    /// Когда фид спрашивали в последний раз — в памяти, а не в хранилище:
    /// неудачная попытка не результат, и помнить её между запусками незачем.
    private var lastAttempt: Date?
    private var isChecking = false

    init(installed: String = UpdateChecker.installedBuild) {
        self.installed = installed
        // Результат прошлой проверки переживает перезапуск: иначе каждый запуск
        // забывал бы про вышедшую версию и молчал до следующих суток.
        state = Updates.state(
            known: Settings.knownUpdate,
            lastCheck: Settings.lastUpdateCheck,
            installed: installed
        )
    }

    /// Тихая проверка. Висит на том же тике, что и отсчёт, и сама решает, пора
    /// ли: вопрос к ней тот же — сколько прошло, — поэтому пробуждение из сна
    /// отдельного случая не требует.
    func checkIfDue(now: Date) {
        guard Updates.isDue(
            lastCheck: Settings.lastUpdateCheck, lastAttempt: lastAttempt, now: now
        ) else { return }
        check(now: now)
    }

    /// Щелчок по «Проверить обновления» — спросить прямо сейчас, срока не
    /// дожидаясь.
    func checkNow() {
        check(now: Date())
    }

    /// Щелчок по «Обновить до 1.1» — страница релиза в браузере. Ставить
    /// обновление приложение пока не умеет.
    func openReleasePage() {
        NSWorkspace.shared.open(UpdateFeed.releasePage)
    }

    private func check(now: Date) {
        guard !isChecking else { return }
        isChecking = true
        lastAttempt = now

        // Пункт меню не трогаем, пока фид не ответил: и тихая проверка, и
        // щелчок оставляют его прежним — состояния «проверяем» у него нет.
        var request = URLRequest(url: UpdateFeed.address)
        request.timeoutInterval = 20
        // Свежий ответ, а не вчерашний: проверка идёт раз в сутки, и кэш отдал
        // бы прошлый выпуск ровно тогда, когда вышел новый.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let update = Self.update(from: data, response: response)
            DispatchQueue.main.async { self?.finish(update) }
        }.resume()
    }

    private static func update(from data: Data?, response: URLResponse?) -> Update? {
        guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UpdateFeed.parse(data)
    }

    /// Ни сети, ни ответа, ни разбора — молчание: пункт остаётся прежним, и
    /// проверка повторится по сроку. Ошибка проверки не повод обращаться
    /// к человеку.
    private func finish(_ update: Update?) {
        isChecking = false
        guard let update else { return }
        let checked = Date()
        Settings.lastUpdateCheck = checked
        Settings.knownUpdate = update
        state = Updates.state(known: update, lastCheck: checked, installed: installed)
    }

    /// Номер установленной сборки. Его нет — сравнивать нечем, и обновление не
    /// покажется: тот же случай молчания, что и неразобранный фид.
    private static var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
