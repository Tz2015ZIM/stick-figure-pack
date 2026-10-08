// Drawing.swift
// His window, his poses, and the little windows around him: the spark a blow
// pops, the grip pad under a pointer he is holding, and the Flash panels he
// conjures to throw.

import Cocoa

// ------------------------------------------------------------------- the sprite
// He lives in a small borderless window that floats above everything, on every
// Space. It has no background at all - just the figure - and clicks go
// straight through it except where he is actually drawn.
var spriteWin: NSPanel! = nil
var spriteView: SpriteView! = nil

final class SpriteView: NSView {
    override var isFlipped: Bool { true }           // y down, like his design units
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        g.clear(bounds)
        drawFigure(g)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event, self); return }
        spriteMouseDown()
    }
    override func mouseUp(with event: NSEvent) { spriteMouseUp() }
    override func rightMouseDown(with event: NSEvent) { showMenu(event, self) }
}

// a borderless see-through window that never takes the focus
func overlayPanel(_ w: Double, _ h: Double) -> NSPanel {
    let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.level = .statusBar
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    return p
}

func makeSprite() {
    let p = overlayPanel(BOXW, BOXH)
    p.ignoresMouseEvents = true
    let v = SpriteView(frame: NSRect(x: 0, y: 0, width: BOXW, height: BOXH))
    p.contentView = v
    spriteWin = p
    spriteView = v
}

// one frame: redraw him, move the window to him, and let clicks through
// wherever he is not
func placeSprite() {
    guard let win = spriteWin, let view = spriteView else { return }
    let x = (S.x - CX).rounded(), y = (S.y - FOOT).rounded()
    win.setFrameOrigin(cocoaOrigin(x, y, BOXH))
    view.needsDisplay = true
    if !win.isVisible { win.orderFrontRegardless() }
    MY_WINDOWS.insert(win.windowNumber)
    let c = cursorPos()
    let over = S.drag || figureHit((c.x - x) / SC, (c.y - y) / SC)
    if win.ignoresMouseEvents == over { win.ignoresMouseEvents = !over }
}

// ------------------------------------------------------------------------ poses
struct Seg { var ax: Double, ay: Double, bx: Double, by: Double }

struct Pose {
    var segs: [Seg] = []
    var headX = 22.0, headY = 14.0
    var lift = 0.0                  // the whole figure off the ground, for the cheer hop
    var dots = 0                    // speech dots over his head while he chats
    var name = "walk"
}

// the lines of him right now, in design units
func currentPose() -> Pose {
    var P = Pose()
    let ph = S.phase
    let sn = sin(ph)
    let d = Double(S.dir)
    let tm = Double(S.timer)
    var lean = 0.0
    func L(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) {
        P.segs.append(Seg(ax: ax, ay: ay, bx: bx, by: by))
    }

    var pose = S.drag ? "fall" : S.state
    if pose == "meet" { pose = S.waiting ? "idle" : "walk" }
    if pose == "social" { pose = SOCIAL_POSE[S.act] ?? "idle" }
    if pose == "fall" && F.air != "" && !S.drag { pose = F.air }
    if pose == "cheer" { P.lift = -abs(sin(ph * 1.4)) * 9.0 }     // the whole figure leaves the ground
    P.name = pose

    switch pose {
    case "climb":
        L(22, 21, 22, 40)                               // spine
        L(22, 25, 14, 13 - sn * 5)                      // arms reaching up
        L(22, 25, 30, 13 + sn * 5)
        L(22, 40, 14, 52 + sn * 5)                      // bent legs
        L(22, 40, 30, 52 - sn * 5)

    case "fall":
        P.headY = 15
        L(22, 22, 22, 40)
        L(22, 26, 11, 15)
        L(22, 26, 33, 17)
        L(22, 40, 13, 60)
        L(22, 40, 30, 62)

    case "idle":
        let bob = sn * 1.2
        P.headY = 14 + bob
        L(22, 21 + bob, 22, 40 + bob)
        L(22, 26 + bob, 16, 38 + bob)
        L(22, 26 + bob, 28, 38 + bob)
        L(22, 40 + bob, 17, 62)
        L(22, 40 + bob, 27, 62)

    case "leap":
        // stretched out, both arms reaching for the corner
        P.headY = 16
        L(22, 23, 22, 41)
        L(22, 26, 22 - d * 6, 9)
        L(22, 26, 22 + d * 9, 11)
        L(22, 41, 22 - d * 7, 56)                       // legs tucked and trailing
        L(22 - d * 7, 56, 22 - d * 12, 62)
        L(22, 41, 22 - d * 2, 60)

    case "cheer":
        let sw = sin(ph * 1.4)
        L(22, 21, 22, 40)
        L(22, 26, 12, 13 - sw * 3)                      // both arms up
        L(22, 26, 32, 13 + sw * 3)
        L(22, 40, 22 - 5 - sw * 3, 62)                  // legs kicking out
        L(22, 40, 22 + 5 + sw * 3, 62)

    case "wave":
        P.headX = 22 + d * 1.5
        L(22, 21, 22, 40)
        L(22, 26, 22 - d * 7, 38)                       // arm down
        L(22, 26, 22 + d * 10, 15 + sn * 5)             // arm waving
        L(22, 40, 17, 62)
        L(22, 40, 27, 62)

    case "sit":
        P.headY = 30
        P.headX = 22 + d * 1.5
        L(22, 37, 22 - d * 2, 54)                       // spine, leaning back
        L(22, 41, 22 - d * 8, 55)                       // arm propped behind
        L(22, 41, 22 + d * 5, 50)
        L(22 - d * 2, 54, 22 + d * 12, 53)              // thigh along the edge
        L(22 + d * 12, 53, 22 + d * 12 + sn * 3, 64)    // shin swinging

    case "press":
        // squat down and stamp on the button
        let c = sin(((42.0 - tm) / 42.0) * Double.pi)
        P.headY = 14 + 11 * c
        L(22, 21 + 11 * c, 22, 40 + 6 * c)
        L(22, 26 + 10 * c, 22 - d * 8, 30 + 14 * c)
        L(22, 26 + 10 * c, 22 + d * 8, 30 + 14 * c)
        L(22, 40 + 6 * c, 22 - 6 - 5 * c, 52 + 2 * c)   // knees out
        L(22 - 6 - 5 * c, 52 + 2 * c, 22 - 6, 62)
        L(22, 40 + 6 * c, 22 + 6 + 5 * c, 52 + 2 * c)
        L(22 + 6 + 5 * c, 52 + 2 * c, 22 + 6, 62)

    case "knock":
        let rap = max(0.0, sn)
        L(22, 21, 22, 40)
        L(22, 26, 22 + d * (8 + rap * 4), 25)           // knuckles on the glass
        L(22, 26, 22 - d * 6, 38)
        L(22, 40, 22 - d * 4, 62)
        L(22, 40, 22 + d * 4, 62)

    case "push":
        lean = d * 4
        P.headX = 22 + lean * 1.3
        P.headY = 16
        L(22 + lean, 23, 22 - lean * 0.3, 40)
        L(22 + lean * 0.6, 27, 22 + d * 12, 29)
        L(22 + lean * 0.6, 27, 22 + d * 12, 33)
        L(22 - lean * 0.3, 40, 22 - d * 11, 62)         // braced back leg
        L(22 - lean * 0.3, 40, 22 + d * 3, 62)

    case "hifive":
        // the arm goes up and out to meet his friend's hand in the middle
        let r = sin(((40.0 - tm) / 40.0) * Double.pi)
        lean = d * 1.5 * r
        P.headX = 22 + lean
        L(22 + lean * 0.6, 21, 22, 40)
        L(22 + lean * 0.4, 26, 22 + d * (4 + 8 * r), 24 - 14 * r)
        L(22 + lean * 0.4, 26, 22 - d * 6, 38)
        L(22, 40, 22 - d * 6, 62)
        L(22, 40, 22 + d * 4, 62)

    case "chat":
        // they take turns: one talks with his hands, the other nods along
        let first = ME < S.with ? 0 : 1
        let talk = (S.timer / 35) % 2 == first
        L(22, 21, 22, 40)
        L(22, 26, 22 - d * 5, 38)
        if talk {
            let gs = sin(ph * 3.0)
            L(22, 26, 22 + d * 8, 34)
            L(22 + d * 8, 34, 22 + d * 13, 27 + gs * 3)
            P.dots = 1 + max(0, ri(floor(ph * 1.5))) % 3
        } else {
            P.headY = 14 + abs(sn) * 1.5
            L(22, 26, 22 + d * 5, 38)
        }
        L(22, 40, 18, 62)
        L(22, 40, 26, 62)

    case "guard":
        // fists up, knees bent, bouncing on his toes
        let b = abs(sin(ph * 1.6)) * 1.6
        P.headX = 22 + d * 2
        P.headY = 18 + b
        L(22 + d * 1.5, 25 + b, 22 - d * 0.5, 42 + b)
        L(22 + d * 1.2, 29 + b, 22 + d * 9, 35 + b)     // lead fist out front
        L(22 + d * 9, 35 + b, 22 + d * 12, 27 + b)
        L(22 + d * 1.2, 29 + b, 22 + d * 3, 37 + b)     // rear fist by his chin
        L(22 + d * 3, 37 + b, 22 + d * 7, 29 + b)
        L(22 - d * 0.5, 42 + b, 22 + d * 7, 52 + b / 2) // lead leg
        L(22 + d * 7, 52 + b / 2, 22 + d * 9, 62)
        L(22 - d * 0.5, 42 + b, 22 - d * 6, 52 + b / 2) // back leg
        L(22 - d * 6, 52 + b / 2, 22 - d * 10, 62)

    case "taunt":
        // 'come on, then': hand out, palm up, fingers beckoning
        let k = max(0.0, sin(ph * 3.0))
        P.headX = 22 + d
        P.headY = 17
        L(22 + d, 24, 22, 42)
        L(22 + d, 28, 22 + d * 13, 31)
        L(22 + d * 13, 31, 22 + d * (17 - 3 * k), 31 - 5 * k)
        L(22 + d, 28, 22 - d * 5, 35)                   // other hand on his hip
        L(22 - d * 5, 35, 22 - d, 40)
        L(22, 42, 22 + d * 7, 52)
        L(22 + d * 7, 52, 22 + d * 9, 62)
        L(22, 42, 22 - d * 6, 52)
        L(22 - d * 6, 52, 22 - d * 10, 62)

    case "punch":
        // jab and cross in turn, lunging in behind it
        let e = sin(((14.0 - tm) / 14.0) * Double.pi)
        lean = d * 2.5 * e
        P.headX = 22 + d * 2 + lean
        P.headY = 18
        let sx = 22 + d * 1.2 + lean
        L(22 + d * 1.5 + lean, 25, 22 - d * 0.5, 42)
        let ex = 22 + d * (8 + 6 * e) + lean * 0.4
        let fx = 22 + d * (11 + 7.5 * e) + lean * 0.4
        L(sx, 29, ex, 34 - 7 * e)                       // the punching arm
        L(ex, 34 - 7 * e, fx, 27 - e)
        L(sx, 29, 22 + d * 3, 37)                       // the other stays up
        L(22 + d * 3, 37, 22 + d * 7, 29)
        L(22 - d * 0.5, 42, 22 + d * 8, 51)
        L(22 + d * 8, 51, 22 + d * 10, 62)
        L(22 - d * 0.5, 42, 22 - d * 6, 52)
        L(22 - d * 6, 52, 22 - d * 11, 62)

    case "kick":
        // leans back and snaps a kick out at the pointer
        let e = sin(((20.0 - tm) / 20.0) * Double.pi)
        let back = d * 4 * e
        P.headX = 22 + d - back
        P.headY = 17 + 2 * e
        L(22 + d - back * 0.9, 24 + 2 * e, 22 - d, 42)
        L(22 + d - back * 0.7, 28 + 2 * e, 22 - d * 9, 34)         // arm out for balance
        L(22 + d - back * 0.7, 28 + 2 * e, 22 + d * 7, 25 + 2 * e)
        L(22 - d, 42, 22 - d * 3, 52)                               // standing leg
        L(22 - d * 3, 52, 22 - d * 5, 62)
        let kneeX = 22 + d * (4 + 8 * e), kneeY = 50 - 10 * e       // kicking leg
        L(22 - d, 42, kneeX, kneeY)
        L(kneeX, kneeY, 22 + d * (6 + 13 * e), 60 - 26 * e)

    case "heave":
        // wrenching a window loose, trembling with the effort
        let k = sin(ph * 6.0) * 0.7
        if let fl = F.fly, fl.up {
            // hands up under its bottom edge, knees bent
            P.headY = 18
            L(22, 25, 22, 42)
            L(22, 28, 22 - d * 9, 18 + k)
            L(22 - d * 9, 18 + k, 22 - d * 4, 4.5 + k)
            L(22, 28, 22 + d * 9, 18 - k)
            L(22 + d * 9, 18 - k, 22 + d * 4, 4.5 - k)
            L(22, 42, 16, 52); L(16, 52, 17, 62)
            L(22, 42, 28, 52); L(28, 52, 27, 62)
        } else {
            // both hands on its side, leaning back further and further
            let t = 1.0 - tm / Double(F.fly?.len ?? HEAVE_LEN)
            let bk = d * 3.5 * t
            let hx = 22 + d * 7 - bk * 0.5
            P.headX = 22 - bk * 1.2
            P.headY = 17
            L(22 - bk, 24, 22, 41)
            L(22 - bk * 0.8, 28, hx, 29 + k)
            L(hx, 29 + k, 22 + d * 14, 27 + k)
            L(22 - bk * 0.8, 28, hx, 33 + k)
            L(hx, 33 + k, 22 + d * 14, 31 + k)
            L(22, 41, 22 + d * 6, 51); L(22 + d * 6, 51, 22 + d * 9, 62)
            L(22, 41, 22 - d * 6, 52); L(22 - d * 6, 52, 22 - d * 11, 62)
        }

    case "hurl":
        // the follow-through: lunging after it, arms out at the pointer
        let e = sin(((14.0 - tm) / 14.0) * Double.pi)
        lean = d * 3 * e
        P.headX = 22 + d * 2 + lean
        P.headY = 17 + e
        let sx = 22 + d * 1.2 + lean * 0.8
        let elbow = 22 + d * (8 + 3 * e) + lean * 0.5
        let low = 22 + d * (7 + 3 * e)
        L(22 + d * 1.5 + lean, 24 + e, 22 - d * 0.5, 42)
        L(sx, 28, elbow, 24 - 2 * e)
        L(elbow, 24 - 2 * e, 22 + d * (14 + 4 * e), 20 - 3 * e)
        L(sx, 28, low, 31)
        L(low, 31, 22 + d * (13 + 3 * e), 28)
        L(22 - d * 0.5, 42, 22 + d * 8, 51); L(22 + d * 8, 51, 22 + d * 11, 62)
        L(22 - d * 0.5, 42, 22 - d * 6, 52); L(22 - d * 6, 52, 22 - d * 12, 62)

    case "haul":
        // the arm with your pointer in it comes from getGrabHand, which
        // stepGrab uses too, so the pointer sits right in his fist
        let hd = getGrabHand()
        if GRAB_HOLD - S.timer < GRAB_SNATCH {
            // lunging in to take it, other fist up
            P.headX = 22 + d * 3
            P.headY = 17
            L(22 + d * 2.5, 24, 22 - d * 0.5, 42)
            L(22 + d, 27, hd.x, hd.y)
            L(22 + d, 29, 22 + d * 3, 37); L(22 + d * 3, 37, 22 + d * 7, 29)
            L(22 - d * 0.5, 42, 22 + d * 8, 51); L(22 + d * 8, 51, 22 + d * 10, 62)
            L(22 - d * 0.5, 42, 22 - d * 6, 52); L(22 - d * 6, 52, 22 - d * 11, 62)
        } else {
            // running off, dragging it along behind him
            let sw = sn * 9.0
            P.headX = 22 + d * 3.5
            P.headY = 16
            L(22 + d * 2.5, 23, 22, 40)
            L(22 + d, 27, hd.x, hd.y)
            L(22 + d, 27, 22 + d + sw * 0.7, 37)
            L(22, 40, 22 + sw, 62)
            L(22, 40, 22 - sw, 62)
        }

    case "fling":
        // swinging it up over his head and letting fly
        let hd = getGrabHand()
        let e = min(1.0, Double(FLING_LEN - S.timer) / Double(FLING_LEN - FLING_AT))
        lean = d * 3 * e
        P.headX = 22 + d + lean
        P.headY = 17
        L(22 + d * 1.5 + lean * 0.8, 24, 22 - d * 0.5, 42)
        L(22 + d, 27, hd.x, hd.y)
        L(22 + d, 28, 22 - d * 10, 33 - 4 * e)
        L(22 - d * 0.5, 42, 22 + d * 8, 51); L(22 + d * 8, 51, 22 + d * 11, 62)
        L(22 - d * 0.5, 42, 22 - d * 6, 52); L(22 - d * 6, 52, 22 - d * 12, 62)

    case "flykick":
        // one leg straight out at the pointer, the other tucked under
        P.headX = 22 - d * 5
        P.headY = 15
        L(22 - d * 4, 22, 22 + d, 38)
        L(22 + d, 38, 22 + d * 19, 34)
        L(22 + d, 38, 22 - d * 3, 49)
        L(22 - d * 3, 49, 22 - d * 10, 45)
        L(22 - d * 3, 26, 22 + d * 7, 21)
        L(22 - d * 3, 26, 22 - d * 13, 30)

    case "hurt":
        // knocked back: head snapped back, arms and legs flung forward
        P.headX = 22 - d * 6
        P.headY = 16
        L(22 - d * 4.5, 22.5, 22 + d, 40)
        L(22 - d * 3, 27, 22 + d * 9, 19)
        L(22 - d * 3, 27, 22 + d * 10, 31)
        L(22 + d, 40, 22 + d * 10, 55)
        L(22 + d, 40, 22 + d * 4, 61)

    case "flip":
        // a quick hop back out of the way, knees tucked
        P.headX = 22 - d * 2
        P.headY = 19
        L(22 - d * 1.5, 25.5, 22, 40)
        L(22 - d, 29, 22 + d * 9, 25)
        L(22 - d, 29, 22 - d * 9, 33)
        L(22, 40, 22 + d * 7, 47)
        L(22 + d * 7, 47, 22 + d * 2, 55)
        L(22, 40, 22 + d * 4, 50)
        L(22 + d * 4, 50, 22 - d * 2, 58)

    case "ko":
        // flat on his back with his knees up
        P.headX = 22 - d * 12
        P.headY = 55
        L(22 - d * 5.5, 58, 22 + d * 5, 60)
        L(22 - d * 4, 58, 22 + d, 51)
        L(22 - d * 4, 58, 22 - d * 10, 62)
        L(22 + d * 5, 60, 22 + d * 11, 50)
        L(22 + d * 11, 50, 22 + d * 17, 61)
        L(22 + d * 5, 60, 22 + d * 13, 53)
        L(22 + d * 13, 53, 22 + d * 18, 62)

    default:    // walk
        lean = d * 2
        let swing = sn * 7
        let hand = 37 - abs(sn) * 2
        P.headX = 22 + lean * 0.9
        L(22 + lean * 0.7, 21, 22, 40)
        L(22 + lean * 0.4, 26, 22 - swing, hand)
        L(22 + lean * 0.4, 26, 22 + swing, hand)
        L(22, 40, 22 + swing, 62)
        L(22, 40, 22 - swing, 62)
    }
    return P
}

// Is the point (x, y), in design units inside his box, on the figure itself?
func figureHit(_ x: Double, _ y: Double) -> Bool {
    if x < 0 || y < 0 || x > DW || y > DH { return false }
    let P = currentPose()
    let py = y - P.lift
    let hx = x - P.headX, hy = py - P.headY
    if hx * hx + hy * hy <= 100 { return true }
    for s in P.segs {
        let vx = s.bx - s.ax, vy = s.by - s.ay
        let len2 = vx * vx + vy * vy
        var t = len2 > 0 ? ((x - s.ax) * vx + (py - s.ay) * vy) / len2 : 0
        t = max(0, min(1, t))
        let qx = s.ax + vx * t - x, qy = s.ay + vy * t - py
        if qx * qx + qy * qy <= 25 { return true }
    }
    return false
}

// ------------------------------------------------------------------------ inks
let EGG_INK  = RGB(r: 24, g: 24, b: 28)         // his own ink
let HURT_INK = RGB(r: 226, g: 46, b: 46)        // the red he flashes when you land one
let FLASH_BLUE = RGB(r: 0, g: 153, b: 255)

func cgc(_ c: RGB, _ a: Double = 1) -> CGColor {
    CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: a)
}

func strokeSegs(_ g: CGContext, _ segs: [Seg]) {
    g.beginPath()
    for s in segs {
        g.move(to: CGPoint(x: s.ax, y: s.ay))
        g.addLine(to: CGPoint(x: s.bx, y: s.by))
    }
    g.strokePath()
}

func drawFigure(_ g: CGContext) {
    g.saveGState()
    defer { g.restoreGState() }
    g.scaleBy(x: SC, y: SC)                         // design units from here on

    // whichever figure he currently is. A pale colour needs a dark halo or he
    // disappears into a light wallpaper, so the outline flips with the ink.
    var ink = S.ink ?? EGG_INK
    if F.hurt > 0 && F.hurt % 4 < 2 { ink = HURT_INK }      // you landed one
    let lum = (0.299 * ink.r + 0.587 * ink.g + 0.114 * ink.b) / 255.0
    let halo = lum > 0.62 ? RGB(r: 24, g: 24, b: 28) : RGB(r: 255, g: 255, b: 255)

    let P = currentPose()
    let head = CGRect(x: P.headX - 6.5, y: P.headY - 6.5, width: 13, height: 13)

    g.saveGState()
    g.translateBy(x: 0, y: P.lift)
    g.setLineCap(.round)
    g.setLineJoin(.round)

    g.setStrokeColor(cgc(halo))
    g.setLineWidth(6.5)
    strokeSegs(g, P.segs)
    g.strokeEllipse(in: head)
    g.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    g.fillEllipse(in: head)
    g.setStrokeColor(cgc(ink))
    g.setLineWidth(3.0)
    strokeSegs(g, P.segs)
    g.strokeEllipse(in: head)

    for i in 0..<P.dots {
        let dx = 22 + Double(S.dir) * (9 + Double(i) * 4)
        g.setFillColor(cgc(halo))
        g.fillEllipse(in: CGRect(x: dx - 2.2, y: 1.3, width: 4.4, height: 4.4))
        g.setFillColor(cgc(ink))
        g.fillEllipse(in: CGRect(x: dx - 1.3, y: 2.2, width: 2.6, height: 2.6))
    }

    if P.name == "ko" {
        // stars going round his head
        for i in 0..<3 {
            let a = S.phase * 2.2 + Double(i) * 2.0944
            let sx = P.headX + cos(a) * 8.0
            let sy = P.headY - 11.0 + sin(a) * 2.5
            for (w, col) in [(3.3, RGB(r: 24, g: 24, b: 28)), (1.5, RGB(r: 255, g: 214, b: 0))] {
                g.setStrokeColor(cgc(col))
                g.setLineWidth(w)
                g.beginPath()
                g.move(to: CGPoint(x: sx - 2.6, y: sy)); g.addLine(to: CGPoint(x: sx + 2.6, y: sy))
                g.move(to: CGPoint(x: sx, y: sy - 2.6)); g.addLine(to: CGPoint(x: sx, y: sy + 2.6))
                g.strokePath()
            }
        }
    }
    if F.on {
        // the hits he can still take
        g.setFillColor(cgc(halo))
        g.fill(CGRect(x: 7, y: 3, width: 30, height: 4.5))
        g.setFillColor(cgc(RGB(r: 90, g: 24, b: 24)))
        g.fill(CGRect(x: 8, y: 4, width: 28, height: 2.5))
        g.setFillColor(cgc(RGB(r: 232, g: 52, b: 52)))
        g.fill(CGRect(x: 8, y: 4, width: 28 * Double(max(0, F.hp)) / Double(F.maxHp), height: 2.5))
    }
    g.restoreGState()

    if S.symbol || S.symFlash > 0 { drawSymbolBox(g) }      // the cheer hop must not move it
}

// The Flash-style wrapper: the selection rectangle plus the little registration
// cross at whichever of the nine points you picked in the dialog.
func drawSymbolBox(_ g: CGContext) {
    let box = CGRect(x: 1.5, y: 1.5, width: DW - 3.0, height: DH - 3.0)
    // the box takes the figure's colour when he is one of the hidden names,
    // and stays Flash blue when he is just a symbol
    let tint = S.ink ?? FLASH_BLUE
    if S.symFlash > 0 {
        let a = Double(Int(80.0 * Double(S.symFlash) / Double(max(1, S.symFlashMax)))) / 255.0
        g.setFillColor(cgc(tint, a))
        g.fill(box)
    }
    if !S.symbol { return }

    // a white halo so the thin line survives a light wallpaper, then the line
    let haloColor = CGColor(red: 1, green: 1, blue: 1, alpha: 150.0 / 255.0)
    g.setLineCap(.butt)
    g.setStrokeColor(haloColor); g.setLineWidth(3.2); g.stroke(box)
    g.setStrokeColor(cgc(tint)); g.setLineWidth(1.3); g.stroke(box)

    let rx = Double(box.minX) + Double(box.width) * (Double(S.symReg % 3) / 2.0)
    let ry = Double(box.minY) + Double(box.height) * (Double(S.symReg / 3) / 2.0)
    let arm = 3.0
    for (w, col) in [(3.2, haloColor), (1.7, cgc(tint))] {
        g.setStrokeColor(col)
        g.setLineWidth(w)
        g.beginPath()
        g.move(to: CGPoint(x: rx - arm, y: ry)); g.addLine(to: CGPoint(x: rx + arm, y: ry))
        g.move(to: CGPoint(x: rx, y: ry - arm)); g.addLine(to: CGPoint(x: rx, y: ry + arm))
        g.strokePath()
    }
}

// ----------------------------------------------------------------------- sparks
// A blow that lands pops a comic-book spark where it hit. His own window is only
// as big as he is, so the spark gets a window of its own, made the first time
// it is needed. Clicks go straight through it, so it never catches one.
let FXS = 72.0                                  // spark window, design units
var fxWin: NSPanel? = nil

final class SparkView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        g.clear(bounds)
        drawSpark(g)
    }
}

// the points of an eight-pointed star round the middle of the spark window
func starPoints(_ ro: Double, _ rin: Double, _ rot: Double) -> [CGPoint] {
    let m = FXS / 2.0
    var pts: [CGPoint] = []
    for i in 0..<16 {
        let r = i % 2 == 0 ? ro : rin
        let a = Double(i) * Double.pi / 8 + rot
        pts.append(CGPoint(x: m + cos(a) * r, y: m + sin(a) * r))
    }
    return pts
}

func drawSpark(_ g: CGContext) {
    let t = 1.0 - Double(F.fx) / Double(FX_LEN)
    let a = 1.0 - t * t
    let ro = 9.0 + 22.0 * t.squareRoot()
    g.saveGState()
    defer { g.restoreGState() }
    g.scaleBy(x: SC, y: SC)
    g.setLineJoin(.round)
    g.beginPath()
    g.addLines(between: starPoints(ro, ro * 0.45, F.fxRot))
    g.closePath()
    g.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: a))
    g.setStrokeColor(CGColor(red: 24.0 / 255, green: 24.0 / 255, blue: 28.0 / 255, alpha: a))
    g.setLineWidth(1.8)
    g.drawPath(using: .fillStroke)
    g.beginPath()
    g.addLines(between: starPoints(ro * 0.55, ro * 0.25, F.fxRot + 0.2))
    g.closePath()
    g.setFillColor(CGColor(red: 1, green: 204.0 / 255, blue: 0, alpha: a))
    g.fillPath()
}

// one frame of the spark: it pops out and fades, then the window hides
func drawFx() {
    if fxWin == nil {
        let w = (FXS * SC).rounded()
        let p = overlayPanel(w, w)
        p.ignoresMouseEvents = true
        p.contentView = SparkView(frame: NSRect(x: 0, y: 0, width: w, height: w))
        fxWin = p
    }
    guard let p = fxWin else { return }
    F.fx -= 1
    if F.fx <= 0 { p.orderOut(nil); return }
    let w = Double(p.frame.width)
    p.setFrameOrigin(cocoaOrigin((F.fxX - w / 2).rounded(), (F.fxY - w / 2).rounded(), w))
    p.contentView?.needsDisplay = true
    if !p.isVisible { p.orderFrontRegardless() }
    MY_WINDOWS.insert(p.windowNumber)
}

// ------------------------------------------------------------------------- grip
// While he has hold of your pointer, a small pad you can barely see sits under
// it. A click lands on the pad and never on the program underneath, so a click
// meant to fight him off cannot press something by accident; it counts as a
// hit on him instead, and he lets go. Made the first time it is needed.
let GRIP = (120 * SC).rounded()
var gripWin: NSPanel? = nil

final class GripView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.012).setFill()   // invisible, but there to catch the click
        bounds.fill()
    }
    override func mouseDown(with event: NSEvent) { gripClicked() }
    override func rightMouseDown(with event: NSEvent) { gripClicked() }
}

func gripClicked() {
    releasePointer()
    if F.on { hitHim(cursorPos()) }
}

func showGrip(_ x: Double, _ y: Double) {
    if gripWin == nil {
        let p = overlayPanel(GRIP, GRIP)
        p.ignoresMouseEvents = false                // catching clicks is its job
        p.contentView = GripView(frame: NSRect(x: 0, y: 0, width: GRIP, height: GRIP))
        gripWin = p
    }
    guard let p = gripWin else { return }
    p.setFrameOrigin(cocoaOrigin((x - GRIP / 2).rounded(), (y - GRIP / 2).rounded(), GRIP))
    if !p.isVisible { p.orderFrontRegardless() }
    MY_WINDOWS.insert(p.windowNumber)
}

func hideGrip() { gripWin?.orderOut(nil) }

// ----------------------------------------------------------------- prop panels
// a Flash panel of rows: what he throws when none of your windows will do
final class PropView: NSView {
    var rows: [String] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 238.0 / 255, alpha: 1).setFill()
        bounds.fill()
        let rowH = 22 * SC, pad = 6 * SC
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12 * SC),
            .foregroundColor: NSColor.black
        ]
        let width = Double(bounds.width)
        for (i, row) in rows.enumerated() {
            let y = pad + Double(i) * rowH
            if i % 2 == 0 {
                NSColor(white: 250.0 / 255, alpha: 1).setFill()
                NSRect(x: pad, y: y, width: width - 2 * pad, height: rowH).fill()
            }
            NSColor(red: 0, green: 153.0 / 255, blue: 1, alpha: 1).setFill()
            NSRect(x: pad * 2, y: y + rowH * 0.3, width: rowH * 0.4, height: rowH * 0.4).fill()
            (row as NSString).draw(at: NSPoint(x: pad * 3 + rowH * 0.4, y: y + rowH * 0.12), withAttributes: attrs)
        }
    }
}

// They show up without taking the focus from whatever you are using, float
// above your windows, and stay out of the Dock and the window switcher.
func makePropPanel(_ title: String, _ rows: [String], _ w: Double, _ h: Double) -> NSPanel {
    let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: max(40, h - 22)),
                    styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
    p.title = title
    p.level = .floating
    p.isFloatingPanel = true
    p.hidesOnDeactivate = false
    p.becomesKeyOnlyIfNeeded = true
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    let v = PropView(frame: NSRect(x: 0, y: 0, width: w, height: max(40, h - 22)))
    v.rows = rows
    p.contentView = v
    return p
}
