// Ink.swift
// Anything solid white on screen is ground to him, and so is the ink on a
// paint program's canvas and every stroke on the Gravity Pencil web page when
// its tab is showing. A background thread looks at the screen in a box around
// him, and has the paint window render itself (so nothing on top of it - him
// included - gets in the picture), picks out the white canvas and marks every
// dark pixel on it. The map is kept relative to the window, so it stays lined
// up while you drag it around between looks.
//
// Looking at the screen takes ScreenCaptureKit (macOS 14 or later) and the
// Screen Recording permission. Without them there is simply no ink.

import Cocoa
import ScreenCaptureKit

final class InkMap {                // the canvas, relative to the paint window
    let cl: Int, ct: Int, cr: Int, cb: Int, w: Int
    let m: [Bool]
    init(cl: Int, ct: Int, cr: Int, cb: Int, w: Int, m: [Bool]) {
        self.cl = cl; self.ct = ct; self.cr = cr; self.cb = cb; self.w = w; self.m = m
    }
}

final class InkShot {               // the white on screen in a box around him
    let x: Int, y: Int, w: Int, h: Int
    let m: [Bool]
    init(x: Int, y: Int, w: Int, h: Int, m: [Bool]) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.m = m
    }
}

final class Holder<T> { var value: T? = nil }

enum Ink {
    private static let lock = NSLock()
    private static var cur: InkMap? = nil
    private static var scr: InkShot? = nil

    static var white = false            // menu toggle
    static var fx = 0, fy = 0           // main thread: where he is right now
    static var active = false           // main thread: he is in or near the paint window
    static var target = 0               // the paint window (or the Gravity Pencil page), found by the thread
    static var web = false              // the target is the Gravity Pencil page in a browser
    private static var ox = 0, oy = 0   // where the window is right now (main thread)
    private static var synced = 0       // the window ox, oy belong to

    static let BOX_W = 1400, BOX_H = 1000   // how much of the screen around him is looked at
    static let RUN = 10, THICK = 4          // smallest white patch that counts, so text does not

    static var supported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    static func start() {
        if #available(macOS 14.0, *) {
            Thread.detachNewThread { Ink.loop(InkCapture()) }
        }
    }

    private static func store(_ m: InkMap?, _ s: InkShot?) {
        lock.lock(); cur = m; scr = s; lock.unlock()
    }

    @available(macOS 14.0, *)
    private static func loop(_ cap: InkCapture) {
        var found = 0
        var allowed = false
        var checked = 0
        while true {
            autoreleasepool {
                checked -= 1
                if checked <= 0 { checked = 30; allowed = CGPreflightScreenCaptureAccess() }
                if !allowed {
                    store(nil, nil)
                } else {
                    found -= 1
                    if found <= 0 { found = 8; cap.refresh(); find() }       // look about once a second
                    let t = target
                    let m = (active && t != 0) ? cap.grab(t, web) : nil
                    let s = white ? cap.shoot(fx, fy) : nil
                    store(m, s)
                }
            }
            // the web page's drawings move, so it is looked at more often
            let wait = active ? (web ? 0.03 : 0.11) : 0.14
            Thread.sleep(forTimeInterval: !allowed ? 0.5 : (white ? min(wait, 0.06) : wait))
        }
    }

    // The frontmost of: a paint program's window, or a window titled
    // "Gravity Pencil" (the page's tab, when it is the one showing).
    private static func find() {
        var hit = 0
        var isWeb = false
        for w in windowList() where w.layer == 0 {
            if w.title.range(of: "Gravity Pencil", options: .caseInsensitive) != nil { hit = w.id; isWeb = true; break }
            let o = w.owner.lowercased()
            if o.hasPrefix("paint") || o == "pinta" { hit = w.id; isWeb = false; break }
        }
        if hit != target { lock.lock(); cur = nil; lock.unlock() }
        web = isWeb
        target = hit
    }

    // Called from the animation loop: note where the paint window is now, and
    // say how far it moved since last time so he can ride along when it is dragged.
    static func sync() -> (dx: Double, dy: Double) {
        let t = target
        guard t != 0, let r = windowBounds(t) else { return (dx: 0, dy: 0) }
        let nx = Int(r.minX), ny = Int(r.minY)
        let dx = nx - ox, dy = ny - oy
        let first = t != synced                 // a different window: nothing moved
        synced = t; ox = nx; oy = ny
        return first ? (dx: 0, dy: 0) : (dx: Double(dx), dy: Double(dy))
    }

    private static func snap() -> (InkMap?, InkShot?) {
        lock.lock()
        defer { lock.unlock() }
        return (active ? cur : nil, scr)
    }

    static var ready: Bool {
        let (m, s) = snap()
        return m != nil || s != nil
    }

    private static func inMap(_ m: InkMap?, _ x: Int, _ y: Int) -> Bool {
        guard let m = m else { return false }
        return x >= ox + m.cl && x <= ox + m.cr && y >= oy + m.ct - 2 && y <= oy + m.cb
    }

    // on the paint canvas (so he rides it when it is dragged), not just on white
    static func inCanvas(_ x: Int, _ y: Int) -> Bool { inMap(snap().0, x, y) }

    // left, right and bottom of whatever he is standing on at (x, y)
    static func bounds(_ x: Int, _ y: Int) -> (l: Double, r: Double, b: Double) {
        let (m, s) = snap()
        if let mm = m, inMap(mm, x, y) { return (l: Double(ox + mm.cl), r: Double(ox + mm.cr), b: Double(oy + mm.cb)) }
        if let ss = s { return (l: Double(ss.x), r: Double(ss.x + ss.w - 1), b: Double(ss.y + ss.h - 1)) }
        return (l: Double(x - 1), r: Double(x + 1), b: Double(y + 1))
    }

    // The canvas wins where it is (its white paper is not ground, its ink is);
    // everywhere else anything white is solid.
    private static func at(_ m: InkMap?, _ s: InkShot?, _ x: Int, _ y: Int) -> Bool {
        if let m = m {
            let mx = x - ox - m.cl, my = y - oy - m.ct
            if mx >= 0 && mx < m.w && my >= 0 && my <= m.cb - m.ct { return m.m[my * m.w + mx] }
        }
        guard let s = s else { return false }
        let sx = x - s.x, sy = y - s.y
        if sx < 0 || sx >= s.w || sy < 0 || sy >= s.h { return false }
        return s.m[sy * s.w + sx]
    }

    static func inside(_ x: Int, _ y: Int) -> Bool {
        let (m, s) = snap()
        if inMap(m, x, y) { return true }
        guard let ss = s else { return false }
        return x >= ss.x && x < ss.x + ss.w && y >= ss.y && y < ss.y + ss.h
    }

    // The first solid pixel going down from y0 to y1 under his feet, or -1.
    // Three columns wide, so a thin slanted line cannot slip between his toes.
    static func floor(_ x: Int, _ y0: Int, _ y1: Int) -> Int {
        let (m, s) = snap()
        if m == nil && s == nil { return -1 }
        for y in stride(from: y0, through: y1, by: 1) {
            if at(m, s, x - 1, y) || at(m, s, x, y) || at(m, s, x + 1, y) { return y }
        }
        return -1
    }

    // anything solid in this column between y0 and y1: a stroke in his way
    static func blocked(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
        let (m, s) = snap()
        if m == nil && s == nil { return false }
        for y in stride(from: y0, through: y1, by: 1) where at(m, s, x, y) { return true }
        return false
    }
}

// the pixels of an image, top row first, four bytes each: red, green, blue, alpha
func rgbaPixels(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8]? {
    if w <= 0 || h <= 0 { return nil }
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ok: Bool = buf.withUnsafeMutableBytes { raw -> Bool in
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? buf : nil
}

@available(macOS 14.0, *)
final class InkCapture {
    private var content: SCShareableContent? = nil

    // what is on screen: displays, windows and the programs they belong to
    func refresh() {
        let sem = DispatchSemaphore(value: 0)
        let box = Holder<SCShareableContent>()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, _ in
            box.value = c
            sem.signal()
        }
        if sem.wait(timeout: .now() + 2) == .success, let c = box.value { content = c }
    }

    private func snap(_ filter: SCContentFilter, _ cfg: SCStreamConfiguration) -> CGImage? {
        let sem = DispatchSemaphore(value: 0)
        let box = Holder<CGImage>()
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, _ in
            box.value = img
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 1.5) == .success else { return nil }
        return box.value
    }

    // Paint: pure white canvas, black ink. The Gravity Pencil page paints its
    // paper exactly #fdfcfa, and every stroke on it is ink, whatever colour.
    private func paper(_ px: [UInt8], _ o: Int, _ isWeb: Bool) -> Bool {
        let r = Int(px[o]), g = Int(px[o + 1]), b = Int(px[o + 2])
        if isWeb { return abs(r - 253) <= 3 && abs(g - 252) <= 3 && abs(b - 250) <= 3 }
        return r >= 250 && g >= 250 && b >= 250
    }
    private func stroke(_ px: [UInt8], _ o: Int, _ isWeb: Bool) -> Bool {
        let r = Int(px[o]), g = Int(px[o + 1]), b = Int(px[o + 2])
        if isWeb { return min(r, g, b) < 190 }
        return r < 90 && g < 90 && b < 90
    }

    func grab(_ id: Int, _ isWeb: Bool) -> InkMap? {
        guard let win = content?.windows.first(where: { Int($0.windowID) == id }), let r = windowBounds(id) else { return nil }
        let w = Int(r.width), ht = Int(r.height)
        if w < 50 || ht < 50 { return nil }
        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = ht
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.sRGB
        guard let img = snap(SCContentFilter(desktopIndependentWindow: win), cfg), let px = rgbaPixels(img, w, ht) else { return nil }

        // The canvas is the one big pure-white area: find the rows and columns
        // that are mostly white. The toolbar's white swatch is far too small to
        // count, and the chrome around it is never pure white.
        var rows = [Int](repeating: 0, count: ht)
        var cols = [Int](repeating: 0, count: w)
        for y in 0..<ht {
            for x in 0..<w where paper(px, (y * w + x) * 4, isWeb) { rows[y] += 1; cols[x] += 1 }
        }
        let rMin = max(40, w / 6), cMin = max(40, ht / 6)
        var cl = -1, cr = -1, ct = -1, cb = -1
        for x in 0..<w where cols[x] >= cMin { if cl < 0 { cl = x }; cr = x }
        for y in 0..<ht where rows[y] >= rMin { if ct < 0 { ct = y }; cb = y }
        if cl < 0 || ct < 0 || cr - cl < 20 || cb - ct < 20 { return nil }

        let mw = cr - cl + 1
        var m = [Bool](repeating: false, count: mw * (cb - ct + 1))
        for y in ct...cb {
            for x in cl...cr { m[(y - ct) * mw + (x - cl)] = stroke(px, (y * w + x) * 4, isWeb) }
        }
        return InkMap(cl: cl, ct: ct, cr: cr, cb: cb, w: mw, m: m)
    }

    // The screen in a box around (cx, cy). Every stickman is left out of the
    // picture, so his own white head is never ground.
    func shoot(_ cx: Int, _ cy: Int) -> InkShot? {
        guard let content = content else { return nil }
        let pt = CGPoint(x: cx, y: cy)
        guard let display = content.displays.first(where: { $0.frame.contains(pt) }) ?? content.displays.first else { return nil }
        let df = display.frame
        let dl = Int(df.minX), dt = Int(df.minY), dw = Int(df.width), dh = Int(df.height)
        let w = min(Ink.BOX_W, dw), h = min(Ink.BOX_H, dh)
        if w <= 0 || h <= 0 { return nil }
        let x = max(dl, min(cx - w / 2, dl + dw - w))
        let y = max(dt, min(cy - h / 2, dt + dh - h))

        let me = getpid()
        let bid = Bundle.main.bundleIdentifier ?? "-"
        let sticks = content.applications.filter { $0.processID == me || $0.bundleIdentifier == bid }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: x - dl, y: y - dt, width: w, height: h)
        cfg.width = w
        cfg.height = h
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(display: display, excludingApplications: sticks, exceptingWindows: [])
        guard let img = snap(filter, cfg), let px = rgbaPixels(img, w, h) else { return nil }

        // white runs at least RUN wide...
        var row = [Bool](repeating: false, count: w * h)
        for yy in 0..<h {
            let base = yy * w
            var start = -1
            for xx in 0...w {
                var on = false
                if xx < w {
                    let o = (base + xx) * 4
                    on = px[o] >= 245 && px[o + 1] >= 245 && px[o + 2] >= 245
                }
                if on { if start < 0 { start = xx }; continue }
                if start >= 0 && xx - start >= Ink.RUN { for k in start..<xx { row[base + k] = true } }
                start = -1
            }
        }
        // ...and at least THICK tall below each pixel
        var m = [Bool](repeating: false, count: w * h)
        var i = 0
        while i + (Ink.THICK - 1) * w < w * h {
            var ok = true
            var k = 0
            while k < Ink.THICK && ok { ok = row[i + k * w]; k += 1 }
            m[i] = ok
            i += 1
        }
        return InkShot(x: x, y: y, w: w, h: h, m: m)
    }
}
