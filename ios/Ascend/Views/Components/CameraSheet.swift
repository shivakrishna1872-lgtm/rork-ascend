import SwiftUI
import UIKit

/// Wraps UIImagePickerController so we can take a live photo from inside the app.
/// On the cloud simulator the camera is not available — call `CameraSheet.isAvailable`
/// before presenting and show the placeholder card instead.
///
/// Front-camera selfies are mirrored on capture so the saved image matches the
/// live preview the user just saw (this is the natural feel users expect).
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
            let isFront = picker.cameraDevice == .front
            let processed: UIImage? = {
                guard let raw else { return nil }
                let oriented = raw.normalizedOrientation()
                return isFront ? oriented.horizontallyFlipped() : oriented
            }()
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
                Text("Install Ascend Life on your device via the Rork App to capture live photos. You can still upload from the library here.")
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
