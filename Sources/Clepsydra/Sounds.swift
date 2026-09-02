import AppKit

/// Два разных системных звука: когда экран появляется, ты можешь смотреть не на
/// него, а на телефон — «пора отдохнуть» и «пора работать» должны отличаться на слух.
enum Sounds {
    static func pomodoroFinished() { NSSound(named: "Glass")?.play() }
    static func breakFinished() { NSSound(named: "Blow")?.play() }
}
