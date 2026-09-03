import AppKit

// До делегата: он читает историю в момент создания.
Settings.migrateLegacyTally()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
