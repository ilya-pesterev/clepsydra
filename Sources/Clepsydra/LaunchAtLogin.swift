import ServiceManagement

/// Запуск при входе. Единственной настройкой быть перестал: в корне меню
/// с ним рядом стоит второй переключатель — напоминание (ADR-0014). Живёт не
/// в `Settings`, а в системе: выбор помнит она.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Clepsydra: не удалось переключить запуск при входе — \(error.localizedDescription)")
        }
    }
}
