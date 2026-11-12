import Foundation

/// WebAuthn's JSON, as the API sends it and takes it back (Better Auth's passkey plugin), to and
/// from the pieces Apple's AuthenticationServices wants. The Dart side hands the channel the options
/// JSON as a string and expects the credential JSON as a string, as on Android, where Credential
/// Manager reads and writes the same JSON itself.
public enum WebAuthnJSON {
    public struct ParseError: Error, Equatable {
        public let message: String
    }

    /// The options for signing in with a passkey.
    public struct AssertionRequest: Equatable {
        public let challenge: Data
        public let rpId: String
        /// Empty when the request names no credential (any passkey for the site may answer).
        public let allowCredentialIds: [Data]
        public let userVerification: String?
        /// The PRF salt (`extensions.prf.eval.first`) when the request asks for the passkey's PRF.
        public let prfInput: Data?
    }

    /// The options for creating a passkey.
    public struct RegistrationRequest: Equatable {
        public let challenge: Data
        public let rpId: String
        public let userName: String
        public let userId: Data
        public let excludeCredentialIds: [Data]
        /// `required`, `preferred` or `discouraged`; `preferred` when the request does not say.
        public let userVerification: String
        /// `none`, `indirect`, `direct` or `enterprise`; `none` when the request does not say.
        public let attestation: String
        /// The PRF salt (`extensions.prf.eval.first`) when the request asks for the passkey's PRF.
        public let prfInput: Data?
    }

    public static func parseAssertion(_ json: String) throws -> AssertionRequest {
        let object = try object(json)
        return AssertionRequest(
            challenge: try bytes(object["challenge"], "challenge"),
            rpId: try string(object["rpId"], "rpId"),
            allowCredentialIds: try credentialIds(object["allowCredentials"]),
            userVerification: object["userVerification"] as? String,
            prfInput: try prfInput(object["extensions"]))
    }

    public static func parseRegistration(_ json: String) throws -> RegistrationRequest {
        let object = try object(json)
        guard let rp = object["rp"] as? [String: Any] else { throw ParseError(message: "rp is missing") }
        guard let user = object["user"] as? [String: Any] else { throw ParseError(message: "user is missing") }
        let selection = object["authenticatorSelection"] as? [String: Any]
        return RegistrationRequest(
            challenge: try bytes(object["challenge"], "challenge"),
            rpId: try string(rp["id"], "rp.id"),
            userName: try string(user["name"], "user.name"),
            userId: try bytes(user["id"], "user.id"),
            excludeCredentialIds: try credentialIds(object["excludeCredentials"]),
            userVerification: selection?["userVerification"] as? String ?? "preferred",
            attestation: object["attestation"] as? String ?? "none",
            prfInput: try prfInput(object["extensions"]))
    }

    /// The signed-in credential, as the API's verification wants it. `userHandle` is left out when nil.
    /// `prfOutput` (the passkey's PRF) goes to `clientExtensionResults.prf.results.first`, as in a browser.
    public static func assertionResponse(
        credentialId: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?,
        prfOutput: Data? = nil
    ) -> String {
        var response: [String: Any] = [
            "clientDataJSON": base64url(clientDataJSON),
            "authenticatorData": base64url(authenticatorData),
            "signature": base64url(signature),
        ]
        if let userHandle { response["userHandle"] = base64url(userHandle) }
        return serialize(credential(credentialId, response, prf(enabled: false, output: prfOutput)))
    }

    /// The new credential, as the API's verification wants it. `prfEnabled` says the passkey supports
    /// the PRF (`prf.enabled`); `prfOutput` is its PRF when the registration already evaluated it.
    public static func registrationResponse(
        credentialId: Data, clientDataJSON: Data, attestationObject: Data,
        prfEnabled: Bool = false, prfOutput: Data? = nil
    ) -> String {
        serialize(credential(credentialId, [
            "clientDataJSON": base64url(clientDataJSON),
            "attestationObject": base64url(attestationObject),
            "transports": ["internal", "hybrid"],
        ], prf(enabled: prfEnabled, output: prfOutput)))
    }

    /// Base64url without padding (RFC 4648 section 5), WebAuthn's byte encoding.
    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The bytes of a base64url string, with or without padding; nil when it is not base64url.
    public static func fromBase64url(_ text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "=", with: "")
        switch base64.count % 4 {
        case 1: return nil
        case 2: base64 += "=="
        case 3: base64 += "="
        default: break
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - Private

    /// `clientExtensionResults`: empty without a PRF, as a browser without the extension.
    private static func prf(enabled: Bool, output: Data?) -> [String: Any] {
        var prf: [String: Any] = [:]
        if enabled { prf["enabled"] = true }
        if let output { prf["results"] = ["first": base64url(output)] }
        return prf.isEmpty ? [:] : ["prf": prf]
    }

    /// `extensions.prf.eval.first`, the PRF salt; nil when absent, an error when it is not base64url.
    private static func prfInput(_ extensions: Any?) throws -> Data? {
        let eval = ((extensions as? [String: Any])?["prf"] as? [String: Any])?["eval"] as? [String: Any]
        guard let first = eval?["first"] else { return nil }
        return try bytes(first, "extensions.prf.eval.first")
    }

    private static func credential(
        _ id: Data, _ response: [String: Any], _ extensionResults: [String: Any]
    ) -> [String: Any] {
        [
            "id": base64url(id),
            "rawId": base64url(id),
            "type": "public-key",
            "authenticatorAttachment": "platform",
            "clientExtensionResults": extensionResults,
            "response": response,
        ]
    }

    private static func serialize(_ object: [String: Any]) -> String {
        // The input is strings, arrays and dictionaries only: serializing cannot fail.
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func object(_ json: String) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            throw ParseError(message: "not a JSON object")
        }
        return object
    }

    private static func string(_ value: Any?, _ name: String) throws -> String {
        guard let text = value as? String, !text.isEmpty else { throw ParseError(message: "\(name) is missing") }
        return text
    }

    private static func bytes(_ value: Any?, _ name: String) throws -> Data {
        guard let data = fromBase64url(try string(value, name)) else {
            throw ParseError(message: "\(name) is not base64url")
        }
        return data
    }

    private static func credentialIds(_ value: Any?) throws -> [Data] {
        guard let list = value as? [[String: Any]] else { return [] }
        return try list.map { try bytes($0["id"], "credential id") }
    }
}
