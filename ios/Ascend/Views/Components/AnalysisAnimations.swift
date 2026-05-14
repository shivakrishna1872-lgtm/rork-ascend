import SwiftUI

// MARK: - Cal AI food scan animation
//
// A subtle scanning grid that sweeps across the meal photo while the AI
// identifies foods and estimates portions. When no photo is present we
// fall back to a calorie-orbit motif.

struct FoodScanAnimation: View {
    let image: UIImage?
    @State private var sweep: CGFloat = -1
    @State private var pulse: Double = 0
    @State private var spin: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let image {
                Color.black.opacity(0.45)
                    .overlay {
                        Image(uiImage: image)
                            .resizable().aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay { scanGrid }
                    .overlay {
                        // Detection chips appearing one after another
                        VStack {
                            HStack {
                                detectionChip(label: "FOODS", x: 0.10, y: 0.18)
                                Spacer()
                            }
                            Spacer()
                            HStack {
                                Spacer()
                                detectionChip(label: "PORTION", x: 0.78, y: 0.78)
                            }
                        }
                        .padding(10)
                    }
                    .clipShape(.rect(cornerRadius: 16))
            } else {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.accentGlow.opacity(0.5), lineWidth: 1)
                        .frame(width: 70, height: 70)
                        .scaleEffect(1 + CGFloat(pulse) * 0.06)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.accentGlow)
                        .rotationEffect(.degrees(spin * 0.2))
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                sweep = 1.2
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = 1
            }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                spin = 360
            }
        }
    }

    private var scanGrid: some View {
        GeometryReader { geo in
            ZStack {
                // Subtle grid
                Canvas { ctx, size in
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(Theme.accentGlow.opacity(0.18)), lineWidth: 0.5)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(Theme.accentGlow.opacity(0.18)), lineWidth: 0.5)
                        y += step
                    }
                }
                // Sweep beam
                LinearGradient(
                    colors: [.clear, Theme.accentGlow.opacity(0.9), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.25)
                .offset(y: geo.size.height * sweep)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
        }
    }

    private func detectionChip(label: String, x: CGFloat, y: CGFloat) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.good).frame(width: 5, height: 5)
                .shadow(color: Theme.good.opacity(0.8), radius: 4)
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.65)))
        .overlay(Capsule().strokeBorder(Theme.accentGlow.opacity(0.6), lineWidth: 0.5))
        .opacity(0.85 + 0.15 * pulse)
    }
}

// MARK: - Face mesh sweep — used during PSL analysis
//
// Lays a soft triangular face mesh over the user's portrait and traces a
// horizontal beam across it for an analytical, premium feel.

struct FaceMeshSweep: View {
    let image: UIImage?
    @State private var sweepY: CGFloat = -1
    @State private var meshOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Portrait
            if let image {
                Image(uiImage: image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            } else {
                LinearGradient(colors: [Theme.surface, Theme.bg],
                               startPoint: .top, endPoint: .bottom)
            }

            // Triangular face mesh
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cx = w * 0.5
                let nodes: [CGPoint] = [
                    CGPoint(x: cx, y: h * 0.18),                        // forehead top
                    CGPoint(x: cx - w*0.18, y: h * 0.30),                // temple L
                    CGPoint(x: cx + w*0.18, y: h * 0.30),                // temple R
                    CGPoint(x: cx - w*0.12, y: h * 0.42),                // brow L
                    CGPoint(x: cx + w*0.12, y: h * 0.42),                // brow R
                    CGPoint(x: cx - w*0.10, y: h * 0.50),                // eye L
                    CGPoint(x: cx + w*0.10, y: h * 0.50),                // eye R
                    CGPoint(x: cx, y: h * 0.58),                         // nose
                    CGPoint(x: cx - w*0.14, y: h * 0.66),                // cheek L
                    CGPoint(x: cx + w*0.14, y: h * 0.66),                // cheek R
                    CGPoint(x: cx, y: h * 0.72),                         // mouth
                    CGPoint(x: cx - w*0.12, y: h * 0.84),                // jaw L
                    CGPoint(x: cx + w*0.12, y: h * 0.84),                // jaw R
                    CGPoint(x: cx, y: h * 0.92)                          // chin
                ]
                // Connect a sparse triangle network
                let edges: [(Int, Int)] = [
                    (0,1),(0,2),(1,2),(1,3),(2,4),(3,4),
                    (3,5),(4,6),(5,6),(5,7),(6,7),
                    (5,8),(6,9),(7,8),(7,9),(8,9),
                    (8,10),(9,10),(8,11),(9,12),(10,11),(10,12),
                    (11,13),(12,13)
                ]
                for (a, b) in edges {
                    var p = Path()
                    p.move(to: nodes[a]); p.addLine(to: nodes[b])
                    ctx.stroke(p, with: .color(Theme.accentGlow.opacity(0.55)), lineWidth: 0.7)
                }
                for n in nodes {
                    let r: CGFloat = 2
                    ctx.fill(Path(ellipseIn: CGRect(x: n.x - r, y: n.y - r, width: r*2, height: r*2)),
                             with: .color(Theme.accentGlow))
                }
            }
            .opacity(meshOpacity)

            // Sweep
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Theme.accentGlow.opacity(0.95), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 2)
                    .blur(radius: 1)
                    .offset(y: geo.size.height * sweepY)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                meshOpacity = 1
                return
            }
            withAnimation(.easeOut(duration: 0.6)) { meshOpacity = 1 }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                sweepY = 1
            }
        }
    }
}

// MARK: - Skeleton trace — used during Physique analysis
//
// Draws an animated stick-figure that traces its limbs sequentially, giving
// a sense that the AI is "wiring up" the body's landmarks.

struct SkeletonTrace: View {
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w * 0.5
            let head = CGPoint(x: cx, y: h * 0.12)
            let neck = CGPoint(x: cx, y: h * 0.22)
            let shL = CGPoint(x: cx - w*0.20, y: h * 0.28)
            let shR = CGPoint(x: cx + w*0.20, y: h * 0.28)
            let elL = CGPoint(x: cx - w*0.30, y: h * 0.46)
            let elR = CGPoint(x: cx + w*0.30, y: h * 0.46)
            let wrL = CGPoint(x: cx - w*0.34, y: h * 0.62)
            let wrR = CGPoint(x: cx + w*0.34, y: h * 0.62)
            let hpL = CGPoint(x: cx - w*0.14, y: h * 0.58)
            let hpR = CGPoint(x: cx + w*0.14, y: h * 0.58)
            let knL = CGPoint(x: cx - w*0.16, y: h * 0.78)
            let knR = CGPoint(x: cx + w*0.16, y: h * 0.78)
            let anL = CGPoint(x: cx - w*0.18, y: h * 0.96)
            let anR = CGPoint(x: cx + w*0.18, y: h * 0.96)

            let limbs: [[CGPoint]] = [
                [neck, shL, elL, wrL],
                [neck, shR, elR, wrR],
                [neck, hpL, knL, anL],
                [neck, hpR, knR, anR],
                [shL, shR],
                [hpL, hpR]
            ]
            // Head
            let r: CGFloat = h * 0.06
            ctx.stroke(
                Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r*2, height: r*2)),
                with: .color(Theme.accentGlow.opacity(0.9)),
                lineWidth: 1.4
            )

            // Animated limb trace
            let total = limbs.reduce(0) { $0 + $1.count - 1 }
            let progressEdges = Double(total) * progress
            var drawn = 0.0
            for chain in limbs {
                for i in 0..<(chain.count - 1) {
                    let remaining = progressEdges - drawn
                    if remaining <= 0 { return }
                    let a = chain[i], b = chain[i+1]
                    let t = min(1.0, remaining)
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: CGPoint(
                        x: a.x + (b.x - a.x) * t,
                        y: a.y + (b.y - a.y) * t
                    ))
                    ctx.stroke(p, with: .color(Theme.accentGlow.opacity(0.85)), lineWidth: 1.6)
                    // joints
                    let jr: CGFloat = 3
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - jr, y: a.y - jr, width: jr*2, height: jr*2)),
                             with: .color(Theme.accent))
                    drawn += 1
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { progress = 1; return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                progress = 1
            }
        }
    }
}
