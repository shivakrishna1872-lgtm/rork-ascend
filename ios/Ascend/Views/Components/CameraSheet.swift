import SwiftUI
import UIKit

/// Wraps UIImagePickerController so we can take a live photo from inside the app.
/// On the cloud simulator the camera is not available — call `CameraSheet.isAvailable`
/// before presenting and show the placeholder card instead.
///
/// Front-camera selfies are saved un-mirrored (matching how the lens actually
/// sees you, the same way the Photos app stores selfies) so analysis isn't
/// thrown off by the preview's mirror flip.
struct CameraSheet: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    var preferFront: Bool = false

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        if preferFront, UIImagePickerController.isCameraDeviceAvailable(.front) {
            p.cameraDevice = .front
        }
        p.allowsEditing = false
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void
        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let raw = info[.originalImage] as? UIImage
            let processed: UIImage? = raw?.normalizedOrientation()
            DispatchQueue.main.async { [onCapture, onCancel] in
                if let processed { onCapture(processed) } else { onCancel() }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async { [onCancel] in onCancel() }
        }
    }
}

extension UIImage {
    /// Re-renders the image with the .up orientation baked into the pixels.
    nonisolated func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Mirrors the image left-to-right (used for front-camera captures so the saved
    /// photo matches the mirrored preview the user just saw).
    nonisolated func horizontallyFlipped() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: size.width, y: 0)
            c.scaleBy(x: -1, y: 1)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Friendly sheet used when the camera can't be opened — either because the
/// hardware is missing (cloud simulator) or the user previously denied access.
struct CameraUnavailableSheet: View {
    enum Reason { case unavailable, denied }
    var reason: Reason = .unavailable
    /// Optional callback wired by the host screen to open its photo picker once
    /// the user dismisses the sheet, so the unavailable state isn't a dead end.
    var onUseLibrary: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: reason == .denied ? "lock.shield" : "iphone.gen3.badge.exclamationmark")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.accentGlow)
                    .ambientFloat(amplitude: 3, duration: 3.4)
                Text(reason == .denied ? "Camera access needed" : "Live camera unavailable here")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(reason == .denied
                     ? "Enable camera access for Ascend Life in Settings to capture live photos. You can still upload from your library here."
                     : "You're previewing Ascend Life on the cloud simulator, which has no camera hardware. Install the build on your iPhone (via the Rork app or TestFlight) to take photos live — or upload one from your library now.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
                VStack(spacing: 10) {
                    if reason == .denied {
                        PrimaryButton(title: "Open Settings", icon: "gearshape") {
                            CameraPermission.openSettings()
                            dismiss()
                        }
                        if onUseLibrary != nil {
                            GhostButton(title: "Upload from Library", icon: "photo.on.rectangle.angled") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onUseLibrary?() }
                            }
                        } else {
                            GhostButton(title: "Not now", icon: "xmark") { dismiss() }
                        }
                    } else {
                        if onUseLibrary != nil {
                            PrimaryButton(title: "Upload from Library", icon: "photo.on.rectangle.angled") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onUseLibrary?() }
                            }
                            GhostButton(title: "Got it", icon: "checkmark") { dismiss() }
                        } else {
                            PrimaryButton(title: "OK", icon: "checkmark") { dismiss() }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Reusable trigger

/// Centralized helper that handles the four-way permission state machine for
/// every "Take Photo" button across the app. Consumers wire up two state
/// flags (camera + access-sheet) and an enum for which reason to show.
struct CameraAccessTrigger {
    var onAuthorized: () -> Void
    var onDenied: () -> Void
    var onUnavailable: () -> Void

    @MainActor
    func fire() {
        let state = CameraPermission.currentState()
        switch state {
        case .ready:
            onAuthorized()
        case .needsRequest:
            Task { @MainActor in
                let resolved = await CameraPermission.request()
                switch resolved {
                case .ready: onAuthorized()
                case .denied: onDenied()
                case .unavailable: onUnavailable()
                case .needsRequest: onDenied()
                }
            }
        case .denied:
            onDenied()
        case .unavailable:
            onUnavailable()
        }
    }
}
