import Foundation

/// Ключ, которым прогон подписывает. Из связки ключей он не берётся: там
/// живёт настоящий, и трогать его проверками нельзя. Семя постоянное, а не
/// случайное, — иначе непрошедшая проверка не повторялась бы.
let testUpdateKey = "ladbVS3KiuoHYjWNB0AimXp3MtfG0sH4dgCfBsQ+bgs="

/// Другой ключ — для случая «подписано не тем».
let otherUpdateKey = "6PNfeA+Ba9VlvJdZzy3h92PsogPR6QJ1wDWzNaeQ4xk="

/// Запускает подпись с ключом вместо связки ключей.
func runSigning(key: String = testUpdateKey, _ arguments: String...) -> (printed: String, status: Int32) {
    runTool("sign-update.swift", environment: ["CLEPSYDRA_UPDATE_KEY": key], arguments: arguments)
}

/// Подпись EdDSA — единственное, на чём держится доверие к обновлению:
/// Developer ID у проекта нет, подпись бандла ad-hoc, и проверить её
/// установщику не по чему (см. ADR-0010). Поэтому проверяется и то, что
/// подпись сходится, и то, что подменённый файл её не проходит.
func checkSignUpdate(_ t: Runner) {

    let archive = temporaryFile(named: "Clepsydra.zip", contents: "как будто бандл")

    t.test("Подпись сходится с файлом") {
        let signature = runSigning(archive)
        t.expect(signature.status, 0)
        t.expect(Data(base64Encoded: signature.printed)?.count, 64, "подпись ed25519 — 64 байта")
        t.expect(runSigning("--verify", archive, signature.printed).status, 0)
    }

    t.test("Подменённый по дороге архив подпись не проходит") {
        // Ровно тот случай, ради которого ключ и заведён: архив едет по сети,
        // подпись бандла ad-hoc, и подменить его иначе было бы нечем.
        let signature = runSigning(archive).printed
        let tampered = temporaryFile(named: "Clepsydra.zip", contents: "как будто бандл!")

        t.expect(runSigning("--verify", tampered, signature).status, 1)
    }

    t.test("Подписанное чужим ключом не проходит") {
        let stranger = runSigning(key: otherUpdateKey, archive).printed

        t.expect(runSigning("--verify", archive, stranger).status, 1)
        t.expect(runSigning(key: otherUpdateKey, "--verify", archive, stranger).status, 0,
                 "своим ключом та же подпись сходится")
    }

    t.test("Открытая половина ключа — 32 байта") {
        // Её и вписывают в SUPublicEDKey бандла: другой опоры у установленной
        // копии нет.
        let published = runSigning("--public")
        t.expect(published.status, 0)
        t.expect(Data(base64Encoded: published.printed)?.count, 32)
        t.expect(runSigning(key: otherUpdateKey, "--public").printed == published.printed, false,
                 "у разных ключей разные открытые половины")
    }

    t.test("Ключ не ключ — отказ, а не подпись чем попало") {
        t.expect(runSigning(key: "не base64", archive).status, 1)
        t.expect(runSigning(key: "0J/RgNC40LLQtdGC", archive).status, 1, "base64, но не 32 байта")
    }

    t.test("Нет файла, нет подписи, нет ключа — отказ") {
        t.expect(runSigning(missingPath()).status, 1)
        t.expect(runSigning("--verify", archive).status, 1, "проверке нужна подпись")
        t.expect(runSigning("--verify", archive, "не base64").status, 1)
    }
}
