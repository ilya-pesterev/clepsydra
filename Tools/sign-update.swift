#!/usr/bin/env swift
//
// Ключ обновления и подпись архива. Всё, что установленная копия знает о
// доверии: Developer ID у проекта нет, подпись бандла ad-hoc, и проверить её
// установщику не по чему. Остаётся ключ EdDSA — открытая половина едет в
// бандле (`SUPublicEDKey`), закрытая живёт в связке ключей на машине автора.
//
//   ./Tools/sign-update.swift Clepsydra.zip              подпись архива, base64
//   ./Tools/sign-update.swift --public                   открытая половина ключа
//   ./Tools/sign-update.swift --verify Clepsydra.zip ... проверка подписи
//   ./Tools/sign-update.swift --create                   завести ключ в связке
//
// Ключ берётся из связки ключей. Переменная CLEPSYDRA_UPDATE_KEY (закрытая
// половина в base64) её подменяет: так прогон проверяет подпись своим ключом,
// не трогая связку, и так же подписывают не с машины автора.
//
// Формат тот же, что у Sparkle: 32 байта семени в base64, связка ключей
// «https://sparkle-project.org», учётная запись «clepsydra». Поэтому тем же
// ключом умеет подписывать и sign_update из поставки Sparkle — на случай,
// если этот скрипт когда-нибудь окажется потерян, а ключ нет.
//
// Что делать, если ключ потерян, — в docs/development.md.

import CryptoKit
import Foundation
import Security

let keychainService = "https://sparkle-project.org"
let keychainAccount = "clepsydra"
let keyVariable = "CLEPSYDRA_UPDATE_KEY"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ОШИБКА: \(message)\n".utf8))
    exit(1)
}

/// Закрытая половина ключа: из переменной окружения, иначе из связки ключей.
func privateKey() -> Curve25519.Signing.PrivateKey {
    if let outside = ProcessInfo.processInfo.environment[keyVariable], !outside.isEmpty {
        return key(fromBase64: outside, source: "переменной \(keyVariable)")
    }
    return key(fromBase64: seedFromKeychain(), source: "связки ключей")
}

func key(fromBase64 base64: String, source: String) -> Curve25519.Signing.PrivateKey {
    let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: trimmed), seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else {
        fail("ключ из \(source) — не 32 байта семени в base64.")
    }
    return key
}

func keychainQuery(returningData: Bool) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecAttrProtocol as String: kSecAttrProtocolSSH
    ]
    if returningData { query[kSecReturnData as String] = true }
    return query
}

func seedFromKeychain() -> String {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(keychainQuery(returningData: true) as CFDictionary, &item)
    switch status {
    case errSecSuccess:
        guard let data = item as? Data, let base64 = String(data: data, encoding: .utf8) else {
            fail("в связке ключей лежит не ключ.")
        }
        return base64
    case errSecItemNotFound:
        fail("""
            ключа обновления нет в связке ключей.
            Завести: ./Tools/sign-update.swift --create
            Потерянный ключ не восстанавливается — см. docs/development.md.
            """)
    default:
        fail("связка ключей не отдала ключ (\(status)). Разблокируйте её и повторите.")
    }
}

/// Заводит ключ. Второй раз не заводит: перезаписанный ключ оставил бы все
/// установленные копии без обновлений, а узнал бы об этом автор только на
/// следующем выпуске.
func createKey() -> Never {
    var item: CFTypeRef?
    if SecItemCopyMatching(keychainQuery(returningData: false) as CFDictionary, &item) == errSecSuccess {
        fail("""
            ключ обновления в связке ключей уже есть — второй завести нельзя.
            Открытая половина: ./Tools/sign-update.swift --public
            """)
    }

    let key = Curve25519.Signing.PrivateKey()
    var query = keychainQuery(returningData: false)
    query[kSecValueData as String] = Data(key.rawRepresentation.base64EncodedString().utf8)
    query[kSecAttrLabel as String] = "Clepsydra: ключ обновления (EdDSA)"

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        fail("связка ключей не приняла ключ (\(status)).")
    }

    print(key.publicKey.rawRepresentation.base64EncodedString())
    FileHandle.standardError.write(Data("""
        Ключ заведён. Открытая половина напечатана выше — впишите её в
        Resources/Info.plist под ключом SUPublicEDKey и закоммитьте.

        """.utf8))
    exit(0)
}

func contents(of path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("нет файла \(path).")
    }
    return data
}

// --- Разбор ключей ------------------------------------------------------------

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--create":
    createKey()

case "--public":
    print(privateKey().publicKey.rawRepresentation.base64EncodedString())

case "--verify":
    guard arguments.count == 3 else {
        fail("проверке нужны файл и подпись: --verify Clepsydra.zip <подпись>.")
    }
    guard let signature = Data(base64Encoded: arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fail("подпись — не base64.")
    }
    guard privateKey().publicKey.isValidSignature(signature, for: contents(of: arguments[1])) else {
        fail("подпись не сходится с файлом \(arguments[1]).")
    }

case .some(let path) where !path.hasPrefix("--"):
    guard arguments.count == 1 else { fail("подписывают один файл, а не \(arguments.count).") }
    guard let signature = try? privateKey().signature(for: contents(of: path)) else {
        fail("не удалось подписать \(path).")
    }
    print(signature.base64EncodedString())

default:
    fail("не назван файл. Есть --public, --verify, --create и путь к архиву.")
}
