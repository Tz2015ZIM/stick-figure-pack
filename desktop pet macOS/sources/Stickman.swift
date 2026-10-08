// Stickman.swift
// Everything he does: the world he walks on, his moves, his friends and his
// fights. A close port of the behaviour in stickman.ps1, function for
// function, so the two can be kept in step.

import Cocoa

// ------------------------------------------------------------------------ scale
// He is drawn in 96-dpi design units. macOS already works in points, the same
// physical size on every display, so a design unit is simply a point here.
let SC = 1.0

let DW = 44.0, DH = 68.0        // sprite box, design units
let DCX = 22.0, DFT = 62.0      // centre line and foot line, design units

let BOXW = (DW * SC).rounded()
let BOXH = (DH * SC).rounded()
let CX = DCX * SC
let FOOT = DFT * SC

let GRAVITY = 0.85 * SC
let SPEED   = 1.9 * SC
let CLIMB   = 2.0 * SC
let VMAX    = 26.0 * SC
let REACH   = 14.0 * SC     // how far ahead he notices a wall
let MINWALL = 22.0 * SC     // shortest wall worth climbing
let EDGE    = 6.0 * SC      // how close to a ledge end he gets before deciding
let HUG     = 7.0 * SC      // how far off the wall his body sits while climbing
let STEPIN  = 10.0 * SC     // where he plants his feet after topping out
let NOTICE  = 120.0 * SC    // how close the pointer has to be before he reacts
let OPEN_GAP = 1500         // frames between shortcut launches, about 45 seconds

let PLAIN = "Stick figure"  // the name Activity Monitor shows for his plain self

// Random.Next(lo, hi): lo up to but not including hi
func rnd(_ lo: Int, _ hi: Int) -> Int { hi > lo ? Int.random(in: lo..<hi) : lo }
func sgn(_ v: Double) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }
// [int] in PowerShell: rounded, and never a crash on a bad number
func ri(_ v: Double) -> Int { v.isFinite && abs(v) < 1e15 ? Int(v.rounded()) : 0 }
// turns him towards dx, unless it is dead ahead
func face(_ dx: Double) { let s = sgn(dx); if s != 0 { S.dir = s } }

struct RGB { var r: Double, g: Double, b: Double }

// ----------------------------------------------------------------------- state
struct Ledge {
    var h: Int                      // window number; 0 ground, -1.. buttons, -1000.. icons, INK_H ink
    var l: Double, t: Double, r: Double, b: Double
    var ground = false
    var maxed = false
    var btn = false
    var uia = -1                    // the scanner's index for a button
    var icon = false
    var name = ""                   // desktop icons carry their label
    var ink = false
}

final class Stick {
    var x = 400.0, y = 200.0        // x = centre of body, y = the surface under his feet
    var vx = 0.0, vy = 0.0
    var state = "fall"              // walk fall climb idle sit wave knock push press ...
    var dir = 1                     // 1 right, -1 left
    var phase = 0.0                 // animation clock
    var ledge: Ledge? = nil         // what he is standing on
    var wall: Ledge? = nil          // what he is climbing / knocking on
    var timer = 0                   // frames left in the current one-shot pose
    var cool = 0                    // frames until he will notice the pointer again
    var tick = 0
    var drag = false
    var grabX = 0.0, grabY = 0.0
    var lastX = 0.0
    var dragged = 0.0
    var ledges: [Ledge] = []
    var ignore = 0                  // window top to fall straight through, while diving in
    var mdown = false               // left button was already down last frame
    var tx = 0.0, ty = 0.0          // where you last clicked, which he runs to
    var chase = 0                   // frames left before he gives up on getting there
    var ly0 = 0.0                   // height he leapt from, to grab a window corner
    var icons: [(rect: CGRect, name: String)] = []   // desktop icons, from the scanner
    var desk: [String: URL] = [:]   // icon label -> the file it points at
    var deskAt = -99999             // tick the desktop folder was last read
    var openOn = true               // allowed to open a desktop icon he stamps on
    var lastOpen = -99999           // tick of the last launch, to keep it occasional
    var shove = true                // allowed to push windows around
    var click = false               // allowed to really press the buttons he stands on
    var throwOn = true              // allowed to throw windows at the pointer in a fight
    var grabPtr = true              // allowed to grab the pointer and drag it off in a fight
    var symbol = false              // he is wrapped in a symbol box, Flash style
    var symName = ""                // what the instance was named in the dialog
    var symType = "Movie Clip"      // Movie Clip / Button / Graphic
    var symReg = 4                  // registration point, 0..8 across the 3x3 grid
    var symNum = 1                  // next default name, Symbol 1, Symbol 2, ...
    var symFlash = 0                // frames left of the flash after converting
    var symFlashMax = 14            // how long that flash was, so it can fade out
    var figure = ""                 // the Alan Becker figure he was named after
    var ink: RGB? = nil             // that figure's colour, or nil for his own
    var pending = ""                // his new figure's move, waiting for him to settle
    var pendTTL = 0                 // frames it waits before being given up on
    var peers: [Peer] = []          // the other stickmen running right now
    var with = -1                   // slot of the one he is meeting, or -1
    var act = ""                    // what the two of them are doing together
    var meetT = 0                   // frames spent getting to each other
    var waiting = false             // stood still, waiting for his friend to arrive
    var social = 300                // frames until he goes looking for company again
    var chasePeer = -1              // slot of the friend he is chasing in a game of tag
}
let S = Stick()

let SCAN = Scanner()

// ------------------------------------------------------------------ paint ink
// Ink is ground and walls (see Ink.swift). Standing on ink he follows the
// stroke's top pixel by pixel: up small steps, down slopes, stopped by
// anything taller than a step, and he falls off where it ends.
let INK_H    = -7777
let INK_UP   = ri(7 * SC)       // tallest bump he just steps over
let INK_DOWN = ri(12 * SC)      // deepest dip he walks down rather than falls
let INK_BODY = ri(46 * SC)      // how tall he is, for strokes in front of his face

func newInkLedge(_ y: Int) -> Ledge {
    let b = Ink.bounds(ri(S.x), y)
    return Ledge(h: INK_H, l: b.l, t: Double(y), r: b.r, b: b.b, ink: true)
}

// Move him dx along the ink he stands on. Returns "ok", "wall" (he did not
// move) or "fall" (he stepped off the end and is now falling).
@discardableResult
func stepInk(_ dx: Double) -> String {
    let nx = S.x + dx
    let ix = ri(nx)
    let iy = ri(S.y)
    let lead = ix + sgn(dx) * ri(4 * SC)
    if Ink.blocked(lead, iy - INK_BODY, iy - INK_UP - 1) { return "wall" }
    var gy = -1
    if Ink.inside(ix, iy) { gy = Ink.floor(ix, iy - INK_UP, iy + INK_DOWN) }
    S.x = nx
    if gy < 0 {
        S.ledge = nil; S.state = "fall"; S.vy = 0; S.vx = dx * 0.6
        return "fall"
    }
    S.y = Double(gy)
    S.ledge = newInkLedge(gy)
    return "ok"
}

func openShortcut(_ label: String) -> Bool {
    let k = label.trimmingCharacters(in: .whitespaces).lowercased()
    guard !k.isEmpty, let url = S.desk[k] else { return false }     // the hard disk and friends match nothing
    return NSWorkspace.shared.open(url)
}

func getGround() -> Ledge {
    let a = workingArea(S.x, S.y)
    return Ledge(h: 0, l: a.left + 4 * SC, t: a.bottom, r: a.right - 4 * SC, b: 1e6, ground: true)
}

// Rebuild the world, and carry him along with whatever he was holding on to,
// so he rides a window when you drag it instead of being left in mid-air.
func updateWorld() {
    let old = S.ledge
    let ow = S.wall

    WINS = windowList()
    STICK_PIDS = Set(Peers.others().map { Int32(truncatingIfNeeded: $0.pid) })
    STICK_PIDS.insert(getpid())
    let wins = standableWindows()
    var byId: [Int: Win] = [:]
    for w in wins { byId[w.id] = w }
    WIN_BY_ID = byId
    var list: [Ledge] = wins.map { Ledge(h: $0.id, l: $0.left, t: $0.top, r: $0.right, b: $0.bottom, maxed: $0.maxed) }

    // Buttons, but only in the window he is standing on or wandering over, so
    // the scanner is not walking every control on the desktop.
    var near: Win? = nil
    if let l = S.ledge, !l.ground, !l.btn {
        near = byId[l.h]
    } else {
        for w in wins where S.x >= w.left - 40 * SC && S.x <= w.right + 40 * SC &&
            S.y >= w.top - 40 * SC && S.y <= w.bottom + 40 * SC {
            near = w
            break
        }
    }
    SCAN.setTarget(near)
    if near != nil {
        for (i, r) in SCAN.currentButtons().enumerated() {
            list.append(Ledge(h: -1 - i, l: Double(r.minX), t: Double(r.minY), r: Double(r.maxX), b: Double(r.maxY),
                              btn: true, uia: i))
        }
    }

    // desktop icons, but only the ones actually in view - an icon under a
    // window is not something he can stand on
    if S.tick % 90 == 0 { SCAN.setFinder(finderPid()) }
    S.icons = SCAN.currentIcons()
    if S.tick - S.deskAt >= 900 { S.desk = desktopFiles(); S.deskAt = S.tick }
    for (i, ic) in S.icons.enumerated() {
        let cx = Double(ic.rect.midX), cy = Double(ic.rect.midY)
        var hidden = false
        for w in wins where cx >= w.left && cx <= w.right && cy >= w.top && cy <= w.bottom { hidden = true; break }
        if hidden { continue }
        // the picture, a square across the middle: the bit he can stand on
        let side = Double(min(ic.rect.width, ic.rect.height))
        let top = Double(ic.rect.minY)
        list.append(Ledge(h: -1000 - i, l: cx - side / 2, t: top, r: cx + side / 2, b: top + side, icon: true, name: ic.name))
    }

    list.append(getGround())
    S.ledges = list

    // the paint window's ink only counts where it is the window in front, so
    // a stroke hidden behind another window cannot hold him up
    let pw = Ink.target
    var live = false
    if pw != 0 {
        var decided = false
        for w in wins where S.x >= w.left && S.x <= w.right && S.y >= w.top && S.y <= w.bottom {
            live = w.id == pw
            decided = true
            break
        }
        if !decided {
            for w in wins where w.id == pw && S.x >= w.left - 80 * SC && S.x <= w.right + 80 * SC &&
                S.y >= w.top - 80 * SC && S.y <= w.bottom + 80 * SC {
                live = true
            }
        }
    }
    Ink.active = live
    Ink.fx = ri(S.x)
    Ink.fy = ri(S.y)
    let moved = Ink.sync()

    if S.state == "fall" || S.drag { return }

    if let o = old, o.ink, S.state != "climb", S.state != "leap" {
        // ride the paint window when it is dragged, then find the stroke under him again
        if Ink.inCanvas(ri(S.x), ri(S.y)) { S.x += moved.dx; S.y += moved.dy }
        let iy = ri(S.y)
        let gy = Ink.floor(ri(S.x), iy - INK_UP, iy + INK_DOWN)
        if gy < 0 { S.ledge = nil; S.state = "fall"; S.vy = 0; return }
        S.y = Double(gy)
        S.ledge = newInkLedge(gy)
        return
    }

    if S.state == "climb" {
        guard let w = ow, let m = S.ledges.first(where: { $0.h == w.h }) else {
            S.state = "fall"; S.vy = 0; S.wall = nil
            return
        }
        S.x += S.dir > 0 ? m.l - w.l : m.r - w.r
        S.wall = m
        if S.y < m.t || S.y > m.b { S.state = "fall"; S.vy = 0; S.wall = nil }
        return
    }

    guard let o = old else { S.state = "fall"; return }

    if o.ground { let g = getGround(); S.ledge = g; S.y = g.t; return }

    guard let match = S.ledges.first(where: { $0.h == o.h }) else {
        S.ledge = nil; S.state = "fall"; S.vy = 0
        return
    }
    S.x += match.l - o.l        // ride it
    S.y = match.t
    S.ledge = match
    if S.x < match.l || S.x > match.r { S.ledge = nil; S.state = "fall"; S.vy = 0 }
}

// A window edge directly in front of him, tall enough to be worth bothering with.
func findWall() -> Ledge? {
    for l in S.ledges {
        if l.ground { continue }
        let minH = (l.btn || l.icon) ? 9 * SC : MINWALL     // a button or icon is a low step up
        if l.t > S.y - minH { continue }                    // too short
        if l.b < S.y - 4 * SC { continue }                  // ends above his feet
        if S.dir > 0 {
            if l.l >= S.x && l.l <= S.x + REACH { return l }
        } else {
            if l.r <= S.x && l.r >= S.x - REACH { return l }
        }
    }
    return nil
}

// A button sitting inside the window he is standing on, close enough below to
// drop down onto.
func findDropTarget(_ l: Ledge) -> Ledge? {
    for b in S.ledges where b.btn {
        if b.t <= l.t + 12 * SC || b.t >= l.b { continue }
        if S.x >= b.l + EDGE && S.x <= b.r - EDGE { return b }
    }
    return nil
}

// A window floating clear of the ground has no edge he can walk into, so he
// jumps up and grabs its bottom corner instead, and climbs from there.
func findReach() -> Ledge? {
    for l in S.ledges {
        if l.ground || l.btn { continue }
        if l.b >= S.y - 8 * SC { continue }         // not above him
        if l.b < S.y - 240 * SC { continue }        // out of jumping range
        if l.t > l.b - 24 * SC { continue }         // no side worth climbing
        if S.dir > 0 {
            if l.l >= S.x - REACH && l.l <= S.x + REACH { return l }
        } else {
            if l.r <= S.x + REACH && l.r >= S.x - REACH { return l }
        }
    }
    return nil
}

func landOn(_ l: Ledge) {
    S.ledge = l
    S.y = l.t
    S.vy = 0
    S.state = "walk"
    S.wall = nil
    S.ignore = 0
    F.air = ""
    if F.on { return }                      // mid-fight he never stamps on buttons or icons
    if (l.btn || l.icon) && rnd(0, 3) == 0 {
        S.state = "press"; S.timer = 42; S.phase = 0
    } else if S.chase > 0 {
        S.state = "chase"                   // he was on his way to you, carry on
    }
}

func startClimb(_ wall: Ledge) {
    S.wall = wall
    S.state = "climb"
    S.x = S.dir > 0 ? wall.l - HUG : wall.r + HUG
    S.phase = 0
}

func startLeap(_ up: Ledge) {
    S.wall = up
    S.state = "leap"
    S.timer = 18
    S.ly0 = S.y
    S.phase = 0
    S.x = S.dir > 0 ? up.l - HUG : up.r + HUG
}

func cursorDistance() -> (d: Double, x: Double) {
    let c = cursorPos()
    let dx = c.x - S.x
    let dy = c.y - (S.y - 30 * SC)
    return (d: (dx * dx + dy * dy).squareRoot(), x: c.x)
}

// A window edge anywhere nearby that he could climb, so he goes looking for
// something to stand on instead of pacing the Dock all day.
func findClimb() -> Double? {
    var best: Double? = nil
    var bd = 700 * SC
    for l in S.ledges {
        if l.ground || l.btn { continue }
        if l.t > S.y - MINWALL { continue }
        if l.b < S.y - 4 * SC { continue }
        for e in [l.l, l.r] {
            let d = abs(e - S.x)
            if d < bd && d > REACH { bd = d; best = e }
        }
    }
    return best
}

// ---------------------------------------------------------------- other stickmen
// Each copy of him publishes a slot (see Peers.swift), so they can see one
// another. A meeting is a handshake done entirely through those slots: one of
// them sets 'with' to the other and walks over, the other notices it is
// wanted, sets 'with' back, and once both are close they play the act together.
var ME = -1
let STATE_CODE: [String: Int] = [
    "walk": 1, "fall": 2, "climb": 3, "idle": 4, "sit": 5, "wave": 6, "knock": 7, "push": 8,
    "press": 9, "chase": 10, "cheer": 11, "leap": 12, "meet": 13, "social": 14
]
let ST_WAVE = 6, ST_CHEER = 11, ST_MEET = 13, ST_SOCIAL = 14, ST_DRAG = 15
let ACTS = ["", "greet", "highfive", "chat", "dance", "tag"]
let ACT_TIME: [String: Int] = ["greet": 60, "highfive": 40, "chat": 150, "dance": 80, "tag": 24]
let ACT_GAP: [String: Double] = ["greet": 34, "highfive": 24, "chat": 32, "dance": 30, "tag": 22]  // how close they stand
let SOCIAL_POSE: [String: String] = ["greet": "wave", "highfive": "hifive", "chat": "chat", "dance": "cheer", "tag": "knock"]

func publishSelf() {
    let code = S.drag ? ST_DRAG : (STATE_CODE[S.state] ?? 0)
    Peers.publish(ri(S.x), ri(S.y), S.dir, code, S.with, ACTS.firstIndex(of: S.act) ?? -1)
    ME = Peers.me
}

func getPeer(_ slot: Int) -> Peer? { S.peers.first { $0.slot == slot } }

// free to be walked up to: pottering about and not already with someone
func testFree(_ p: Peer) -> Bool { p.with < 0 && (p.state == 1 || p.state == 4 || p.state == 5) }

func stopMeeting() {
    S.with = -1
    S.act = ""
    S.waiting = false
    S.social = rnd(450, 1200)
    if S.state == "meet" || S.state == "social" { S.state = "walk" }
}

func startMeeting(_ p: Peer, _ act: String) {
    S.with = p.slot
    S.act = act
    S.state = "meet"
    S.meetT = 0
    S.waiting = false
    S.phase = 0
    if p.x != ri(S.x) { face(Double(p.x) - S.x) }
}

func stepFriends() {
    S.peers = Peers.others()
    if S.social > 0 { S.social -= 1 }

    // something else took him out of the meeting: a click, a drag, a fall
    if S.with >= 0 && S.state != "meet" && S.state != "social" { stopMeeting() }
    if S.peers.isEmpty || ME < 0 { return }
    if S.with >= 0 || S.ledge == nil { return }
    if !(S.state == "walk" || S.state == "idle" || S.state == "sit" || S.state == "wave") { return }

    // somebody is on their way over to see him
    for p in S.peers where p.with == ME && p.state == ST_MEET && abs(Double(p.y) - S.y) < 8 * SC {
        startMeeting(p, ACTS[max(0, min(ACTS.count - 1, p.act))])
        return
    }
    if S.state == "wave" { return }

    var same: Peer? = nil       // nearest friend on the same ledge
    var sd = 1e9
    var far: Peer? = nil        // nearest one anywhere else
    var fd = 1e9
    for p in S.peers {
        let dx = Double(p.x) - S.x
        let d = abs(dx)
        let level = abs(Double(p.y) - S.y) < 6 * SC

        // walking straight into each other: step back round instead of through
        if level && S.state == "walk" && d < 16 * SC && sgn(dx) == S.dir && p.dir == -S.dir { S.dir = -S.dir }

        // one of them is cheering or waving: join in, facing them
        if S.social <= 0 && S.tick % 10 == 0 && d < 300 * SC &&
            (p.state == ST_CHEER || p.state == ST_WAVE) && rnd(0, 3) == 0 {
            face(dx)
            S.state = p.state == ST_CHEER ? "cheer" : "wave"
            S.timer = 55; S.phase = 0; S.social = 400
            return
        }

        if !testFree(p) { continue }
        if level {
            if d < sd { sd = d; same = p }
        } else if d < fd {
            fd = d; far = p
        }
    }

    // a friend stood about: look at them
    if S.state == "idle", let s = same, sd < 260 * SC, s.x != ri(S.x) { face(Double(s.x) - S.x) }

    if S.social > 0 || S.tick % 15 != 0 { return }

    // close by on the same ledge: go over and do something together
    if let s = same, sd < 280 * SC, rnd(0, 3) == 0 {
        startMeeting(s, ACTS[rnd(1, ACTS.count)])
        return
    }
    // out of reach: a wave across the gap, which they will usually return
    if let fr = far, fd < 420 * SC, rnd(0, 6) == 0 {
        if fr.x != ri(S.x) { face(Double(fr.x) - S.x) }
        S.state = "wave"; S.timer = 60; S.phase = 0; S.social = 500
    }
}

// ------------------------------------------------------------------------ fight
// Fight mode, ticked in the Convert to Symbol dialog: Animator vs. Animation,
// with your pointer as the animator. He hunts it down, climbing whatever is in
// the way, and throws punches, kicks and flying kicks at it; a blow that lands
// pops a spark and knocks the pointer back a little. When the pointer is out of
// reach he picks up a window instead and throws it at it, and with the pointer
// far off that is his main weapon: he runs to windows along his ledge, jumps
// for ones hanging above him, and throws them one after another, up to three
// in the air at once. Click him to hit back - eight hits and he is out, and
// when he comes round he gives up.
//
// It is all show. While he fights he never presses buttons or opens icons. A
// window he throws is only ever moved: never closed, resized, minimised or
// clicked, never Activity Monitor or anything floating above the rest, and it
// stays on screen. When the fight ends every one of them glides back to where
// it was, unless you have moved it yourself since. The pointer is only nudged,
// and a window only flies, while no mouse button is down, so nothing you are
// dragging gets pulled somewhere else. Esc ends it.
final class Flyer {                 // a window in his hands or in the air
    let h: Int
    var ol: Double, ot: Double      // visible frame inside the full rectangle
    var fw: Double, fh: Double
    var hx: Double, hy: Double      // where it sat when he grabbed it
    var x: Double, y: Double        // where it is now, frame top-left
    var vx = 0.0, vy = 0.0
    var t = 0
    var up: Bool, jump: Bool
    var g: Double
    var len: Int
    var hit = false
    init(h: Int, ol: Double, ot: Double, fw: Double, fh: Double, hx: Double, hy: Double,
         up: Bool, jump: Bool, g: Double, len: Int) {
        self.h = h; self.ol = ol; self.ot = ot; self.fw = fw; self.fh = fh
        self.hx = hx; self.hy = hy; self.x = hx; self.y = hy
        self.up = up; self.jump = jump; self.g = g; self.len = len
    }
}

// a window he can get his hands on: where he stands to grab it, which way he
// faces, held overhead rather than by its side, out of reach so he jumps for it
struct ThrowTarget { var l: Ledge; var x: Double; var dir: Int; var up: Bool; var jump: Bool }

final class Fight {
    var on = false
    var hp = 8, maxHp = 8           // hits he can still take before he is knocked out
    var ko = false                  // knocked out: he lies down as soon as he lands
    var intro = false               // the first thing he does is square up to you
    var inv = 0                     // frames before he can be hit again
    var hurt = 0                    // frames left of the red flash
    var cool = 0                    // frames before his next attack
    var combo = 0                   // jab, cross, jab...
    var air = ""                    // how he looks in the air: flykick, hurt, flip
    var hitDone = false             // a flying kick lands once at most
    var gloat = false               // taunt once the current blow is over
    var kx = 0.0, ky = 0.0, kn = 0  // knock-back still owed to the pointer
    var fx = 0, fxX = 0.0, fxY = 0.0, fxRot = 0.0   // the spark: frames left, where, angle
    var px = 0.0, py = 0.0          // the pointer last frame, to see you swipe at him
    var dodge = 0                   // frames before he will dodge again
    var fly: Flyer? = nil           // the window in his hands
    var flying: [Flyer] = []        // the windows he has thrown, still in the air
    var fetch: ThrowTarget? = nil   // the window he is walking over to pick up
    var throwCool = 0               // frames before he will throw another
    var far = false                 // the pointer is a long way off: time for windows
    var skip = Set<Int>()           // windows that would not let him move them
    var kd = 0.62                   // how fast the knock-back dies away, per frame
    var grab = false                // he has hold of your pointer
    var grabCool = 0                // frames before he will grab it again
    var gx = 0.0, gy = 0.0          // where he last put the pointer
    var sx = 0.0, sy = 0.0          // where it was when he grabbed it
    var run = 1                     // the way he is running off with it
    var struggle = 0.0              // how hard you have been pulling it back
}
let F = Fight()

let FIGHT_STATES: Set<String> = ["hunt", "guard", "taunt", "punch", "kick", "ko", "fetch", "heave", "hurl", "haul", "fling"]
let FX_LEN = 10

// every window he has thrown, by number: where it was before the fight (x0, y0)
// and where he last put it (lx, ly), so it can be put back afterwards
final class Thrown {
    let h: Int
    let x0: Double, y0: Double
    var lx: Double, ly: Double
    init(h: Int, x0: Double, y0: Double) { self.h = h; self.x0 = x0; self.y0 = y0; lx = x0; ly = y0 }
}
var THROWN: [Int: Thrown] = [:]

let WGRAV      = 0.9 * SC       // windows fall a little faster than he does
let HEAVE_LEN  = 20             // frames of wind-up before a window flies
let JUMP_RISE  = 10             // jumping for a window: frames going up,
let JUMP_HANG  = 6              // hanging off its bottom edge,
let JUMP_PULL  = 12             // and dropping back down with it
let REACH_UP   = 240 * SC       // highest window bottom, above his feet, he jumps for
let FAR_OFF    = 300 * SC       // the pointer further off than this: the windows come out
let FETCH_FAR  = 700 * SC       // and he goes this far along his ledge to get one
let MAX_FLYING = 3              // windows in the air at once

let GRAB_HOLD   = 84            // frames he runs about with your pointer before throwing it
let GRAB_SNATCH = 8             // the first of them, reaching out and taking it
let FLING_LEN   = 14            // the throw at the end
let FLING_AT    = 5             // the frame of the throw he lets go on
let STRUGGLE    = 170.0         // how hard you have to pull, design units, to get it back

func startFight() {
    let c = cursorPos()
    F.on = true; F.hp = F.maxHp; F.ko = false; F.intro = true
    F.inv = 0; F.cool = 20; F.air = ""; F.px = c.x; F.py = c.y
    F.fly = nil; F.fetch = nil; F.flying.removeAll(); F.throwCool = 90     // fists first
    F.grab = false; F.grabCool = 60
    S.pending = ""                          // squaring up is his entrance now
    S.chase = 0; S.chasePeer = -1
    if S.with >= 0 { stopMeeting() }
    syncSymbolItem()
}

func endFight() {
    F.on = false; F.ko = false; F.air = ""; F.kn = 0
    F.fly = nil; F.fetch = nil; F.flying.removeAll()      // whatever he threw goes back, see stepTidy
    for p in PROPS { removeProp(p) }                        // his own panels just go
    releasePointer()
    if FIGHT_STATES.contains(S.state) { S.state = "walk"; S.phase = 0 }
    syncSymbolItem()
}

func popSpark(_ x: Double, _ y: Double) {
    F.fx = FX_LEN; F.fxX = x; F.fxY = y; F.fxRot = Double.random(in: 0..<1)
}

// his fist or foot, or a window he threw, found the pointer: it is knocked
// (kx, ky) points the first frame, and a little less each frame after
func landBlow(_ kx: Double? = nil, _ ky: Double? = nil) {
    let c = cursorPos()
    popSpark(c.x, c.y)
    if !mouseHeld() {
        F.kx = kx ?? Double(S.dir) * 14 * SC
        F.ky = ky ?? -5 * SC
        F.kn = 6; F.kd = 0.62
    }
    if rnd(0, 4) == 0 { F.gloat = true }
}

// ------------------------------------------------------------- throwing windows
// A window he can get his hands on from somewhere on the ledge he is standing
// on, within range of him, or nil. Nothing maximised, nothing too big to
// lift, nothing hanging off the screen or hidden behind other windows,
// nothing already in the air, and nothing that fails winThrowable.
func findThrowable(_ range: Double) -> ThrowTarget? {
    guard let l = S.ledge else { return nil }
    let top = l.ink ? 70 * SC : REACH_UP        // he does not jump off ink
    var best: ThrowTarget? = nil
    var bd = 1e9
    for w in S.ledges {
        if w.ground || w.btn || w.icon || w.ink || w.maxed || w.h == l.h { continue }
        if w.t > S.y - 20 * SC || w.b < S.y - top { continue }     // not within his reach
        if testFlying(w.h) { continue }
        let up = w.b < S.y - 38 * SC
        let jump = w.b < S.y - 70 * SC
        var gx: Double, px: Double, py: Double
        var dir: Int
        if up {
            gx = max(w.l + 12 * SC, min(w.r - 12 * SC, S.x)); dir = S.dir
            // a spot on it just clear of where he will stand, to see it is not covered
            px = gx + 34 * SC <= w.r - 4 ? gx + 34 * SC : gx - 34 * SC
            py = w.b - 8 * SC
        } else {
            // by its side: the nearer edge, never from in front of it
            let gl = w.l - 14 * SC, gr = w.r + 14 * SC
            if abs(S.x - gl) <= abs(S.x - gr) { gx = gl; dir = 1 } else { gx = gr; dir = -1 }
            px = dir > 0 ? w.l + 30 * SC : w.r - 30 * SC
            py = max(w.t + 8 * SC, min(w.b - 8 * SC, S.y - 30 * SC))
        }
        let d = abs(gx - S.x)
        if d > range || d >= bd { continue }
        if l.ink {
            if d > 4 * SC { continue }              // he does not walk ink to get there
        } else if gx < l.l + EDGE || gx > l.r - EDGE {
            continue
        }
        if !testThrowable(w) { continue }
        // a window hidden behind others would fly where nobody can see it
        if !windowShowing(w.h, px, py) { continue }
        bd = d
        best = ThrowTarget(l: w, x: gx, dir: dir, up: up, jump: jump)
    }
    return best
}

func testThrowable(_ w: Ledge) -> Bool {
    if F.skip.contains(w.h) { return false }
    let a = workingArea((w.l + w.r) / 2, (w.t + w.b) / 2)
    if w.r - w.l > a.width * 0.7 || w.b - w.t > a.height * 0.7 { return false }
    if w.l < a.left - 2 || w.t < a.top - 2 || w.r > a.right + 2 || w.b > a.bottom + 2 { return false }
    return winThrowable(w.h)
}

func testFlying(_ h: Int) -> Bool { F.flying.contains { $0.h == h } }

// A throw is due: go and get a window. With conjure, when none of yours will
// do, a panel of his own pops up in his hands instead.
func tryThrow(_ range: Double, conjure: Bool = false) -> Bool {
    if !S.throwOn || F.throwCool > 0 || F.fly != nil || F.flying.count >= MAX_FLYING { return false }
    guard let t = findThrowable(range) else {
        if conjure && S.ledge != nil { return conjureProp() }
        return false
    }
    F.fetch = t
    S.state = "fetch"; S.phase = 0
    S.timer = ri(abs(t.x - S.x) / (SPEED * 2.4)) + 40
    S.dir = abs(t.x - S.x) > 2 * SC ? sgn(t.x - S.x) : t.dir
    return true
}

// at the window: take hold of it
@discardableResult
func startHeave(_ t: ThrowTarget) -> Bool {
    let w = t.l
    guard let r = winRect(w.h) else { return false }
    // the first time, or you have moved it since he last had it: this is home
    if let was = THROWN[w.h], abs(r.l - was.lx) <= 3, abs(r.t - was.ly) <= 3 {
        // still where he left it: it keeps its first home
    } else {
        THROWN[w.h] = Thrown(h: w.h, x0: r.l, y0: r.t)
    }
    var len = HEAVE_LEN
    var g = 0.0
    if t.jump {
        len = JUMP_RISE + JUMP_HANG + JUMP_PULL
        g = S.y - 58 * SC - w.b                 // how far he has to jump for his hands to reach it
    }
    F.fly = Flyer(h: w.h, ol: w.l - r.l, ot: w.t - r.t, fw: w.r - w.l, fh: w.b - w.t,
                  hx: w.l, hy: w.t, up: t.up, jump: t.jump, g: g, len: len)
    S.dir = t.dir
    S.state = "heave"; S.timer = len; S.phase = 0
    return true
}

// How high off his ledge he is, n frames into a jump for a window g above his
// reach: up fast, a moment hanging off it, then down again, pulling it.
func getJumpLift(_ n: Int, _ g: Double) -> Double {
    if n <= JUMP_RISE {
        let u = 1.0 - Double(n) / Double(JUMP_RISE)
        return g * (1.0 - u * u)
    }
    if n <= JUMP_RISE + JUMP_HANG { return g }
    let u = min(1.0, Double(n - JUMP_RISE - JUMP_HANG) / Double(JUMP_PULL))
    return g * (1.0 - u * u)
}

// puts window fl at frame top-left (x, y), and notes where it went
func moveHeld(_ fl: Flyer, _ x: Double, _ y: Double) -> Bool {
    guard let w = THROWN[fl.h], let at = winPlace(fl.h, (x - fl.ol).rounded(), (y - fl.ot).rounded()) else { return false }
    w.lx = at.x; w.ly = at.y
    fl.x = x; fl.y = y
    return true
}

// still just where he last put it? If it was closed, or moved by you or by
// the program itself, he lets go of it there
func testHold(_ fl: Flyer) -> Bool {
    guard let w = THROWN[fl.h], let p = winPos(fl.h) else { return false }
    return abs(p.x - w.lx) <= 3 && abs(p.y - w.ly) <= 3
}

// end of the wind-up: it goes, on an arc that meets the pointer where it is now
func launchWindow() {
    guard let fl = F.fly else { S.state = "guard"; return }
    let c = cursorPos()
    let dx = c.x - (fl.x + fl.fw / 2)
    let dy = c.y - (fl.y + fl.fh / 2)
    let n = max(10.0, min(24.0, (dx * dx + dy * dy).squareRoot() / (26 * SC)))
    fl.vx = dx / n
    fl.vy = dy / n - 0.5 * WGRAV * n
    fl.t = 0
    F.flying.append(fl)
    F.fly = nil
    face(c.x - S.x)
    S.state = "hurl"; S.timer = 14; S.phase = 0
    F.throwCool = rnd(120, 240)     // runs down four times as fast with the pointer far off
    F.cool = 16
}

// every frame of a fight: the window in his hands, and every one in the air
func stepThrow() {
    if F.fly == nil && F.flying.isEmpty { return }
    // a mouse button is down: never fight you over a window
    if mouseHeld() { F.fly = nil; F.flying.removeAll(); return }
    if F.fly != nil { stepHeld() }
    for fl in F.flying where !stepFlight(fl) {
        F.flying.removeAll { $0 === fl }
    }
}

// the wind-up, before a window flies
func stepHeld() {
    guard let fl = F.fly else { return }
    // knocked out of his hands, or moved under him
    if S.state != "heave" || !testHold(fl) { F.fly = nil; return }
    let n = fl.len - S.timer + 1            // frames in, as the heave state will count them
    let j = SC * (S.tick % 2 == 0 ? 1.0 : -1.0)
    var x = fl.hx
    var y = fl.hy
    if fl.jump {
        // it rattles while he hangs off it, then comes down with him
        if n > JUMP_RISE + JUMP_HANG { y += fl.g - getJumpLift(n, fl.g) }
        else if n > JUMP_RISE { x += 2 * j }
    } else {
        // it rattles harder and harder, dragged back toward him
        let t = 1.0 - Double(S.timer) / Double(fl.len)
        x = fl.hx - Double(S.dir) * 10 * SC * t * t + (1.0 + 3.0 * t) * j
        y = fl.hy - (fl.up ? 12 * SC * t : 4 * SC * t)
    }
    if !moveHeld(fl, x, y) {
        // it will not let him move it: he gives up on it for good
        F.skip.insert(fl.h)
        F.fly = nil
        S.state = "taunt"; S.timer = 40; S.phase = 0
    }
}

// one frame of a thrown window; false once it has come to rest
func stepFlight(_ fl: Flyer) -> Bool {
    if !testHold(fl) { return false }
    fl.t += 1
    fl.vy += WGRAV
    var x = fl.x + fl.vx
    var y = fl.y + fl.vy
    // the edges of the screen it is over: it bounces off them, it never leaves
    let a = workingArea(x + fl.fw / 2, y + fl.fh / 2)
    if x < a.left {
        x = a.left; fl.vx = -fl.vx * 0.5
    } else if x + fl.fw > a.right {
        x = max(a.left, a.right - fl.fw); fl.vx = -fl.vx * 0.5
    }
    if y < a.top { y = a.top; fl.vy = abs(fl.vy) * 0.3 }
    var rest = false
    if y + fl.fh > a.bottom {
        y = max(a.top, a.bottom - fl.fh)
        fl.vy = fl.vy > 4 * SC ? -fl.vy * 0.35 : 0
        fl.vx *= 0.75
        rest = fl.vy == 0 && abs(fl.vx) < 0.8 * SC
    }
    if !moveHeld(fl, x, y) { return false }

    // it caught the pointer: a spark, and the pointer is knocked the way it flew
    if !fl.hit {
        let c = cursorPos()
        if c.x >= x && c.x <= x + fl.fw && c.y >= y && c.y <= y + fl.fh {
            fl.hit = true
            let sp = max(1.0, (fl.vx * fl.vx + fl.vy * fl.vy).squareRoot())
            landBlow(fl.vx / sp * 18 * SC, fl.vy / sp * 18 * SC)
            fl.vx *= 0.5
        }
    }
    return !(rest || fl.t > 90)
}

// ------------------------------------------------------------------ prop windows
// When none of your windows is one he can throw - they are all maximised, say -
// he makes his own: a little Flash panel pops up in his hands and is thrown
// like any other window. They are his, not yours, so once one has landed it
// hangs about a moment and vanishes, and any left go when the fight ends.
final class Prop {
    let panel: NSPanel
    let h: Int
    var life: Int
    init(panel: NSPanel, h: Int, life: Int) { self.panel = panel; self.h = h; self.life = life }
}
var PROPS: [Prop] = []
let PROP_LINGER = 60            // frames one stays about after it lands
let PROP_KINDS: [(title: String, rows: [String])] = [
    (title: "Library",         rows: ["Symbol 1", "Stick figure", "Tween 1", "Sound 1"]),
    (title: "Properties",      rows: ["Movie Clip", "W: 44    H: 68", "X: 400   Y: 200", "Instance of: Symbol 1"]),
    (title: "Timeline",        rows: ["Layer 1", "Layer 2", "Guide: Layer 1", "Actions"]),
    (title: "Actions - Frame", rows: ["stop();", "this.fight();", "gotoAndPlay(\"attack\");", "trace(\"run\");"]),
    (title: "Color Mixer",     rows: ["#000000", "#FFFFFF", "#0099FF", "#FF0000"]),
    (title: "Tools",           rows: ["Selection", "Pencil", "Brush", "Eraser"])
]

// nothing of yours to throw: a panel appears right in front of him, on the
// side the pointer is on, with a spark, and he takes hold of it
func conjureProp() -> Bool {
    if PROPS.count >= MAX_FLYING { return false }
    let c = cursorPos()
    let w = (220 * SC).rounded(), h = (140 * SC).rounded()
    let a = workingArea(S.x, S.y - 30 * SC)
    var dir = c.x >= S.x ? 1 : -1
    var x = dir > 0 ? S.x + 14 * SC : S.x - 14 * SC - w
    if x < a.left || x + w > a.right {
        dir = -dir                                      // no room that side: the other
        x = dir > 0 ? S.x + 14 * SC : S.x - 14 * SC - w
    }
    x = max(a.left, min(a.right - w, x))
    let y = max(a.top, min(a.bottom - h, S.y - 34 * SC - h / 2))

    let kind = PROP_KINDS[rnd(0, PROP_KINDS.count)]
    let panel = makePropPanel(kind.title, kind.rows, w, h)
    panel.setFrame(NSRect(origin: cocoaOrigin(x, y, h), size: NSSize(width: w, height: h)), display: false)
    panel.orderFrontRegardless()
    let id = panel.windowNumber
    let prop = Prop(panel: panel, h: id, life: PROP_LINGER)
    PROPS.append(prop)
    PROP_PANELS[id] = panel
    MY_WINDOWS.insert(id)

    guard let r = winRect(id) else { removeProp(prop); return false }
    popSpark((r.l + r.r) / 2, (r.t + r.b) / 2)
    let t = ThrowTarget(l: Ledge(h: id, l: r.l, t: r.t, r: r.r, b: r.b), x: S.x, dir: dir, up: false, jump: false)
    if !startHeave(t) { removeProp(prop); return false }
    return true
}

func removeProp(_ p: Prop) {
    THROWN[p.h] = nil                                   // nothing to put back
    p.panel.orderOut(nil)
    p.panel.close()
    PROP_PANELS[p.h] = nil
    MY_WINDOWS.remove(p.h)
    PROPS.removeAll { $0 === p }
}

// every frame: a prop in his hands or in the air stays; one that has landed
// counts down and goes. Closed by you with its close button, it is forgotten.
func stepProps() {
    for p in PROPS {
        if !p.panel.isVisible { removeProp(p); continue }
        let busy = F.on && (F.fly?.h == p.h || testFlying(p.h))
        if busy { p.life = PROP_LINGER; continue }
        p.life -= 1
        if p.life <= 0 { removeProp(p) }
    }
}

// ----------------------------------------------------------- grabbing the pointer
// In reach, now and then he grabs your pointer instead of hitting it, runs off
// dragging it behind him, and throws it. Wiggle or yank the mouse hard enough
// and it comes free; click him (the click lands on him, see the grip window),
// or press Esc, and he lets go. He never takes it, or moves it, while a mouse
// button is down, and he never clicks anything.

func startGrab() {
    let c = cursorPos()
    F.grab = true; F.struggle = 0; F.kn = 0
    F.sx = c.x; F.sy = c.y; F.gx = c.x; F.gy = c.y
    // he runs off with it whichever way there is more room
    if let l = S.ledge, l.r - S.x < S.x - l.l { F.run = -1 } else { F.run = 1 }
    S.state = "haul"; S.timer = GRAB_HOLD; S.phase = 0
}

func releasePointer() {
    if !F.grab { return }
    F.grab = false; F.struggle = 0
    F.grabCool = rnd(150, 270)
    hideGrip()
}

// where his holding hand is, in design units: reaching out for your pointer,
// trailing it behind him as he runs, then swinging it up over his head and
// out in front to throw it. The arm is 15 long, from his shoulder.
func getGrabHand() -> (x: Double, y: Double) {
    var th: Double
    if S.state == "fling" {
        let e = min(1.0, Double(FLING_LEN - S.timer) / Double(FLING_LEN - FLING_AT))
        th = 200.0 - 170.0 * e
    } else if GRAB_HOLD - S.timer < GRAB_SNATCH {
        th = 10.0
    } else {
        th = 200.0
    }
    th *= Double.pi / 180.0
    return (x: 22.0 + Double(S.dir) * (1.0 + 15.0 * cos(th)), y: 27.0 - 15.0 * sin(th))
}

// every frame he has it: it stays in his hand, unless you pull it free
func stepGrab() {
    if !F.on || S.drag || !(S.state == "haul" || S.state == "fling") { releasePointer(); return }
    if mouseHeld() { releasePointer(); return }         // a button is down: hands off
    // anything it moved since he last put it was you, pulling against him
    let c = cursorPos()
    let ux = c.x - F.gx, uy = c.y - F.gy
    F.struggle = F.struggle * 0.85 + (ux * ux + uy * uy).squareRoot()
    if F.struggle > STRUGGLE * SC {
        // you yanked it out of his hand, and he stumbles
        releasePointer()
        S.state = "fall"; F.air = "hurt"; S.wall = nil
        S.vy = -5.0 * SC; S.vx = -Double(S.dir) * 3.0 * SC
        return
    }
    let hd = getGrabHand()
    var x = S.x + (hd.x - DCX) * SC
    var y = S.y + (hd.y - DFT) * SC
    let k = Double(GRAB_HOLD - S.timer) / Double(GRAB_SNATCH)
    if S.state == "haul" && k < 1.0 {
        // still snatching it: it is pulled from where it was into his hand
        x = F.sx + (x - F.sx) * k
        y = F.sy + (y - F.sy) * k
    }
    let at = putCursor(x, y)
    F.gx = at.x; F.gy = at.y
    showGrip(at.x, at.y)
}

// the end of the throw: he lets go and your pointer sails off the way it went
func flingPointer() {
    releasePointer()
    if mouseHeld() { return }
    F.kx = Double(S.dir) * 44 * SC; F.ky = -22 * SC; F.kn = 12; F.kd = 0.8
}

// After a fight every window he threw glides back where it was. One you have
// moved yourself since is left where you put it, and nothing moves while a
// mouse button is down.
func stepTidy() {
    if mouseHeld() { return }
    for (k, w) in THROWN {
        guard let p = winPos(w.h), abs(p.x - w.lx) <= 3, abs(p.y - w.ly) <= 3 else { THROWN[k] = nil; continue }
        let dx = w.x0 - p.x, dy = w.y0 - p.y
        if abs(dx) <= 2 && abs(dy) <= 2 {
            _ = winPlace(w.h, w.x0, w.y0)
            THROWN[k] = nil
            continue
        }
        let nx = p.x + (dx * 0.25).rounded() + Double(sgn(dx))
        let ny = p.y + (dy * 0.25).rounded() + Double(sgn(dy))
        guard let at = winPlace(w.h, nx, ny) else { THROWN[k] = nil; continue }
        w.lx = at.x; w.ly = at.y
    }
}

// he is going away: everything he threw goes straight back
func putWindowsBack() {
    for w in THROWN.values {
        if let p = winPos(w.h), abs(p.x - w.lx) <= 3, abs(p.y - w.ly) <= 3 { _ = winPlace(w.h, w.x0, w.y0) }
    }
    THROWN.removeAll()
}

// you clicked him: he is thrown back, still facing you
func hitHim(_ c: (x: Double, y: Double)) {
    if F.inv > 0 || S.state == "ko" { return }
    popSpark(c.x, c.y)
    F.hp -= 1; F.inv = 12; F.hurt = 12
    if F.hp <= 0 { F.ko = true }
    let away = c.x > S.x ? -1 : 1
    S.dir = -away
    S.state = "fall"; F.air = "hurt"
    S.vy = -7.0 * SC
    S.vx = Double(away) * 5.0 * SC
    S.wall = nil
}

func jumpKick(_ dx: Double, _ dy: Double) {
    // rise just far enough for his foot to meet the pointer at the top
    let h = min(240 * SC, max(40 * SC, -dy - 6 * SC))
    S.vy = -(2 * GRAVITY * h).squareRoot()
    S.vx = max(-9 * SC, min(9 * SC, dx / (-S.vy / GRAVITY)))
    face(dx)
    S.state = "fall"; F.air = "flykick"; F.hitDone = false; S.phase = 0
    F.cool = 10
}

// every frame of a fight, before his state moves him
func stepFightFrame() {
    if F.inv > 0 { F.inv -= 1 }
    if F.hurt > 0 { F.hurt -= 1 }
    if F.cool > 0 { F.cool -= 1 }
    if F.dodge > 0 { F.dodge -= 1 }
    stepThrow()

    // the pointer sliding away from a blow, a little less each frame
    if F.kn > 0 {
        F.kn -= 1
        if mouseHeld() {
            F.kn = 0
        } else {
            let c = cursorPos()
            putCursor(c.x + F.kx, c.y + F.ky)
            F.kx *= F.kd; F.ky *= F.kd
        }
    }

    let c = cursorPos()
    let swipe = ((c.x - F.px) * (c.x - F.px) + (c.y - F.py) * (c.y - F.py)).squareRoot()
    F.px = c.x; F.py = c.y

    // the pointer a long way off: out come the windows, one after another
    let fdx = c.x - S.x, fdy = c.y - (S.y - 34 * SC)
    F.far = fdx * fdx + fdy * fdy > FAR_OFF * FAR_OFF || fdy <= -250 * SC
    if F.throwCool > 0 { F.throwCool -= F.far ? 4 : 1 }
    if F.grabCool > 0 { F.grabCool -= 1 }

    // a flying kick: does his foot find the pointer on the way up?
    if S.state == "fall" && F.air == "flykick" && !F.hitDone {
        let kx = S.x + Double(S.dir) * 19 * SC - c.x
        let ky = S.y - 28 * SC - c.y
        if kx * kx + ky * ky < 26 * 26 * SC * SC { F.hitDone = true; landBlow() }
    }

    // anything he was doing on his own gives way to the fight
    let own: Set<String> = ["walk", "idle", "sit", "wave", "cheer", "chase", "knock", "push", "press", "meet", "social"]
    if own.contains(S.state) {
        S.wall = nil; S.phase = 0
        if F.ko { S.state = "ko"; S.timer = 160 }
        else if F.intro { F.intro = false; S.state = "taunt"; S.timer = 50 }
        else { S.state = "guard" }
    }

    // you swiped at him: now and then he hops back out of the way
    if (S.state == "guard" || S.state == "hunt" || S.state == "taunt") && F.dodge <= 0 && swipe > 28 * SC {
        let dx = c.x - S.x, dy = c.y - (S.y - 34 * SC)
        if dx * dx + dy * dy < 100 * 100 * SC * SC {
            F.dodge = 40
            if rnd(0, 3) == 0 {
                face(dx)
                S.state = "fall"; F.air = "flip"
                S.vy = -7.5 * SC
                S.vx = -Double(S.dir) * 4.5 * SC
            }
        }
    }
}

// squared up to the pointer: attack it in reach, go after it out of reach
func stepGuard() {
    guard let l = S.ledge else { S.state = "fall"; return }
    let c = cursorPos()
    let dx = c.x - S.x
    let dy = c.y - (S.y - 34 * SC)          // from his chest
    let ax = abs(dx)
    if ax > 2 * SC { S.dir = sgn(dx) }

    if S.state == "taunt" {
        S.phase += 0.25
        S.timer -= 1
        if S.timer > 0 { return }
        S.state = "guard"
    }
    S.phase += 0.20
    if F.cool > 0 { return }

    if ax < 30 * SC && dy > -44 * SC && dy < 24 * SC {
        // in reach: now and then he grabs it and runs off with it
        if S.grabPtr && F.grabCool <= 0 && !mouseHeld() && rnd(0, 2) == 0 {
            startGrab()
            return
        }
        // otherwise jab, cross, and a kick for anything low or now and then
        S.state = (dy > 10 * SC || rnd(0, 10) >= 7) ? "kick" : "punch"
        S.timer = S.state == "punch" ? 14 : 20
        S.phase = 0
    } else if ax < 110 * SC && dy <= -44 * SC && dy > -250 * SC {
        jumpKick(dx, dy)                    // above him, but not by much
    } else if F.far && tryThrow(FETCH_FAR, conjure: true) {
        // a long way off, whichever way: a window thrown at it, one of his own if need be
    } else if ax < 110 * SC && dy <= -250 * SC {
        S.state = "taunt"; S.timer = 60; S.phase = 0      // well out of reach: 'come on, then'
    } else if ax >= 80 * SC {
        S.state = "hunt"; S.phase = 0
    } else if ax >= 30 * SC {
        // shuffle in with his fists up, never off the edge
        if l.ink { stepInk(Double(S.dir) * SPEED * 0.7); return }
        S.x = max(l.l + EDGE, min(l.r - EDGE, S.x + Double(S.dir) * SPEED * 0.7))
    }
}

// a punch or kick: the blow lands, or misses, at full stretch
func stepStrike() {
    S.phase += 0.2
    let len = S.state == "punch" ? 14 : 20
    S.timer -= 1
    if S.timer == len / 2 {
        let c = cursorPos()
        let hx = S.x + Double(S.dir) * 19 * SC - c.x
        let hy = S.y - (S.state == "punch" ? 35.0 : 28.0) * SC - c.y
        if hx * hx + hy * hy < 28 * 28 * SC * SC { landBlow() }
    }
    if S.timer <= 0 {
        F.combo += 1
        F.cool = rnd(5, 16)
        S.phase = 0
        if F.gloat { F.gloat = false; S.state = "taunt"; S.timer = 45 }
        else { S.state = "guard" }
    }
}

// running at the pointer, climbing or leaping at whatever is in the way
func stepHunt() {
    guard let l = S.ledge else { S.state = "fall"; return }
    let c = cursorPos()
    let dx = c.x - S.x
    let dy = c.y - (S.y - 34 * SC)
    let ax = abs(dx)
    if ax < 60 * SC || (ax < 110 * SC && dy < -44 * SC) {
        S.state = "guard"                   // close enough to fight
        return
    }
    S.phase += 0.40
    face(dx)

    // a throw is due: a window right at hand, the one he was about to climb
    // included, or with the pointer far off, any he can get to on this ledge,
    // and failing that one of his own
    if S.tick % 4 == 0 {
        let threw = F.far ? tryThrow(FETCH_FAR, conjure: true) : tryThrow(30 * SC)
        if threw { return }
    }

    if let wall = findWall() { startClimb(wall); return }
    if dy < -44 * SC, let up = findReach() { startLeap(up); return }   // it is up there: jump for a corner
    if l.ink {
        if stepInk(Double(S.dir) * SPEED * 2.2) == "wall" { S.state = "taunt"; S.timer = 40 }
        return
    }

    S.x += Double(S.dir) * SPEED * 2.2
    // he jumps off an edge to get at it; the floor's edge stops him
    if S.x < l.l + EDGE {
        if l.ground { S.x = l.l + EDGE; S.state = "taunt"; S.timer = 40 }
        else { S.state = "fall"; S.vx = -2.4 * SC; S.vy = -3.0 * SC }
    } else if S.x > l.r - EDGE {
        if l.ground { S.x = l.r - EDGE; S.state = "taunt"; S.timer = 40 }
        else { S.state = "fall"; S.vx = 2.4 * SC; S.vy = -3.0 * SC }
    }
}

// ------------------------------------------------------------------- his sprite
// a left click on him: he is picked up (a quick click is a jump, see below)
func spriteMouseDown() {
    let c = cursorPos()
    S.grabX = c.x - (S.x - CX)
    S.grabY = c.y - (S.y - FOOT)
    S.lastX = S.x
    S.dragged = 0
    S.drag = true
    // a click on him in a fight is a hit. stepPhysics sees most clicks too,
    // but a quick one can come and go between two of its frames.
    if F.on { hitHim(c) }
}

func spriteMouseUp() {
    if !S.drag { return }
    S.drag = false
    if F.on && S.dragged < 4 * SC { return }        // just a hit, already dealt with
    F.air = ""
    if S.dragged < 4 * SC && S.ledge != nil {
        // a click rather than a drag: he jumps on the spot
        S.state = "cheer"; S.timer = 70; S.cool = 160; S.phase = 0
        face(cursorPos().x - S.x)
        return
    }
    S.state = "fall"
    S.vy = 0
    S.vx = max(-9 * SC, min(9 * SC, (S.x - S.lastX) * 0.7))
    if S.vx != 0 { S.dir = sgn(S.vx) }
}

// ---------------------------------------------------------------------- physics
func stepPhysics() {
    S.tick += 1
    if S.tick % 5 == 0 { updateWorld() }
    if !PROPS.isEmpty { stepProps() }
    if !F.on && !THROWN.isEmpty { stepTidy() }
    if S.cool > 0 { S.cool -= 1 }
    if S.chase > 0 { S.chase -= 1 }

    // Esc ends a fight, whichever program has the keyboard
    if F.on && (ESC_TAPPED || escHeld()) { endFight() }
    ESC_TAPPED = false

    // you clicked somewhere: he drops what he is doing and runs over to look
    let down = leftHeld()
    if down && !S.mdown {
        S.mdown = true
        let c = cursorPos()
        let bx = S.x - CX, by = S.y - FOOT
        let onHim = c.x >= bx && c.x <= bx + BOXW && c.y >= by && c.y <= by + BOXH
        if F.on {
            // in a fight, a click on him is a hit, and a click anywhere else is ignored
            if onHim { hitHim(c) }
        } else if !onHim && !S.drag && S.state != "climb" {
            S.tx = c.x
            S.ty = c.y
            S.chase = 300
            S.state = "chase"
            S.phase = 0
            S.chasePeer = -1
            face(c.x - S.x)
        }
    } else if !down {
        S.mdown = false
    }

    if S.drag {
        // the button came up without him hearing about it: let go all the same
        if !down { spriteMouseUp() }
        else {
            let c = cursorPos()
            S.lastX = S.x
            S.x = c.x - S.grabX + CX
            S.y = c.y - S.grabY + FOOT
            S.dragged += abs(S.x - S.lastX)
            S.phase += 0.2
            return
        }
    }

    if F.on { stepFightFrame() } else { stepFriends() }

    // A figure's move waits here until he is settled enough to perform it. The
    // dialog he was named in is a window like any other, so he is often
    // standing on it when you press OK; it shuts, the ledge under him goes, and
    // anything set at that moment would be thrown away by the fall.
    if S.pending != "" {
        S.pendTTL -= 1
        if S.pendTTL <= 0 {
            S.pending = ""
        } else if !S.drag && S.ledge != nil &&
                    !(S.state == "climb" || S.state == "leap" || S.state == "fall" || S.state == "knock" || S.state == "push") {
            let act = S.pending
            S.pending = ""
            doEggAct(act)
        }
    }

    switch S.state {

    case "hunt": stepHunt()
    case "guard", "taunt": stepGuard()
    case "punch", "kick": stepStrike()

    case "fetch":
        // on his way over to a window he means to throw
        guard let t0 = F.fetch, S.ledge != nil else { F.fetch = nil; S.state = "guard"; return }
        S.timer -= 1
        if S.timer <= 0 { F.fetch = nil; S.state = "guard"; return }
        // still there, just as it was?
        guard let w = S.ledges.first(where: { $0.h == t0.l.h }), abs(w.l - t0.l.l) <= 2, abs(w.t - t0.l.t) <= 2 else {
            F.fetch = nil; S.state = "guard"
            return
        }
        let gap = t0.x - S.x
        if abs(gap) <= 4 * SC {
            S.x = t0.x
            var t = t0
            t.l = w
            F.fetch = nil
            if !startHeave(t) { S.state = "guard" }
            return
        }
        S.phase += 0.40
        S.dir = sgn(gap)
        S.x += Double(S.dir) * min(abs(gap), SPEED * 2.4)

    case "heave":
        // wrenching it loose, see stepHeld; then it flies
        S.phase += 0.5
        guard let fl = F.fly, let l = S.ledge else { F.fly = nil; S.state = "guard"; return }
        // one out of reach: he jumps up to its bottom edge and drops back down with it
        if fl.jump { S.y = l.t - getJumpLift(fl.len - S.timer + 1, fl.g) }
        S.timer -= 1
        if S.timer <= 0 { launchWindow() }

    case "hurl":
        S.phase += 0.2
        S.timer -= 1
        if S.timer <= 0 { S.state = "guard"; S.phase = 0 }

    case "haul":
        // off he goes with your pointer, see stepGrab, turning at the ends
        S.phase += 0.42
        if let l = S.ledge {
            if GRAB_HOLD - S.timer >= GRAB_SNATCH {
                S.dir = F.run
                if l.ink {
                    if stepInk(Double(S.dir) * SPEED * 1.8) == "wall" { F.run = -F.run }
                } else {
                    S.x += Double(S.dir) * SPEED * 1.8
                    if S.x < l.l + EDGE { S.x = l.l + EDGE; F.run = 1 }
                    else if S.x > l.r - EDGE { S.x = l.r - EDGE; F.run = -1 }
                }
            }
        } else {
            S.state = "fall"; S.vy = 0
        }
        if S.state == "haul" {
            S.timer -= 1
            if S.timer <= 0 { S.state = "fling"; S.timer = FLING_LEN; S.phase = 0 }
        }

    case "fling":
        S.phase += 0.2
        if S.timer == FLING_AT { flingPointer() }
        S.timer -= 1
        if S.timer <= 0 { S.state = "guard"; S.phase = 0 }

    case "ko":
        S.phase += 0.15
        S.timer -= 1
        if S.timer <= 0 {
            endFight()                          // he has had enough, and says so
            S.state = "wave"; S.timer = 70; S.phase = 0
        }

    case "walk":
        S.phase += 0.26
        guard let l = S.ledge else { S.state = "fall"; return }

        // something is in front of him
        if let wall = findWall() {
            if wall.btn || wall.icon { startClimb(wall); return }      // a button or an icon is just a step up
            let roll = rnd(0, 100)
            if roll < 80 {
                startClimb(wall)
            } else if roll < 90 {
                S.wall = wall; S.state = "knock"; S.timer = 54; S.phase = 0
            } else if roll < 98 && S.shove && !wall.maxed {
                S.wall = wall; S.state = "push"; S.timer = 60; S.phase = 0
            } else {
                S.dir = -S.dir
            }
            return
        }

        // the pointer came near
        let cd = cursorDistance()
        if S.cool <= 0 && cd.d < NOTICE {
            face(cd.x - S.x)
            S.state = "wave"; S.timer = 60; S.cool = 200; S.phase = 0
            return
        }

        // a window hanging overhead: jump for the corner
        if let up = findReach(), rnd(0, 100) < 75 { startLeap(up); return }

        // nothing to stand on down here: go and find a window to get onto
        if l.ground && S.tick % 40 == 0, let e = findClimb() { face(e - S.x) }

        // drop off the title bar down onto the buttons inside the window
        if !l.ground && !l.btn && rnd(0, 45) == 0 {
            if findDropTarget(l) != nil {
                S.ignore = l.h; S.state = "fall"; S.vy = 0; S.vx = 0
                return
            }
        }

        // standing on top of the paint window with ink on the canvas below: hop down in
        if !l.ink && l.h != 0 && l.h == Ink.target && Ink.ready && rnd(0, 90) == 0 &&
            Ink.floor(ri(S.x), ri(l.t + 30 * SC), ri(l.b)) >= 0 {
            S.ignore = l.h; S.state = "fall"; S.vy = 0; S.vx = 0
            return
        }

        if l.ink {
            // a stroke taller than a step is a wall: turn round
            if stepInk(Double(S.dir) * SPEED) == "wall" { S.dir = -S.dir }
            if S.state == "walk" && rnd(0, 260) == 0 { S.state = "idle"; S.timer = 40 }
            return
        }

        S.x += Double(S.dir) * SPEED

        // at the end of a ledge he almost always stays on it, and now and then
        // sits down on the edge instead of turning round
        if S.x < l.l + EDGE {
            if l.ground || rnd(0, 100) < 96 {
                S.x = l.l + EDGE
                if !l.ground && !l.btn && rnd(0, 4) == 0 {
                    S.state = "sit"; S.timer = rnd(90, 260); S.phase = 0
                } else { S.dir = 1 }
            } else {
                S.state = "fall"; S.vx = -1.2 * SC; S.vy = 0
            }
        } else if S.x > l.r - EDGE {
            if l.ground || rnd(0, 100) < 96 {
                S.x = l.r - EDGE
                if !l.ground && !l.btn && rnd(0, 4) == 0 {
                    S.state = "sit"; S.timer = rnd(90, 260); S.phase = 0
                } else { S.dir = -1 }
            } else {
                S.state = "fall"; S.vx = 1.2 * SC; S.vy = 0
            }
        }

        if S.state == "walk" && rnd(0, 260) == 0 { S.state = "idle"; S.timer = 40 }

    case "chase":
        S.phase += 0.36
        guard let l = S.ledge else { S.state = "fall"; return }

        // playing tag: the target is a friend, and they keep moving
        if S.chasePeer >= 0 {
            if let p = getPeer(S.chasePeer) { S.tx = Double(p.x); S.ty = Double(p.y) } else { S.chasePeer = -1 }
        }

        let gap = S.tx - S.x
        if abs(gap) > 4 * SC { S.dir = sgn(gap) }

        // got there: a hop and a cheer
        if abs(gap) < 16 * SC && abs(S.ty - S.y) < 90 * SC {
            S.state = "cheer"; S.timer = 60; S.phase = 0; S.cool = 120; S.chasePeer = -1
            return
        }
        if S.chase <= 0 { S.state = "walk"; S.chasePeer = -1; return }

        // anything in the way gets climbed, no dithering about it
        if let wall = findWall() { startClimb(wall); return }
        if let up = findReach() { startLeap(up); return }

        if l.ink {
            // a stroke taller than a step is in the way: he gives up
            if stepInk(Double(S.dir) * SPEED * 1.9) == "wall" {
                S.state = "walk"; S.chase = 0; S.chasePeer = -1; S.dir = -S.dir
            }
            return
        }

        S.x += Double(S.dir) * SPEED * 1.9

        // he will run off an edge to get to you
        if S.x < l.l + EDGE {
            if l.ground { S.x = l.l + EDGE; S.dir = 1 }
            else { S.state = "fall"; S.vx = -1.6 * SC; S.vy = 0 }
        } else if S.x > l.r - EDGE {
            if l.ground { S.x = l.r - EDGE; S.dir = -1 }
            else { S.state = "fall"; S.vx = 1.6 * SC; S.vy = 0 }
        }

    case "cheer":
        S.phase += 0.30
        S.timer -= 1
        if S.timer <= 0 { S.state = "walk" }

    case "meet":
        let lo = S.ledge
        let po = getPeer(S.with)
        var bail = lo == nil || po == nil
        if !bail, let pp = po { bail = abs(Double(pp.y) - S.y) > 8 * SC }
        if !bail { S.meetT += 1; bail = S.meetT > 240 }
        guard !bail, let l = lo, let p = po else { stopMeeting(); return }
        let answered = p.with == ME
        if !answered && S.meetT > 30 { stopMeeting(); return }     // busy with someone else
        // if both asked at once, the lower slot's idea wins
        if answered && p.slot < ME && p.act > 0 && p.act < ACTS.count { S.act = ACTS[p.act] }

        let gap = Double(p.x) - S.x
        if abs(gap) > 1 { S.dir = sgn(gap) }
        if abs(gap) > (ACT_GAP[S.act] ?? 30) * SC {
            if findWall() != nil { stopMeeting(); return }          // a window in the way
            S.waiting = false
            S.phase += 0.26
            if l.ink {
                let r = stepInk(Double(S.dir) * SPEED)
                if r == "wall" { S.waiting = true }
                else if r == "fall" { stopMeeting(); S.state = "fall" }
                return
            }
            S.x += Double(S.dir) * SPEED
            if S.x < l.l + EDGE { S.x = l.l + EDGE; S.waiting = true }
            if S.x > l.r - EDGE { S.x = l.r - EDGE; S.waiting = true }
        } else {
            S.waiting = true
            S.phase += 0.12
            if answered && (p.state == ST_MEET || p.state == ST_SOCIAL) {
                S.state = "social"; S.timer = ACT_TIME[S.act] ?? 60; S.phase = 0
            }
        }

    case "social":
        // they quit, or finished and wandered off a moment before him
        guard let p = getPeer(S.with), !(p.with != ME && S.timer > 10) else { stopMeeting(); return }
        if p.x != ri(S.x) { face(Double(p.x) - S.x) }
        S.phase += S.act == "chat" ? 0.14 : (S.act == "greet" ? 0.34 : 0.30)
        S.timer -= 1
        if S.timer <= 0 {
            let act = S.act, who = S.with
            stopMeeting()
            if act == "tag" {
                // the lower slot is 'it' and runs for it, the other gives chase
                if ME < who {
                    S.tx = S.x - Double(S.dir) * 600 * SC; S.ty = S.y; S.chase = 150
                } else {
                    S.chasePeer = who; S.tx = Double(p.x); S.ty = Double(p.y); S.chase = 260
                }
                face(S.tx - S.x)
                S.state = "chase"; S.phase = 0
            } else {
                S.dir = -S.dir              // and off they go their separate ways
            }
        }

    case "leap":
        S.phase += 0.30
        guard let w = S.wall else { S.state = "fall"; S.vy = 0; return }
        S.timer -= 1
        let t = max(0.0, 1.0 - Double(S.timer) / 18.0)
        S.y = S.ly0 + (w.b - S.ly0) * pow(t, 0.55)     // fast off the mark, easing into the grab
        S.x = S.dir > 0 ? w.l - HUG : w.r + HUG
        if S.timer <= 0 { S.y = w.b; S.state = "climb"; S.phase = 0 }

    case "idle":
        S.phase += 0.12
        S.timer -= 1
        if S.timer <= 0 {
            S.state = "walk"
            if rnd(0, 2) == 0 { S.dir = -S.dir }
        }

    case "sit":
        S.phase += 0.14
        // he looks at the pointer while he sits
        let cd = cursorDistance()
        if cd.d < NOTICE { face(cd.x - S.x) }
        S.timer -= 1
        if S.timer <= 0 { S.state = "walk"; S.dir = -S.dir }

    case "wave":
        S.phase += 0.34
        S.timer -= 1
        if S.timer <= 0 { S.state = "walk" }

    case "knock":
        S.phase += 0.30
        guard let w = S.wall else { S.state = "walk"; return }
        // a rap on the glass, and the window rattles back
        if S.shove && !w.maxed {
            let k = S.timer % 18
            if k == 9 { _ = winNudge(w.h, Double(S.dir) * 3 * SC, 0) }
            if k == 5 { _ = winNudge(w.h, -Double(S.dir) * 3 * SC, 0) }
        }
        S.timer -= 1
        if S.timer <= 0 { S.state = "walk"; S.dir = -S.dir; S.wall = nil }

    case "push":
        S.phase += 0.18
        guard let w = S.wall, !w.maxed else { S.state = "walk"; S.wall = nil; return }
        if S.timer % 2 == 0 {
            if !winNudge(w.h, Double(S.dir) * 2 * SC, 0) { S.state = "walk"; S.wall = nil; return }
        }
        S.timer -= 1
        if S.timer <= 0 {
            S.state = "walk"
            S.wall = nil
            if rnd(0, 2) == 0 { S.dir = -S.dir }
        }

    case "press":
        S.phase += 0.16
        guard let l = S.ledge, l.btn || l.icon else { S.state = "walk"; return }
        // he crouches, then stamps on it halfway through
        if S.timer == 22 {
            if l.icon {
                // jumping on a desktop icon opens it, but not more than once in a while
                if S.openOn && S.tick - S.lastOpen > OPEN_GAP {
                    if openShortcut(l.name) { S.lastOpen = S.tick }
                }
            } else if S.click && l.uia >= 0 {
                SCAN.press(l.uia, CGRect(x: l.l, y: l.t, width: l.r - l.l, height: l.b - l.t))
            }
        }
        S.timer -= 1
        if S.timer <= 0 {
            S.state = "walk"
            if rnd(0, 2) == 0 { S.dir = -S.dir }
        }

    case "climb":
        S.phase += 0.30
        guard let w = S.wall else { S.state = "fall"; return }
        S.x = S.dir > 0 ? w.l - HUG : w.r + HUG
        S.y -= CLIMB
        if S.y <= w.t {
            landOn(w)
            S.x = S.dir > 0 ? w.l + STEPIN : w.r - STEPIN
        }

    case "fall":
        let prev = S.y
        S.vy = min(S.vy + GRAVITY, VMAX)
        S.y += S.vy
        S.x += S.vx
        S.vx *= 0.985
        S.phase += 0.2

        // ink, or anything white, catches him on the way down
        if Ink.ready {
            let ix = ri(S.x)
            let gy = Ink.floor(ix, ri(prev.rounded(.down)) + 1, ri(S.y))
            if gy >= 0 && Ink.inside(ix, gy) {
                landOn(newInkLedge(gy))
                S.y = Double(gy)
                return
            }
        }

        for l in S.ledges {
            if l.h == S.ignore && S.ignore != 0 { continue }
            if S.x >= l.l + 5 * SC && S.x <= l.r - 5 * SC && prev <= l.t + SC && S.y >= l.t {
                landOn(l)
                break
            }
        }

        let all = virtualScreen()
        if S.state == "fall" && S.y > all.bottom + 120 * SC {
            S.x = Double(rnd(ri(all.left + 150 * SC), ri(all.right - 150 * SC)))
            S.y = all.top + 10 * SC
            S.vy = 0; S.vx = 0
        }

    default:
        S.state = "fall"
    }

    let vs = virtualScreen()
    if S.x < vs.left + 8 * SC { S.x = vs.left + 8 * SC; S.dir = 1 }
    if S.x > vs.right - 8 * SC { S.x = vs.right - 8 * SC; S.dir = -1 }
}
