import SwiftUI

/// Small living illustrations for the feature pages (native Canvas, no animation runtime): one loop each, a
/// parallax that follows the pointer, and a click that replays the loop. Reduce Motion and snapshots draw the settled pose.
struct Illustration: View {
    enum Kind { case sorting, renaming, duplicates, tagging, eject }
    var kind: Kind
    var tint: Tint
    @State private var origin = Date()
    @State private var mouse = CGSize.zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Motion.reduced || Motion.snapshot)) { ctx in
            let t = Motion.reduced || Motion.snapshot ? 3.2 : ctx.date.timeIntervalSince(origin)
            Canvas { g, size in
                Art(g: g, size: size, t: t, tint: tint, mouse: mouse).draw(kind)
            }
        }
        .frame(width: 112, height: 92)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): withAnimation(.easeOut(duration: 0.2)) { mouse = CGSize(width: (p.x / 112 - 0.5) * 2, height: (p.y / 92 - 0.5) * 2) }
            case .ended: withAnimation(.easeOut(duration: 0.4)) { mouse = .zero }
            }
        }
        .onTapGesture { origin = Date() }
        .help("Click to replay")
        .accessibilityHidden(true)
    }
}

private struct Art {
    var g: GraphicsContext
    var size: CGSize
    var t: Double
    var tint: Tint
    var mouse: CGSize

    var ink: Color { tint.fg }
    var soft: Color { tint.fg.opacity(0.16) }
    var paper: Color { K.card }
    func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    func seg(_ p: Double, _ a: Double, _ b: Double) -> Double { ease((p - a) / (b - a)) }
    /// Depth 0 stays put, 1 follows the pointer by up to 5 pt.
    func par(_ d: Double) -> CGSize { CGSize(width: mouse.width * 5 * d, height: mouse.height * 3 * d) }

    func sheet(_ x: Double, _ y: Double, w: Double = 30, h: Double = 38, rot: Double = 0, alpha: Double = 1, lines: Int = 3, fill: Color? = nil, depth: Double = 0.5) {
        var c = g
        c.opacity = alpha
        let o = par(depth)
        c.translateBy(x: x + o.width, y: y + o.height)
        c.rotate(by: .degrees(rot))
        let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        c.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(fill ?? paper))
        c.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(ink.opacity(0.55)), lineWidth: 1.2)
        for i in 0..<lines {
            let ly = -h / 2 + 10 + Double(i) * 7
            c.stroke(Path { $0.move(to: CGPoint(x: -w / 2 + 6, y: ly)); $0.addLine(to: CGPoint(x: w / 2 - 6 - (i == lines - 1 ? 8 : 0), y: ly)) }, with: .color(ink.opacity(0.3)), lineWidth: 1.4)
        }
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ w: Double = 1.6, _ alpha: Double = 0.5) {
        g.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(ink.opacity(alpha)), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    func draw(_ kind: Illustration.Kind) {
        switch kind {
        case .sorting: sorting()
        case .renaming: renaming()
        case .duplicates: duplicates()
        case .tagging: tagging()
        case .eject: eject()
        }
    }

    // Three sheets fall one after another and settle on the shelves.
    func sorting() {
        let shelves = [38.0, 60.0, 82.0]
        for (i, y) in shelves.enumerated() {
            let o = par(0.2)
            line(CGPoint(x: 16 + o.width, y: y + 2 + o.height), CGPoint(x: 96 + o.width, y: y + 2 + o.height), 2, 0.4)
        }
        for i in 0..<3 {
            let p = ((t / 5 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
            let fall = seg(p, 0.02, 0.2)
            let rest = shelves[i] - 11
            let y = -14 + (rest + 14) * fall + (fall < 1 ? 0 : 0)
            let bounce = fall >= 1 ? -2.5 * max(0, sin((p - 0.2) * 38)) * exp(-(p - 0.2) * 18) : 0
            let alpha = p < 0.88 ? 1 : 1 - seg(p, 0.88, 1)
            sheet(30 + Double(i) * 22, y + bounce, w: 18, h: 22, rot: (1 - fall) * (i % 2 == 0 ? -14 : 12), alpha: alpha, lines: 2, depth: 0.7)
        }
    }

    // A scribbled name straightens into a clear one while a pencil passes over it.
    func renaming() {
        let p = (t / 4.2).truncatingRemainder(dividingBy: 1)
        let m = seg(p, 0.15, 0.5)
        sheet(52, 46, w: 52, h: 66, lines: 0, depth: 0.4)
        let o = par(0.6)
        var path = Path()
        let x0 = 32.0 + o.width, y0 = 26.0 + o.height
        path.move(to: CGPoint(x: x0, y: y0))
        for i in 1...12 {
            let x = x0 + Double(i) * 3.2
            path.addLine(to: CGPoint(x: x, y: y0 + (i % 2 == 0 ? -4 : 4) * (1 - m)))
        }
        g.stroke(path, with: .color(ink.opacity(0.35 + 0.35 * m)), style: StrokeStyle(lineWidth: 1.6 + m * 0.8, lineCap: .round, lineJoin: .round))
        for i in 0..<3 { line(CGPoint(x: 32 + o.width, y: 42 + Double(i) * 8 + o.height), CGPoint(x: 72 - Double(i) * 8 + o.width, y: 42 + Double(i) * 8 + o.height), 1.4, 0.25) }
        let px = x0 + 38 * seg(p, 0.15, 0.5)
        var c = g
        c.opacity = 1 - seg(p, 0.5, 0.6) * 0.0 - (p > 0.55 ? seg(p, 0.55, 0.65) : 0)
        c.translateBy(x: px + 4, y: y0 - 5)
        c.rotate(by: .degrees(40))
        c.fill(Path(roundedRect: CGRect(x: -2.5, y: -12, width: 5, height: 22), cornerRadius: 2), with: .color(ink))
        c.fill(Path { $0.move(to: CGPoint(x: -2.5, y: 10)); $0.addLine(to: CGPoint(x: 2.5, y: 10)); $0.addLine(to: CGPoint(x: 0, y: 15)); $0.closeSubpath() }, with: .color(ink.opacity(0.7)))
    }

    // The copy slides out from behind and settles on its own shelf.
    func duplicates() {
        let p = (t / 5).truncatingRemainder(dividingBy: 1)
        let out = seg(p, 0.2, 0.42), drop = seg(p, 0.5, 0.7)
        let fade = p > 0.88 ? seg(p, 0.88, 1) : 0
        line(CGPoint(x: 62, y: 80), CGPoint(x: 104, y: 80), 2, 0.4 * (1 - fade))
        sheet(40, 44, w: 34, h: 44, alpha: 1 - fade * 0.0, depth: 0.5)
        sheet(40 + 28 * out + 8 * drop, 44 + 28 * drop - 2 * out, w: 34 - 8 * drop, h: 44 - 10 * drop, rot: 6 * out * (1 - drop), alpha: 1 - fade, fill: tint.bg, depth: 0.9)
    }

    // A tag on a string: idles in a slow sway, a click sets it swinging.
    func tagging() {
        let kick = exp(-t * 0.9) * (t < 0.2 ? t * 5 : 1)
        let angle = (0.1 + 0.5 * kick) * sin(t * 3.2) + mouse.width * 0.12
        let pivot = CGPoint(x: 56 + par(0.2).width, y: 4)
        var c = g
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .radians(angle))
        c.stroke(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 0, y: 34)) }, with: .color(ink.opacity(0.5)), lineWidth: 1.2)
        let body = Path { p in
            p.move(to: CGPoint(x: -14, y: 44)); p.addLine(to: CGPoint(x: 0, y: 30)); p.addLine(to: CGPoint(x: 14, y: 44))
            p.addLine(to: CGPoint(x: 14, y: 72)); p.addQuadCurve(to: CGPoint(x: 10, y: 76), control: CGPoint(x: 14, y: 76)); p.addLine(to: CGPoint(x: -10, y: 76))
            p.addQuadCurve(to: CGPoint(x: -14, y: 72), control: CGPoint(x: -14, y: 76)); p.closeSubpath()
        }
        c.fill(body, with: .color(tint.bg)); c.stroke(body, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        c.fill(Path(ellipseIn: CGRect(x: -3, y: 36, width: 6, height: 6)), with: .color(paper))
        c.stroke(Path { $0.move(to: CGPoint(x: -7, y: 54)); $0.addLine(to: CGPoint(x: 7, y: 54)) }, with: .color(ink.opacity(0.4)), lineWidth: 1.4)
        c.stroke(Path { $0.move(to: CGPoint(x: -7, y: 61)); $0.addLine(to: CGPoint(x: 3, y: 61)) }, with: .color(ink.opacity(0.4)), lineWidth: 1.4)
        // Finder dots popping out beside the tag as it swings.
        for (i, col) in [Color.orange, .blue, .green].enumerated() {
            let pop = max(0, sin(t * 3.2 + Double(i) * 1.1)) * (0.4 + kick)
            g.fill(Path(ellipseIn: CGRect(x: 78 + Double(i) * 9, y: 56 - pop * 10, width: 6, height: 6)), with: .color(col.opacity(0.35 + 0.65 * min(pop, 1))))
        }
    }

    // A disk rises out of its slot, then drops into the bin.
    func eject() {
        let p = (t / 5).truncatingRemainder(dividingBy: 1)
        let up = seg(p, 0.1, 0.32), over = seg(p, 0.5, 0.72), down = seg(p, 0.62, 0.82)
        let fade = p > 0.9 ? seg(p, 0.9, 1) : 0
        let o = par(0.3)
        g.fill(Path(roundedRect: CGRect(x: 14 + o.width, y: 70 + o.height, width: 50, height: 8), cornerRadius: 3), with: .color(soft))
        g.stroke(Path(roundedRect: CGRect(x: 14 + o.width, y: 70 + o.height, width: 50, height: 8), cornerRadius: 3), with: .color(ink.opacity(0.5)), lineWidth: 1.2)
        // bin with a lid that opens as the disk arrives
        let lid = -26 * seg(p, 0.5, 0.62) * (1 - seg(p, 0.8, 0.9))
        let bx = 84.0 + o.width, by = 56.0 + o.height
        var b = g
        b.stroke(Path { $0.move(to: CGPoint(x: bx - 10, y: by + 2)); $0.addLine(to: CGPoint(x: bx - 8, y: by + 26)); $0.addLine(to: CGPoint(x: bx + 8, y: by + 26)); $0.addLine(to: CGPoint(x: bx + 10, y: by + 2)) }, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        b.translateBy(x: bx - 12, y: by)
        b.rotate(by: .degrees(lid))
        b.stroke(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 24, y: 0)) }, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        // the disk
        let dx = 36 + 48 * over, dy = 62 - 26 * up + 38 * down * (over > 0.5 ? 1 : 0) - 14 * over * (1 - down)
        var d = g
        d.opacity = (1 - fade) * (1 - 0.0)
        let r = 13 * (1 - 0.35 * down)
        d.translateBy(x: dx + par(0.8).width, y: dy + par(0.8).height)
        d.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(tint.bg))
        d.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(ink.opacity(0.8)), lineWidth: 1.4)
        d.fill(Path(ellipseIn: CGRect(x: -3.5, y: -3.5, width: 7, height: 7)), with: .color(paper))
        // the up arrow pulses while it rises
        if up > 0 && up < 1 { line(CGPoint(x: 36, y: 28), CGPoint(x: 36, y: 14), 1.8, 0.8); line(CGPoint(x: 31, y: 19), CGPoint(x: 36, y: 14), 1.8, 0.8); line(CGPoint(x: 41, y: 19), CGPoint(x: 36, y: 14), 1.8, 0.8) }
    }
}
