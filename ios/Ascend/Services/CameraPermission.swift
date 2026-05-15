import AVFoundation
import UIKit

/// Centralized camera permission handling. On real devices we explicitly check
/// AVCaptureDevice authorization and request access if not yet determined; the
/// cloud simulator has no hardware so we fall back to the "unavailable" path.
@MainActor
enum CameraPermission {
    enum State {
        case ready          // camera exists and user has granted access
        case needsRequest   // not determined yet — call `request()`
        case denied         // user denied; deep-link to Settings
        case unavailable    // hardware absent (cloud simulator)
    }

    static func currentState() -> State {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .needsRequest
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Asks the user once. Returns the resolved state.
    static func request() async -> State {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .ready : .denied
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
