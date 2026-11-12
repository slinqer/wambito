import XCTest
@testable import WambitoNative

final class WebAuthnJSONPrfTests: XCTestCase {
    // PRF_SALT (packages/crypto) in base64url: SHA-256("wambito/v1/prf").
    private let saltB64 = "mZ0R_U0yE9CNbSH9Hgj6Zjsy9sIcTWA3QBVGG_z9vts"

    private var assertionJSON: String {
        """
        {"challenge":"AQIDBA","rpId":"app.wambito.com",\
        "extensions":{"prf":{"eval":{"first":"\(saltB64)"}}}}
        """
    }

    private var registrationJSON: String {
        """
        {"challenge":"AQIDBA","rp":{"id":"app.wambito.com","name":"Wambito"},\
        "user":{"id":"dXNlci0x","name":"ana@example.com"},\
        "extensions":{"prf":{"eval":{"first":"\(saltB64)"}}}}
        """
    }

    func testPrfInputIsParsed() throws {
        let salt = WebAuthnJSON.fromBase64url(saltB64)
        XCTAssertEqual(salt?.count, 32)
        XCTAssertEqual(try WebAuthnJSON.parseAssertion(assertionJSON).prfInput, salt)
        XCTAssertEqual(try WebAuthnJSON.parseRegistration(registrationJSON).prfInput, salt)
    }

    func testNoPrfInputWhenTheRequestHasNone() throws {
        XCTAssertNil(try WebAuthnJSON.parseAssertion(#"{"challenge":"AQIDBA","rpId":"app.wambito.com"}"#).prfInput)
        XCTAssertNil(try WebAuthnJSON.parseAssertion(
            #"{"challenge":"AQIDBA","rpId":"a.com","extensions":{"prf":{}}}"#).prfInput)
    }

    func testPrfOutputIsWritten() throws {
        let output = Data((0..<32).map { UInt8($0) })
        let json = WebAuthnJSON.assertionResponse(
            credentialId: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
            signature: Data([4]), userHandle: nil, prfOutput: output)
        let results = try clientExtensionResults(json)
        let first = ((results["prf"] as? [String: Any])?["results"] as? [String: Any])?["first"] as? String
        XCTAssertEqual(first, WebAuthnJSON.base64url(output))
    }

    func testNoOutputLeavesTheResultsEmpty() throws {
        let assertion = WebAuthnJSON.assertionResponse(
            credentialId: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
            signature: Data([4]), userHandle: nil)
        XCTAssertTrue(try clientExtensionResults(assertion).isEmpty)
        let registration = WebAuthnJSON.registrationResponse(
            credentialId: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]))
        XCTAssertTrue(try clientExtensionResults(registration).isEmpty)
    }

    func testRegistrationSaysPrfIsEnabledWithoutResults() throws {
        let json = WebAuthnJSON.registrationResponse(
            credentialId: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]),
            prfEnabled: true)
        let prf = try clientExtensionResults(json)["prf"] as? [String: Any]
        XCTAssertEqual(prf?["enabled"] as? Bool, true)
        XCTAssertNil(prf?["results"])
    }

    func testRegistrationWritesTheOutputToo() throws {
        let output = Data(repeating: 9, count: 32)
        let json = WebAuthnJSON.registrationResponse(
            credentialId: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]),
            prfEnabled: true, prfOutput: output)
        let prf = try clientExtensionResults(json)["prf"] as? [String: Any]
        XCTAssertEqual(prf?["enabled"] as? Bool, true)
        XCTAssertEqual((prf?["results"] as? [String: Any])?["first"] as? String, WebAuthnJSON.base64url(output))
    }

    private func clientExtensionResults(_ json: String) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try XCTUnwrap(object["clientExtensionResults"] as? [String: Any])
    }
}
