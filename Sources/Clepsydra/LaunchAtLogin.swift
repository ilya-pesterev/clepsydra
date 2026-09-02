import ServiceManagement

/// Единственная настройка приложения.
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
