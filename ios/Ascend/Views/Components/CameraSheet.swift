import SwiftUI
import UIKit

/// Wraps UIImagePickerController so we can take a live photo from inside the app.
/// On the cloud simulator the camera is not available — call `CameraSheet.isAvailable`
/// before presenting and show the placeholder card instead.
struct CameraSheet: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

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
            let img = info[.originalImage] as? UIImage
            DispatchQueue.main.async { [onCapture, onCancel] in
                if let img { onCapture(img) } else { onCancel() }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async { [onCancel] in onCancel() }
        }
    }
}

/// Friendly placeholder used when the device has no camera (e.g. the Rork cloud simulator).
struct CameraUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.accentGlow)
                    .ambientFloat(amplitude: 3, duration: 3.4)
                Text("Camera unavailable")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                Text("Install this app on your device via the Rork App to capture live photos. You can still upload from the library here.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
                PrimaryButton(title: "OK", icon: "checkmark") { dismiss() }
                    .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }
}
