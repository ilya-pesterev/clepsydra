import Foundation
import ClepsydraCore

/// То немногое, что переживает перезапуск. Длительности зашиты, поэтому здесь
/// только режим цитат; запуск при входе живёт в системе, а не здесь.
enum Settings {

    private static let modeKey = "quoteMode"

    static var quoteMode: QuoteMode {
        get {
            UserDefaults.standard.string(forKey: modeKey)
                .flatMap(QuoteMode.init(rawValue:)) ?? .philosophers
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }
}
