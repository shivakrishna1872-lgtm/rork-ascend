import SwiftUI

/// Lightweight pre-analysis photo editor. Lets the user reposition / zoom /
/// rotate / align an image inside a portrait crop frame before the physique
/// pipeline sees it. Output is rendered at 1024px on the long edge so Vision
/// has plenty of pixels to work with.
struct PhotoAdjustView: View {
    let image: UIImage
    let angle: ScanAngle
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    @State private var showSilhouette: Bool = true

    private let cropAspect: CGFloat = 3.0 / 4.0  // portrait

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                GeometryReader { geo in
                    let frame = cropFrame(in: geo.size)
                    ZStack {
                        // Image canvas (pannable / zoomable / rotatable)
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .rotationEffect(rotation)
                            .offset(offset)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        // Dim outside crop, clear inside
                        cropMask(in: geo.size, frame: frame)
                            .allowsHitTesting(false)

                        // Crop frame border + body silhouette overlay
                        cropOverlay(frame: frame)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(combinedGesture)
                }
                .padding(.horizontal, 8)

                controls
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            Spacer()
            Text("Adjust \(angle.title)".uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(2)
                .foregroundStyle(.white)
            Spacer()
            Button {
                Haptics.success()
                onConfirm(renderCropped())
            } label: {
                Text("Use")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(Capsule().fill(.white))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                controlButton("rotate.left", "Rotate L") {
                    withAnimation(.spring) { rotation -= .degrees(90); lastRotation = rotation }
                    Haptics.soft()
                }
                controlButton("rotate.right", "Rotate R") {
                    withAnimation(.spring) { rotation += .degrees(90); lastRotation = rotation }
                    Haptics.soft()
                }
                controlButton("arrow.up.left.and.down.right.magnifyingglass", "Fit") {
                    withAnimation(.spring) {
                        scale = 1; lastScale = 1
                        offset = .zero; lastOffset = .zero
                        rotation = .zero; lastRotation = .zero
                    }
                    Haptics.soft()
                }
                controlButton(showSilhouette ? "figure.stand" : "figure.stand.dotted",
                              showSilhouette ? "Hide guide" : "Show guide") {
                    withAnimation { showSilhouette.toggle() }
                }
            }

            // Zoom slider
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                Slider(value: $scale, in: 0.5...3.5)
                    .tint(.white)
                    .onChange(of: scale) { _, v in lastScale = v }
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)

            Text("Drag to reposition · Pinch to zoom · Twist to rotate")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.001))
    }

    private func controlButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Crop overlay

    private func cropFrame(in size: CGSize) -> CGRect {
        let maxW = size.width - 24
        let maxH = size.height - 24
        var w = maxW
        var h = w / cropAspect
        if h > maxH { h = maxH; w = h * cropAspect }
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func cropMask(in size: CGSize, frame: CGRect) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .mask {
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                }
        }
    }

    private func cropOverlay(frame: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.4)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Rule-of-thirds grid
            Canvas { ctx, _ in
                let inset: CGFloat = 0
                let r = CGRect(x: frame.minX + inset, y: frame.minY + inset,
                               width: frame.width - inset * 2, height: frame.height - inset * 2)
                for i in 1...2 {
                    let x = r.minX + r.width * CGFloat(i) / 3
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: r.minY))
                    p.addLine(to: CGPoint(x: x, y: r.maxY))
                    ctx.stroke(p, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
                    let y = r.minY + r.height * CGFloat(i) / 3
                    var q = Path()
                    q.move(to: CGPoint(x: r.minX, y: y))
                    q.addLine(to: CGPoint(x: r.maxX, y: y))
                    ctx.stroke(q, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)

            // Body silhouette guide
            if showSilhouette {
                Image(systemName: angle == .front ? "figure.stand"
                      : angle == .side ? "figure"
                      : "figure.stand.line.dotted.figure.stand")
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.opacity(0.18))
                    .frame(height: frame.height * 0.88)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    // MARK: - Gestures

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width,
                                height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in lastOffset = offset }

        let zoom = MagnifyGesture()
            .onChanged { v in
                scale = max(0.4, min(4.0, lastScale * v.magnification))
            }
            .onEnded { _ in lastScale = scale }

        let rotate = RotateGesture()
            .onChanged { v in rotation = lastRotation + v.rotation }
            .onEnded { _ in lastRotation = rotation }

        return drag.simultaneously(with: zoom).simultaneously(with: rotate)
    }

    // MARK: - Render

    /// Compose the current image with the user's transform and crop to the
    /// frame's aspect ratio. Output is 1024px on the long edge so Vision has
    /// enough resolution to detect landmarks reliably.
    private func renderCropped() -> UIImage {
        let outH: CGFloat = 1024
        let outW: CGFloat = outH * cropAspect
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH))
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))

            // We replicate the same transform stack the SwiftUI view uses
            // (scale → rotate → translate, centered on the crop frame), but
            // on the output canvas. Image is drawn at its natural aspect.
            let imgSize = image.size
            let fitScale = min(outW / imgSize.width, outH / imgSize.height)
            let drawSize = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)

            // Map screen offset to output coordinates (screen frame height ≈ outH).
            // Heuristic: SwiftUI frame height when displayed roughly equals outH
            // so a 1:1 mapping works well in practice for portrait scans.
            let cg = ctx.cgContext
            cg.translateBy(x: outW / 2 + offset.width, y: outH / 2 + offset.height)
            cg.rotate(by: CGFloat(rotation.radians))
            cg.scaleBy(x: scale, y: scale)

            let drawRect = CGRect(
                x: -drawSize.width / 2,
                y: -drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
        }
    }
}

struct AdjustWrap: Identifiable {
    let id = UUID()
    let image: UIImage
}
