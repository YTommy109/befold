import Foundation
import Security

/// ダウンロードしたアプリバンドルのコード署名を検証する。
/// 実行中アプリと同一の Team ID で署名されていることを確認し、
/// 改竄されたバイナリの自動インストールを防止する。
enum CodeSignatureVerifier {
    enum VerificationError: Error {
        case cannotCreateStaticCode
        case signatureInvalid
        case teamIDMismatch(expected: String, actual: String?)
        case teamIDUnavailable
    }

    /// 指定パスのアプリバンドルが、現在実行中のアプリと同一の Team ID で有効に署名されているか検証する。
    static func verify(appAt url: URL) throws {
        guard let expectedTeamID = runningAppTeamID() else {
            throw VerificationError.teamIDUnavailable
        }
        try verify(appAt: url, expectedTeamID: expectedTeamID)
    }

    /// 指定パスのアプリバンドルが、期待する Team ID で有効に署名されているか検証する。
    static func verify(appAt url: URL, expectedTeamID: String) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw VerificationError.cannotCreateStaticCode
        }

        let validateStatus = SecStaticCodeCheckValidity(code, [], nil)
        guard validateStatus == errSecSuccess else {
            throw VerificationError.signatureInvalid
        }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let infoStatus = SecCodeCopySigningInformation(code, flags, &info)
        guard infoStatus == errSecSuccess,
              let dict = info as? [String: Any],
              let actualTeamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            throw VerificationError.teamIDMismatch(expected: expectedTeamID, actual: nil)
        }

        guard actualTeamID == expectedTeamID else {
            throw VerificationError.teamIDMismatch(expected: expectedTeamID, actual: actualTeamID)
        }
    }

    /// 実行中アプリの Team ID を取得する。
    static func runningAppTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let sc = staticCode
        else {
            return nil
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(sc, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else {
            return nil
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
