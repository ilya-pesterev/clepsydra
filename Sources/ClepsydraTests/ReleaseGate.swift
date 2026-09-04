import Foundation

/// Ворота релиза — `Tools/release-gate.sh`. Выпуск с невыросшим номером сборки
/// обновление никому не покажет: сравнение версий идёт по `CFBundleVersion`,
/// а не по человеческой строке.
func checkReleaseGate(_ t: Runner) {

    func lastRelease(_ contents: String) -> String {
        temporaryFile(named: "last-release-build", contents: contents)
    }

    t.test("Номер вырос — ворота открыты") {
        t.expect(runTool("release-gate.sh", "20260904120000",
                         lastRelease("20260903120000\n")).status, 0)
    }

    t.test("Номер не вырос — отказ") {
        let previous = lastRelease("20260904120000\n")
        t.expect(runTool("release-gate.sh", "20260903120000", previous).status, 1,
                 "часы на машине сбились назад")
        t.expect(runTool("release-gate.sh", "20260904120000", previous).status, 1,
                 "тот же номер — тоже не рост")
    }

    t.test("Прошлых релизов нет — сверять не с чем") {
        t.expect(runTool("release-gate.sh", "20260904120000", missingPath()).status, 0)
    }

    t.test("В файле не номер — провал, а не молчаливый пропуск") {
        t.expect(runTool("release-gate.sh", "20260904120000", lastRelease("неизвестно\n")).status, 1)
    }

    t.test("Номер сборки надо назвать") {
        t.expect(runTool("release-gate.sh").status, 1)
    }
}
