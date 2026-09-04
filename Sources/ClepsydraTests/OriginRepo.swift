import Foundation

/// Адрес репозитория выводит `Tools/origin-repo.sh` — из origin, а не из
/// строки в скрипте. Источник один на всех: и релиз уходит туда, и ссылка
/// в описании релиза ведёт туда же.
func checkOriginRepo(_ t: Runner) {

    t.test("Адрес — owner/name из origin") {
        let run = runTool("origin-repo.sh")
        t.expect(run.printed, "ilya-pesterev/clepsydra")
        t.expect(run.status, 0)
    }

    t.test("Адрес читается из обеих записей GitHub") {
        t.expect(runTool("origin-repo.sh", "git@github.com:owner/name.git").printed, "owner/name")
        t.expect(runTool("origin-repo.sh", "https://github.com/owner/name.git").printed, "owner/name")
        t.expect(runTool("origin-repo.sh", "https://github.com/owner/name").printed, "owner/name",
                 "без .git на конце тоже пишут")
    }

    t.test("Не GitHub — не адрес релиза") {
        let run = runTool("origin-repo.sh", "https://example.com/owner/name.git")
        t.expect(run.printed, "")
        t.expect(run.status, 1)
    }
}
