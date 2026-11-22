import Foundation

/// What the camera permission allows, from `AVAuthorizationStatus`'s raw value: the QR scanner
/// (Runner/Scanner) asks the system only when the answer is `ask`, and never reaches the camera when
/// it is `denied`.
public enum CameraAccess {
    /// `granted` (authorized, 3), `ask` (not determined, 0: the system prompt is still to come) or
    /// `denied` (denied, 2, or restricted, 1: no prompt can change it; and any status this does not
    /// know, which is never taken for a yes).
    public static func state(_ status: Int) -> String {
        switch status {
        case 3: return "granted"
        case 0: return "ask"
        default: return "denied"
        }
    }
}
