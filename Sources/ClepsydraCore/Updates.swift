import Foundation

/// Обновление — выпуск новее установленного, о котором приложение узнало из
/// фида. Держит ровно то, что читает приложение: человеческую версию для
/// пункта меню и номер сборки для сравнения.
///
/// В фиде полей больше — адрес архива, дата, что изменилось. Их разбор
/// пропускает: показывать их негде, а установщик читает свой фид сам.
/// Отвергать из-за них фид тем более нельзя — установленной копии чинить его
/// нечем.
///
/// Сравнение идёт по `build` — это `CFBundleVersion`, момент сборки по UTC.
/// Человеческая строка для этого не годится: она меняется реже сборок и
/// сравнивается не числом.
public struct Update: Equatable {

    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Обновление из полей — фида или хранилища. Пустое поле, потерянное поле,
    /// номер сборки не числом — `nil`: молчание, а не догадка.
    ///
    /// Строгость к остальному живёт в `Tools/update-feed.sh`, где фид
    /// собирается: там неполный фид ловит человек и не выпускает его.
    public init?(fields: [String: Any]) {
        func field(_ name: String) -> String? {
            guard let value = fields[name] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let version = field("version"),
              let build = field("build"), Self.number(of: build) != nil
        else { return nil }
        self.init(version: version, build: build)
    }

    /// Результат проверки переживает перезапуск: обновление ложится в
    /// `UserDefaults` словарём, как история по дням.
    public var stored: [String: String] {
        ["version": version, "build": build]
    }

    /// Новее ли этот выпуск установленной сборки.
    public func isNewer(than installed: String) -> Bool {
        guard let mine = Self.number(of: build),
              let theirs = Self.number(of: installed) else { return false }
        return mine > theirs
    }

    /// Номер сборки числом — единственное место, где номер им становится.
    /// Чужую строку числом называть нельзя: подставленная руками ерунда не
    /// должна превращаться в «Обновить до 1.1», а `Int(_:)` простил бы и знак.
    private static func number(of build: String) -> Int? {
        guard build.allSatisfy(\.isNumber) else { return nil }
        return Int(build)
    }
}

/// Фид обновлений — единственное, что приложение спрашивает у сети. Кладёт его
/// `Tools/update-feed.sh` при каждом выпуске.
public enum UpdateFeed {

    /// Репозиторий, куда уходит релиз. Тот же, что сверяет `release.sh`:
    /// разойдись они, установленные копии спрашивали бы пустоту.
    public static let repository = "ilya-pesterev/clepsydra"

    /// Имя файла в релизе. Оно же печатает `Tools/update-feed.sh --name`.
    public static let fileName = "updates.json"

    /// Адрес постоянный — `releases/latest/download`, тот же приём, что у
    /// образа в README. Меняйся он от релиза к релизу, установленные копии
    /// перестали бы находить фид после первого же выпуска.
    public static let address = URL(
        string: "https://github.com/\(repository)/releases/latest/download/\(fileName)"
    )!

    /// Страница последнего релиза. Туда уходит человек, когда установить
    /// обновление на месте не вышло, — запасной путь, а не главный.
    public static let releasePage = URL(
        string: "https://github.com/\(repository)/releases/latest"
    )!

    /// Разбирает ответ фида. Не JSON, не те поля, не тот номер — `nil`:
    /// ошибка проверки не повод обращаться к человеку.
    public static func parse(_ data: Data) -> Update? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else { return nil }
        return Update(fields: fields)
    }
}

/// Что приложение знает об обновлении прямо сейчас. Ровно это и показывает
/// пункт меню — другого места у проверки нет: экран занят цитатой, а окон
/// проверка не открывает (см. ADR-0009).
///
/// Состояния «проверяем прямо сейчас» здесь нет намеренно. Тихая проверка
/// не имеет права трогать пункт, пока не ответила: «остаётся прежним» — это и
/// значит прежним.
public enum UpdateState: Equatable {
    /// Не проверяли ни разу или проверка не удалась.
    case unknown
    /// Проверили: новее нет.
    case upToDate
    /// Проверили: есть выпуск новее.
    case ready(Update)
}

/// Строка пункта меню. Живёт рядом с состоянием, а не в контроллере меню:
/// слова — часть решения, и проверяются они здесь же, без AppKit.
public enum UpdateLabel {
    public static func title(for state: UpdateState) -> String {
        switch state {
        case .unknown: return "Проверить обновления"
        case .upToDate: return "Установлена последняя версия"
        case .ready(let update): return "Обновить до \(update.version)"
        }
    }
}

/// Правила проверки: когда пора спрашивать фид и что показывать по ответу.
/// Без сети и без часов — момент приходит снаружи параметром, как в автомате.
public enum Updates {

    /// Раз в сутки. Чаще незачем: выпуск — событие редкое.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Сколько ждать после неудачной попытки. Проверка висит на том же тике,
    /// что и отсчёт, — без этого срока приложение долбило бы сеть каждую
    /// секунду, пока фид не ответит. Час, а не сутки: Mac, у которого в
    /// момент проверки не было сети, не должен ждать до завтра.
    public static let retryInterval: TimeInterval = 60 * 60

    /// Пора ли спрашивать фид. `lastCheck` — когда фид ответил в последний раз,
    /// `lastAttempt` — когда его в последний раз спрашивали.
    public static func isDue(lastCheck: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, now >= lastAttempt, now < lastAttempt + retryInterval { return false }
        guard let lastCheck else { return true }
        // Часы, отмотанные назад, иначе заперли бы проверку до конца суток.
        return now < lastCheck || now >= lastCheck + checkInterval
    }

    /// Состояние по тому, что известно. Проверки не было — зовём проверить;
    /// была, но фид не разобрался, — тоже: запоминать нечего, и говорить, что
    /// версия последняя, не за что.
    public static func state(known: Update?, lastCheck: Date?, installed: String) -> UpdateState {
        guard lastCheck != nil, let known else { return .unknown }
        return known.isNewer(than: installed) ? .ready(known) : .upToDate
    }
}
