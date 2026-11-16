//
//  SchoolConnection.swift
//  SPAI
//
//  Which school this headset belongs to, and the secret that proves it.
//
//  A headset is paired once, by an admin typing a one-time code from the
//  instructor dashboard. The server answers with a token that only this
//  headset holds. The token lives in the Keychain, so it survives app
//  updates, can't be read by other apps, and is never shown on screen.
//  Disconnecting the headset (here or from the dashboard) ends it.
//

import Foundation
import Security

enum SecretStore {
    private static let service = "app.spai.headset"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, for account: String) -> Bool {
        delete(account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            // Readable once the headset has been unlocked after a restart,
            // never copied to another device through a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// What this headset knows about the school it is paired with.
@MainActor
@Observable
final class SchoolConnection {
    static let shared = SchoolConnection()

    private static let tokenAccount = "deviceToken"
    private let schoolKey = "pairedSchoolName"
    private let headsetKey = "pairedHeadsetName"
    private let serverKey = "backendURL"

    private(set) var schoolName: String?
    private(set) var headsetName: String?

    var isPaired: Bool { token != nil }

    /// The headset's secret. Read straight from the Keychain each time so a
    /// disconnect takes effect everywhere at once.
    var token: String? { SecretStore.read(Self.tokenAccount) }

    private init() {
        schoolName = UserDefaults.standard.string(forKey: schoolKey)
        headsetName = UserDefaults.standard.string(forKey: headsetKey)
    }

    func savePairing(server: String, token: String, school: String, headset: String) {
        UserDefaults.standard.set(server, forKey: serverKey)
        SecretStore.write(token, for: Self.tokenAccount)
        UserDefaults.standard.set(school, forKey: schoolKey)
        UserDefaults.standard.set(headset, forKey: headsetKey)
        schoolName = school
        headsetName = headset
    }

    func refresh(school: String, headset: String) {
        if school != schoolName {
            schoolName = school
            UserDefaults.standard.set(school, forKey: schoolKey)
        }
        if headset != headsetName {
            headsetName = headset
            UserDefaults.standard.set(headset, forKey: headsetKey)
        }
    }

    /// Forget the school. Used when the user disconnects, and when the
    /// server says this headset's token is no longer valid.
    func forget() {
        SecretStore.delete(Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: schoolKey)
        UserDefaults.standard.removeObject(forKey: headsetKey)
        schoolName = nil
        headsetName = nil
    }
}
