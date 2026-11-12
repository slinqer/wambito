import AuthenticationServices
import Flutter
import UIKit
import WambitoNative

/// Passkeys through the system's AuthenticationServices, on the `wambito/passkeys` channel
/// (lib/api/passkeys.dart), as on Android (PasskeyChannel.kt): the same methods, the same JSON in
/// and out. The system sheet offers the passkeys of iCloud Keychain and of the person's password
/// manager. The app's associated domain `webcredentials:app.wambito.com` ties it to the server's
/// `/.well-known/apple-app-site-association`.
///
///  * `isSupported` -> true (iOS 16, this app's minimum, has passkeys).
///  * `get(optionsJson)` -> the assertion as JSON.
///  * `getAvailable(optionsJson)` -> the same, but only for a passkey the phone can offer at once:
///    with none, the system shows nothing and the call ends as `cancelled`.
///  * `create(optionsJson)` -> the attestation as JSON.
///
/// Failures: `failed` (no or unreadable options, anything the system reports), `cancelled` (the
/// person closed the sheet). `unsupported` is never answered here. One ceremony runs at a time: a
/// second call while one is up answers `failed`.
final class PasskeyChannel: NSObject {
  private let channel: FlutterMethodChannel
  /// Kept while a sheet is up: the controller holds its delegate weakly.
  private var session: Session?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "wambito/passkeys", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "isSupported": result(true)
      case "get": self.run(call, result) { try self.assertion($0, immediate: false) }
      case "getAvailable": self.run(call, result) { try self.assertion($0, immediate: true) }
      case "create": self.run(call, result) { try self.registration($0) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func run(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult,
    _ build: (String) throws -> (ASAuthorizationController, Bool)
  ) {
    guard let json = call.arguments as? String else {
      return result(FlutterError(code: "failed", message: "Missing WebAuthn options", details: nil))
    }
    guard session == nil else {
      return result(FlutterError(code: "failed", message: "A passkey prompt is already open", details: nil))
    }
    do {
      let (controller, immediate) = try build(json)
      let session = Session(result: result) { [weak self] in self?.session = nil }
      self.session = session
      controller.delegate = session
      controller.presentationContextProvider = session
      if immediate {
        controller.performRequests(options: .preferImmediatelyAvailableCredentials)
      } else {
        controller.performRequests()
      }
    } catch {
      result(FlutterError(code: "failed", message: "Unreadable WebAuthn options", details: nil))
    }
  }

  private func assertion(_ json: String, immediate: Bool) throws -> (ASAuthorizationController, Bool) {
    let options = try WebAuthnJSON.parseAssertion(json)
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
    let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
    request.allowedCredentials = options.allowCredentialIds.map {
      ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
    }
    if let preference = options.userVerification {
      request.userVerificationPreference = .init(rawValue: preference)
    }
    return (ASAuthorizationController(authorizationRequests: [request]), immediate)
  }

  private func registration(_ json: String) throws -> (ASAuthorizationController, Bool) {
    let options = try WebAuthnJSON.parseRegistration(json)
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
    let request = provider.createCredentialRegistrationRequest(
      challenge: options.challenge, name: options.userName, userID: options.userId)
    request.userVerificationPreference = .init(rawValue: options.userVerification)
    request.attestationPreference = .init(rawValue: options.attestation)
    if #available(iOS 17.4, *) {
      request.excludedCredentials = options.excludeCredentialIds.map {
        ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
      }
    }
    return (ASAuthorizationController(authorizationRequests: [request]), false)
  }

  /// One ceremony: answers the call exactly once, then lets the channel forget it.
  private final class Session: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    private var result: FlutterResult?
    private let done: () -> Void

    init(result: @escaping FlutterResult, done: @escaping () -> Void) {
      self.result = result
      self.done = done
    }

    private func finish(_ answer: Any?) {
      result?(answer)
      result = nil
      done()
    }

    func authorizationController(
      controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      switch authorization.credential {
      case let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion:
        finish(WebAuthnJSON.assertionResponse(
          credentialId: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
          authenticatorData: credential.rawAuthenticatorData, signature: credential.signature,
          userHandle: credential.userID))
      case let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration:
        guard let attestation = credential.rawAttestationObject else {
          return finish(FlutterError(code: "failed", message: "No attestation", details: nil))
        }
        finish(WebAuthnJSON.registrationResponse(
          credentialId: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
          attestationObject: attestation))
      default:
        finish(FlutterError(code: "failed", message: "Not a passkey", details: nil))
      }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
      if (error as? ASAuthorizationError)?.code == .canceled {
        finish(FlutterError(code: "cancelled", message: error.localizedDescription, details: nil))
      } else {
        finish(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }
    }

    /// The key window of the active window scene (the app runs on a UIScene).
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
      return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? ASPresentationAnchor()
    }
  }
}
