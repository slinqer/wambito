import XCTest
@testable import WambitoNative

final class WebAuthnJSONTests: XCTestCase {
    // The options the API returns for a sign-in (invented values).
    private let assertionJSON = """
    {"challenge":"AQIDBA","rpId":"app.wambito.com","allowCredentials":[{"id":"-_8","type":"public-key"},\
    {"id":"AAEC","type":"public-key"}],"userVerification":"preferred","timeout":60000}
    """

    // The options the API returns for creating a passkey (invented values).
    private let registrationJSON = """
    {"challenge":"AQIDBA","rp":{"id":"app.wambito.com","name":"Wambito"},\
    "user":{"id":"dXNlci0x","name":"ana@example.com","displayName":"ana@example.com"},\
    "pubKeyCredParams":[{"alg":-7,"type":"public-key"},{"alg":-257,"type":"public-key"}],\
    "timeout":60000,"excludeCredentials":[{"id":"AAEC","type":"public-key"}],\
    "authenticatorSelection":{"residentKey":"required","userVerification":"required"},\
    "attestation":"direct"}
    """

    func testParsesAnAssertionRequest() throws {
        let request = try WebAuthnJSON.parseAssertion(assertionJSON)
        XCTAssertEqual(request.challenge, Data([1, 2, 3, 4]))
        XCTAssertEqual(request.rpId, "app.wambito.com")
        XCTAssertEqual(request.allowCredentialIds, [Data([0xfb, 0xff]), Data([0, 1, 2])])
        XCTAssertEqual(request.userVerification, "preferred")
    }

    func testAssertionWithoutAllowListOrVerification() throws {
        let request = try WebAuthnJSON.parseAssertion(#"{"challenge":"AQIDBA","rpId":"app.wambito.com"}"#)
        XCTAssertEqual(request.allowCredentialIds, [])
        XCTAssertNil(request.userVerification)
    }

    func testAssertionWithoutChallengeThrows() {
        XCTAssertThrowsError(try WebAuthnJSON.parseAssertion(#"{"rpId":"app.wambito.com"}"#))
    }

    func testAssertionWithoutRpIdThrows() {
        XCTAssertThrowsError(try WebAuthnJSON.parseAssertion(#"{"challenge":"AQIDBA"}"#))
    }

    func testNotJSONThrows() {
        XCTAssertThrowsError(try WebAuthnJSON.parseAssertion("nope"))
        XCTAssertThrowsError(try WebAuthnJSON.parseRegistration("[]"))
    }

    func testParsesARegistrationRequest() throws {
        let request = try WebAuthnJSON.parseRegistration(registrationJSON)
        XCTAssertEqual(request.challenge, Data([1, 2, 3, 4]))
        XCTAssertEqual(request.rpId, "app.wambito.com")
        XCTAssertEqual(request.userName, "ana@example.com")
        XCTAssertEqual(request.userId, Data("user-1".utf8))
        XCTAssertEqual(request.excludeCredentialIds, [Data([0, 1, 2])])
        XCTAssertEqual(request.userVerification, "required")
        XCTAssertEqual(request.attestation, "direct")
    }

    func testRegistrationDefaults() throws {
        let request = try WebAuthnJSON.parseRegistration(
            #"{"challenge":"AQIDBA","rp":{"id":"app.wambito.com"},"user":{"id":"dXNlci0x","name":"ana"}}"#)
        XCTAssertEqual(request.userVerification, "preferred")
        XCTAssertEqual(request.attestation, "none")
        XCTAssertEqual(request.excludeCredentialIds, [])
    }

    func testRegistrationWithoutUserThrows() {
        XCTAssertThrowsError(try WebAuthnJSON.parseRegistration(
            #"{"challenge":"AQIDBA","rp":{"id":"app.wambito.com"}}"#))
    }

    func testBase64urlRoundTrip() throws {
        let bytes = Data([0xfb, 0xff])
        XCTAssertEqual(WebAuthnJSON.base64url(bytes), "-_8")
        XCTAssertEqual(WebAuthnJSON.fromBase64url("-_8"), bytes)
        XCTAssertEqual(WebAuthnJSON.fromBase64url("-_8="), bytes)
        XCTAssertEqual(WebAuthnJSON.fromBase64url(""), Data())
        XCTAssertNil(WebAuthnJSON.fromBase64url("a"))
    }

    func testAssertionResponseShape() throws {
        let json = WebAuthnJSON.assertionResponse(
            credentialId: Data([0xfb, 0xff]), clientDataJSON: Data([1]), authenticatorData: Data([2]),
            signature: Data([3]), userHandle: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "rawId", "type", "authenticatorAttachment",
                                          "clientExtensionResults", "response"])
        XCTAssertEqual(object["id"] as? String, "-_8")
        XCTAssertEqual(object["rawId"] as? String, "-_8")
        XCTAssertEqual(object["type"] as? String, "public-key")
        XCTAssertEqual(object["authenticatorAttachment"] as? String, "platform")
        XCTAssertEqual((object["clientExtensionResults"] as? [String: Any])?.count, 0)
        let response = try XCTUnwrap(object["response"] as? [String: Any])
        XCTAssertEqual(Set(response.keys), ["clientDataJSON", "authenticatorData", "signature"])
        XCTAssertEqual(response["clientDataJSON"] as? String, "AQ")
        XCTAssertEqual(response["authenticatorData"] as? String, "Ag")
        XCTAssertEqual(response["signature"] as? String, "Aw")
    }

    func testAssertionResponseKeepsTheUserHandle() throws {
        let json = WebAuthnJSON.assertionResponse(
            credentialId: Data([1]), clientDataJSON: Data([1]), authenticatorData: Data([2]),
            signature: Data([3]), userHandle: Data("user-1".utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let response = try XCTUnwrap(object["response"] as? [String: Any])
        XCTAssertEqual(response["userHandle"] as? String, "dXNlci0x")
    }

    func testRegistrationResponseShape() throws {
        let json = WebAuthnJSON.registrationResponse(
            credentialId: Data([0xfb, 0xff]), clientDataJSON: Data([1]), attestationObject: Data([2]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "rawId", "type", "authenticatorAttachment",
                                          "clientExtensionResults", "response"])
        XCTAssertEqual(object["id"] as? String, "-_8")
        let response = try XCTUnwrap(object["response"] as? [String: Any])
        XCTAssertEqual(Set(response.keys), ["clientDataJSON", "attestationObject", "transports"])
        XCTAssertEqual(response["attestationObject"] as? String, "Ag")
        XCTAssertEqual(response["transports"] as? [String], ["internal", "hybrid"])
    }
}
