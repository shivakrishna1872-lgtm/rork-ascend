import SwiftUI

// MARK: - Cal AI food scan animation
//
// A subtle scanning grid that sweeps across the meal photo while the AI
// identifies foods and estimates portions. When no photo is present we
// fall back to a calorie-orbit motif.

// A premium replacement matching the IrisOrbit / ParticleBody style:
// the meal photo sits inside a hexagonal lattice with three orbiting macro
// tokens (P / C / F), a diagonal shimmer pass, and a soft scan beam. When
// no photo is present we show an orbital calorie motif on its own.

struct FoodScanAnimation: View {
    let image: UIImage?
    @State private var rotation: Double = 0
    @State private var shimmer: CGFloat = -1
    @State private var beam: CGFloat = -0.1
    @State private var pulse: Double = 0
    @State private var tokenPhase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // Outer pulse rings (concentric)
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(Theme.accentGlow.opacity(0.30), lineWidth: 1)
                        .scaleEffect(0.62 + pulse * (0.42 + Double(i) * 0.10))
                        .opacity(max(0, 1 - pulse) * 0.6)
                }

                // Counter-rotating arcs to mirror the PSL/Physique animations
                ForEach(0..<2) { i in
                    let dir: Double = i % 2 == 0 ? 1 : -1
                    Circle()
                        .trim(from: 0, to: i == 0 ? 0.32 : 0.20)
                        .stroke(
                            LinearGradient(
                                colors: [.clear, Theme.accentGlow, Theme.accent.opacity(0.9)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: .init(lineWidth: i == 0 ? 1.4 : 0.9, lineCap: .round)
                        )
                        .frame(width: size * (0.82 + Double(i) * 0.08),
                               height: size * (0.82 + Double(i) * 0.08))
                        .rotationEffect(.degrees(rotation * dir * (1 + Double(i) * 0.4)))
                }

                // Glass plate holding the photo
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Theme.surface)
                        .overlay {
                            if let image {
                                Image(uiImage: image)
                                    .resizable().aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            } else {
                                LinearGradient(colors: [Theme.surface, Theme.bg],
                                               startPoint: .top, endPoint: .bottom)
                                .overlay(
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: size * 0.18, weight: .bold))
                                        .foregroundStyle(Theme.accentGlow.opacity(0.9))
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(hexLattice.opacity(0.55))
                        .overlay(
                            // diagonal shimmer pass
                            GeometryReader { g in
                                LinearGradient(
                                    colors: [.clear, Color.white.opacity(0.32), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                .frame(width: g.size.width * 0.55)
                                .offset(x: g.size.width * shimmer)
                                .blendMode(.plusLighter)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .allowsHitTesting(false)
                        )
                        .overlay(
                            // soft horizontal scan beam
                            GeometryReader { g in
                                LinearGradient(
                                    colors: [.clear, Theme.accentGlow.opacity(0.75), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .frame(height: g.size.height * 0.18)
                                .offset(y: g.size.height * beam - g.size.height * 0.09)
                                .blendMode(.plusLighter)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .allowsHitTesting(false)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18).strokeBorder(
                                LinearGradient(
                                    colors: [Theme.accentGlow.opacity(0.9), Theme.accent.opacity(0.35)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                        )
                        .shadow(color: Theme.accent.opacity(0.3), radius: 16)
                }
                .frame(width: size * 0.66, height: size * 0.66)

                // Three orbiting macro tokens (P / C / F)
                ForEach(Array(macroTokens.enumerated()), id: \.offset) { i, token in
                    let angle = Double(i) / Double(macroTokens.count) * 360 + tokenPhase
                    let radius = size * 0.44
                    macroToken(letter: token.letter, tint: token.tint)
                        .offset(
                            x: cos(angle * .pi / 180) * radius,
                            y: sin(angle * .pi / 180) * radius
                        )
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 11).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) {
                shimmer = 1
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                beam = 1.0
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulse = 1
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                tokenPhase = 360
            }
        }
    }

    private var macroTokens: [(letter: String, tint: Color)] {
        [("P", Theme.elite), ("C", Theme.accentGlow), ("F", Theme.warn)]
    }

    private func macroToken(letter: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.65))
            Circle().strokeBorder(tint.opacity(0.8), lineWidth: 1)
            Text(letter)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
        .shadow(color: tint.opacity(0.6), radius: 5)
    }

    /// Subtle hexagonal detection lattice over the meal photo.
    private var hexLattice: some View {
        Canvas { ctx, size in
            let r: CGFloat = 14
            let dx = r * 1.5
            let dy = r * sqrt(3.0)
            var row = 0
            var y: CGFloat = -dy
            while y < size.height + dy {
                let offsetX: CGFloat = (row % 2 == 0) ? 0 : dx / 2 * 1.0
                var x: CGFloat = -dx + offsetX
                while x < size.width + dx {
                    var p = Path()
                    for i in 0..<6 {
                        let a = Double(i) * .pi / 3
                        let px = x + cos(a) * r
                        let py = y + sin(a) * r
                        if i == 0 { p.move(to: CGPoint(x: px, y: py)) }
                        else { p.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    p.closeSubpath()
                    ctx.stroke(p, with: .color(Theme.accentGlow.opacity(0.22)), lineWidth: 0.5)
                    x += dx * 1.5
                }
                y += dy
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Iris Orbit Scan (PSL analysis)
//
// A premium replacement for the old face mesh: the photo sits inside a soft
// glass orb. Three orbital arcs counter-rotate around it, a radial sonar
// sweeps outward in pulses, and tiny landmark sparks orbit the perimeter.

struct IrisOrbitScan: View {
    let image: UIImage?
    @State private var rotation: Double = 0
    @State private var sonar: CGFloat = 0
    @State private var shimmer: CGFloat = -1
    @State private var sparkPhase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // Outer sonar pulses
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(Theme.accentGlow.opacity(0.35), lineWidth: 1)
                        .scaleEffect(0.55 + sonar * (0.55 + Double(i) * 0.12))
                        .opacity(max(0, 1 - sonar) * 0.7)
                }

                // Three orbital arcs (counter-rotating)
                ForEach(0..<3) { i in
                    let trim = i == 0 ? 0.35 : (i == 1 ? 0.22 : 0.18)
                    let dir: Double = i % 2 == 0 ? 1 : -1
                    Circle()
                        .trim(from: 0, to: trim)
                        .stroke(
                            LinearGradient(
                                colors: [.clear, Theme.accentGlow, Theme.accent.opacity(0.9)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: .init(lineWidth: i == 0 ? 1.6 : 1.0, lineCap: .round)
                        )
                        .frame(width: size * (0.78 + Double(i) * 0.08),
                               height: size * (0.78 + Double(i) * 0.08))
                        .rotationEffect(.degrees(rotation * dir * (1 + Double(i) * 0.35)))
                        .blur(radius: i == 2 ? 0.6 : 0)
                }

                // Glass portrait orb
                Circle()
                    .fill(Theme.surface)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable().aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        } else {
                            LinearGradient(colors: [Theme.surface, Theme.bg],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .clipShape(Circle())
                    .overlay(
                        // Diagonal shimmer band sweeping across the portrait
                        GeometryReader { g in
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.35), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            .frame(width: g.size.width * 0.55)
                            .offset(x: g.size.width * shimmer)
                            .blendMode(.plusLighter)
                        }
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [Theme.accentGlow.opacity(0.9), Theme.accent.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                    )
                    .shadow(color: Theme.accent.opacity(0.35), radius: 18)

                // Orbiting landmark sparks
                ForEach(0..<8) { i in
                    let angle = Double(i) / 8.0 * 360 + sparkPhase
                    let radius = size * 0.42
                    Circle()
                        .fill(Theme.accentGlow)
                        .frame(width: 4, height: 4)
                        .shadow(color: Theme.accentGlow.opacity(0.9), radius: 4)
                        .offset(
                            x: cos(angle * .pi / 180) * radius,
                            y: sin(angle * .pi / 180) * radius
                        )
                        .opacity(0.55 + 0.45 * abs(sin(angle * .pi / 180)))
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                sonar = 1
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) {
                shimmer = 1
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                sparkPhase = 360
            }
        }
    }
}

// MARK: - Particle Body Scan (Physique analysis)
//
// A cloud of points that drifts and slowly resolves into a body silhouette.
// A horizontal scan beam sweeps top-to-bottom with a soft afterglow, and a
// vertical center axis pulses to suggest spinal alignment.

struct ParticleBodyScan: View {
    @State private var resolve: Double = 0
    @State private var beam: CGFloat = -0.1
    @State private var drift: Double = 0
    @State private var axisPulse: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Deterministic landmark grid — 16 anchor points roughly outlining a body.
    private static let anchors: [CGPoint] = [
        // Head + neck
        CGPoint(x: 0.50, y: 0.06),
        CGPoint(x: 0.50, y: 0.13),
        // Shoulders
        CGPoint(x: 0.32, y: 0.20),
        CGPoint(x: 0.68, y: 0.20),
        // Chest
        CGPoint(x: 0.42, y: 0.30),
        CGPoint(x: 0.58, y: 0.30),
        // Elbows
        CGPoint(x: 0.22, y: 0.36),
        CGPoint(x: 0.78, y: 0.36),
        // Waist
        CGPoint(x: 0.44, y: 0.48),
        CGPoint(x: 0.56, y: 0.48),
        // Hips
        CGPoint(x: 0.38, y: 0.58),
        CGPoint(x: 0.62, y: 0.58),
        // Knees
        CGPoint(x: 0.40, y: 0.76),
        CGPoint(x: 0.60, y: 0.76),
        // Ankles
        CGPoint(x: 0.42, y: 0.95),
        CGPoint(x: 0.58, y: 0.95)
    ]

    private static let cloud: [(CGPoint, Double)] = {
        var rng = SystemRandomNumberGenerator()
        var out: [(CGPoint, Double)] = []
        for _ in 0..<60 {
            let x = Double.random(in: 0.15...0.85, using: &rng)
            let y = Double.random(in: 0.05...0.98, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
            out.append((CGPoint(x: x, y: y), phase))
        }
        return out
    }()

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // Vertical center axis (alignment guide)
            let axisAlpha = 0.18 + 0.18 * (sin(axisPulse) * 0.5 + 0.5)
            var axis = Path()
            axis.move(to: CGPoint(x: w * 0.5, y: 0))
            axis.addLine(to: CGPoint(x: w * 0.5, y: h))
            ctx.stroke(axis, with: .color(Theme.accent.opacity(axisAlpha)), lineWidth: 0.6)

            // Drifting noise cloud (low-opacity — the "unresolved" data)
            for (p, phase) in Self.cloud {
                let dx = sin(drift + phase) * 0.012
                let dy = cos(drift * 0.8 + phase) * 0.010
                let cx = (p.x + dx) * w
                let cy = (p.y + dy) * h
                let alpha = (1 - resolve) * 0.55
                let r: CGFloat = 1.3
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .color(Theme.accentGlow.opacity(alpha))
                )
            }

            // Resolved landmark nodes + connecting bones (fade in with `resolve`)
            let edges: [(Int, Int)] = [
                (0,1),(1,2),(1,3),
                (2,4),(3,5),(4,5),
                (2,6),(3,7),
                (4,8),(5,9),(8,9),
                (8,10),(9,11),(10,11),
                (10,12),(11,13),(12,14),(13,15)
            ]
            for (a, b) in edges {
                let pa = Self.anchors[a]
                let pb = Self.anchors[b]
                var line = Path()
                line.move(to: CGPoint(x: pa.x * w, y: pa.y * h))
                line.addLine(to: CGPoint(x: pb.x * w, y: pb.y * h))
                ctx.stroke(line, with: .color(Theme.accentGlow.opacity(resolve * 0.65)),
                           lineWidth: 1.2)
            }
            for p in Self.anchors {
                let cx = p.x * w, cy = p.y * h
                let core: CGFloat = 2.4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - core, y: cy - core, width: core * 2, height: core * 2)),
                    with: .color(Theme.accent.opacity(0.4 + 0.6 * resolve))
                )
                let halo: CGFloat = 5.2
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cx - halo, y: cy - halo, width: halo * 2, height: halo * 2)),
                    with: .color(Theme.accentGlow.opacity(resolve * 0.45)),
                    lineWidth: 0.6
                )
            }

            // Horizontal scan beam with afterglow
            let beamY = beam * h
            let glowRect = CGRect(x: 0, y: beamY - 36, width: w, height: 72)
            ctx.fill(
                Path(glowRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Theme.accentGlow.opacity(0),
                        Theme.accentGlow.opacity(0.35),
                        Theme.accentGlow.opacity(0)
                    ]),
                    startPoint: CGPoint(x: 0, y: glowRect.minY),
                    endPoint: CGPoint(x: 0, y: glowRect.maxY)
                )
            )
            var beamPath = Path()
            beamPath.move(to: CGPoint(x: 0, y: beamY))
            beamPath.addLine(to: CGPoint(x: w, y: beamY))
            ctx.stroke(beamPath, with: .color(Theme.accentGlow), lineWidth: 1.4)
        }
        .onAppear {
            guard !reduceMotion else { resolve = 1; beam = 0.5; return }
            withAnimation(.easeOut(duration: 2.4)) { resolve = 1 }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                beam = 1.0
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                drift = .pi * 2
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                axisPulse = .pi
            }
        }
    }
}

// MARK: - Face mesh sweep — (legacy, kept for reference)
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
