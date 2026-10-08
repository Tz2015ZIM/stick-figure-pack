// Platform.swift
// What stickman.ps1 gets from user32, dwmapi and friends, done the macOS way.
//
// Everything here works in the global coordinates CoreGraphics and the
// Accessibility API use: points, with the origin at the top-left corner of the
// main display and y growing downwards. That is the same way round as the
// screen on Windows, so the behaviour code reads just like stickman.ps1. Only
// AppKit windows count from the bottom up, and cocoaOrigin() turns things
// round for them.

import Cocoa
import ApplicationServices

struct Area {
    var left: Double, top: Double, right: Double, bottom: Double
    var width: Double { right - left }
    var height: Double { bottom - top }
    func contains(_ x: Double, _ y: Double) -> Bool { x >= left && x < right && y >= top && y < bottom }
}

// ---------------------------------------------------------------------- screens
var MAIN_H = 900.0                                  // height of the screen with the menu bar
var SCREENS: [(frame: Area, work: Area)] = []       // refreshed every frame

func quartz(_ r: NSRect) -> Area {
    Area(left: Double(r.minX), top: MAIN_H - Double(r.maxY), right: Double(r.maxX), bottom: MAIN_H - Double(r.minY))
}

// where an AppKit window has to go for its top-left corner to land on (x, y)
func cocoaOrigin(_ x: Double, _ y: Double, _ height: Double) -> NSPoint {
    NSPoint(x: x, y: MAIN_H - y - height)
}

func refreshScreens() {
    let all = NSScreen.screens
    if let first = all.first { MAIN_H = Double(first.frame.height) }
    var list: [(frame: Area, work: Area)] = []
    for s in all { list.append((frame: quartz(s.frame), work: quartz(s.visibleFrame))) }
    SCREENS = list
}

// the screen (x, y) is on, or the nearest one, like Screen.FromPoint
func screenAt(_ x: Double, _ y: Double) -> (frame: Area, work: Area) {
    if SCREENS.isEmpty { refreshScreens() }
    if SCREENS.isEmpty {
        let a = Area(left: 0, top: 0, right: 1440, bottom: 900)
        return (frame: a, work: a)
    }
    var best = 0
    var bd = Double.greatestFiniteMagnitude
    for (i, s) in SCREENS.enumerated() {
        if s.frame.contains(x, y) { return s }
        let dx = max(s.frame.left - x, 0.0, x - s.frame.right)
        let dy = max(s.frame.top - y, 0.0, y - s.frame.bottom)
        let d = dx * dx + dy * dy
        if d < bd { bd = d; best = i }
    }
    return SCREENS[best]
}

// the usable part of that screen: no menu bar, no Dock
func workingArea(_ x: Double, _ y: Double) -> Area { screenAt(x, y).work }

// every screen together, like SystemInformation.VirtualScreen
func virtualScreen() -> Area {
    if SCREENS.isEmpty { refreshScreens() }
    guard var u = SCREENS.first?.frame else { return Area(left: 0, top: 0, right: 1440, bottom: 900) }
    for s in SCREENS {
        u.left = min(u.left, s.frame.left); u.top = min(u.top, s.frame.top)
        u.right = max(u.right, s.frame.right); u.bottom = max(u.bottom, s.frame.bottom)
    }
    return u
}

// ---------------------------------------------------------------------- pointer
func cursorPos() -> (x: Double, y: Double) {
    let p = CGEvent(source: nil)?.location ?? CGPoint.zero
    return (x: Double(p.x), y: Double(p.y))
}

// Moves the pointer to (x, y), kept on a screen, and says where it went. It
// only ever moves it: nothing is ever clicked.
@discardableResult
func putCursor(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
    let f = screenAt(x, y).frame
    let nx = max(f.left, min(f.right - 1, x.rounded()))
    let ny = max(f.top, min(f.bottom - 1, y.rounded()))
    _ = CGWarpMouseCursorPosition(CGPoint(x: nx, y: ny))
    _ = CGAssociateMouseAndMouseCursorPosition(1)     // no quarter-second freeze after the warp
    return (x: nx, y: ny)
}

func mouseHeld() -> Bool { NSEvent.pressedMouseButtons != 0 }
func leftHeld() -> Bool { (NSEvent.pressedMouseButtons & 1) != 0 }

// Esc, whichever program has the keyboard. The key monitors catch a quick tap
// that comes and goes between two frames.
var ESC_TAPPED = false
func escHeld() -> Bool { CGEventSource.keyState(.combinedSessionState, key: 53) }

// ---------------------------------------------------------------------- windows
struct Win {
    var id: Int
    var pid: Int32
    var left: Double, top: Double, right: Double, bottom: Double
    var layer: Int
    var owner: String
    var title: String       // only filled in once he may record the screen
    var maxed = false
}

// Every window on screen, front to back. Safe to call from any thread.
func windowList() -> [Win] {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var out: [Win] = []
    out.reserveCapacity(raw.count)
    for d in raw {
        guard let num = d[kCGWindowNumber as String] as? Int,
              let pid = d[kCGWindowOwnerPID as String] as? Int,
              let bd = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
        let alpha = (d[kCGWindowAlpha as String] as? Double) ?? 1.0
        if alpha <= 0.01 { continue }
        out.append(Win(id: num, pid: Int32(truncatingIfNeeded: pid),
                       left: Double(r.minX), top: Double(r.minY), right: Double(r.maxX), bottom: Double(r.maxY),
                       layer: (d[kCGWindowLayer as String] as? Int) ?? 0,
                       owner: (d[kCGWindowOwnerName as String] as? String) ?? "",
                       title: (d[kCGWindowName as String] as? String) ?? ""))
    }
    return out
}

// where window id is right now, straight from the window server
func windowBounds(_ id: Int) -> CGRect? {
    guard id > 0,
          let raw = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(truncatingIfNeeded: id)) as? [[String: Any]],
          let d = raw.first,
          let bd = d[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bd as CFDictionary)
}

var WINS: [Win] = []                    // every window on screen, front to back, from the last look
var WIN_BY_ID: [Int: Win] = [:]         // the ones he can stand on, by number
var MY_WINDOWS = Set<Int>()             // his sprite, spark, grip and props
var STICK_PIDS = Set<Int32>()           // every stickman running, this one included
var DIALOG: NSWindow? = nil             // the Convert to Symbol dialog, which he may stand on

// system furniture that is never a window to stand on
let NOT_WINDOWS: Set<String> = [
    "Window Server", "Dock", "Control Center", "SystemUIServer", "Notification Center", "NotificationCenter",
    "Spotlight", "WindowManager", "Wallpaper", "screencaptureui", "TextInputMenuAgent", "Stage Manager"
]

// a window belonging to a stickman: his own sprite and props, or anything of
// another copy of him. His own dialog does not count - he stands on that.
func isStickWindow(_ w: Win) -> Bool {
    if MY_WINDOWS.contains(w.id) { return true }
    if STICK_PIDS.contains(w.pid) {
        if let d = DIALOG, d.windowNumber == w.id { return false }
        return true
    }
    return false
}

// Visible windows of other programs, big enough to bother with, front to
// back: the things he can stand on.
func standableWindows() -> [Win] {
    var out: [Win] = []
    for var w in WINS {
        if w.layer < 0 || w.layer >= 20 || isStickWindow(w) || NOT_WINDOWS.contains(w.owner) { continue }
        if w.right - w.left < 140 || w.bottom - w.top < 90 { continue }
        let a = screenAt((w.left + w.right) / 2, (w.top + w.bottom) / 2).work
        w.maxed = w.right - w.left >= a.width - 8 && w.bottom - w.top >= a.height - 8
        out.append(w)
    }
    return out
}

// Is window id what you see at (x, y), and not something in front of it?
func windowShowing(_ id: Int, _ x: Double, _ y: Double) -> Bool {
    for w in WINS {
        if w.layer < 0 || w.layer >= 25 || isStickWindow(w) { continue }
        if x >= w.left && x < w.right && y >= w.top && y < w.bottom { return w.id == id }
    }
    return false
}

// ---------------------------------------------------------------- Accessibility
// Moving another program's window, pressing its buttons and finding the icons
// on the desktop all go through the Accessibility API, which needs the
// Accessibility permission (System Settings > Privacy & Security). Without it
// every call quietly fails and he leaves windows alone.

func axTrusted() -> Bool { AXIsProcessTrusted() }

// shows the system's 'allow this app' prompt
func askForAccessibility() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
}

func axValue(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
    return v
}
func axString(_ e: AXUIElement, _ attr: String) -> String? { axValue(e, attr) as? String }
func axBool(_ e: AXUIElement, _ attr: String) -> Bool? { axValue(e, attr) as? Bool }
func axChildren(_ e: AXUIElement) -> [AXUIElement] { (axValue(e, "AXChildren") as? [AXUIElement]) ?? [] }

func axFrame(_ e: AXUIElement) -> CGRect? {
    guard let pv = axValue(e, "AXPosition"), let sv = axValue(e, "AXSize"),
          CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    var s = CGSize.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

func axPos(_ e: AXUIElement) -> CGPoint? {
    guard let pv = axValue(e, "AXPosition"), CFGetTypeID(pv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func axMove(_ e: AXUIElement, _ x: Double, _ y: Double) -> Bool {
    var p = CGPoint(x: x, y: y)
    guard let v = AXValueCreate(.cgPoint, &p) else { return false }
    return AXUIElementSetAttributeValue(e, "AXPosition" as CFString, v) == .success
}

// The Accessibility handle on one of pid's windows, found by its frame. Safe
// to call from any thread.
func axFindWindow(_ pid: Int32, _ frame: CGRect) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    guard let wins = axValue(app, "AXWindows") as? [AXUIElement] else { return nil }
    for e in wins {
        guard let f = axFrame(e) else { continue }
        if abs(f.minX - frame.minX) <= 2 && abs(f.minY - frame.minY) <= 2 &&
            abs(f.width - frame.width) <= 2 && abs(f.height - frame.height) <= 2 { return e }
    }
    return nil
}

var axCache: [Int: AXUIElement] = [:]

func axWindow(_ id: Int) -> AXUIElement? {
    if let e = axCache[id] { return e }
    guard let w = WIN_BY_ID[id] else { return nil }
    let e = axFindWindow(w.pid, CGRect(x: w.left, y: w.top, width: w.right - w.left, height: w.bottom - w.top))
    if let found = e { axCache[id] = found }
    return e
}

// -------------------------------------------------------------- moving windows
// All he ever does to a window is move it: same size, same place in the
// stack, focus left where it was. Never closed, minimised or clicked.

var PROP_PANELS: [Int: NSWindow] = [:]     // his own conjured panels, by window number

// the window's frame, left top right bottom, or nil if it is gone
func winRect(_ id: Int) -> (l: Double, t: Double, r: Double, b: Double)? {
    if let p = PROP_PANELS[id] {
        if !p.isVisible { return nil }
        let a = quartz(p.frame)
        return (l: a.left, t: a.top, r: a.right, b: a.bottom)
    }
    guard let e = axWindow(id), let f = axFrame(e) else { axCache[id] = nil; return nil }
    return (l: Double(f.minX), t: Double(f.minY), r: Double(f.maxX), b: Double(f.maxY))
}

// just its top-left corner: one question to the program instead of two, for
// the windows he checks on every frame while they fly
func winPos(_ id: Int) -> (x: Double, y: Double)? {
    if let p = PROP_PANELS[id] {
        if !p.isVisible { return nil }
        let a = quartz(p.frame)
        return (x: a.left, y: a.top)
    }
    guard let e = axWindow(id), let p = axPos(e) else { axCache[id] = nil; return nil }
    return (x: Double(p.x), y: Double(p.y))
}

// Puts the window's top-left corner at (x, y) and says where it really went
// (a program may keep its window below the menu bar, say), or nil if it
// would not move.
func winPlace(_ id: Int, _ x: Double, _ y: Double) -> (x: Double, y: Double)? {
    if let p = PROP_PANELS[id] {
        if !p.isVisible { return nil }
        p.setFrameOrigin(cocoaOrigin(x, y, Double(p.frame.height)))
        let a = quartz(p.frame)
        return (x: a.left, y: a.top)
    }
    if let w = WIN_BY_ID[id], w.maxed { return nil }
    guard let e = axWindow(id), axMove(e, x, y), let p = axPos(e) else { axCache[id] = nil; return nil }
    return (x: Double(p.x), y: Double(p.y))
}

// shove a window sideways without resizing it, raising it or taking the focus
func winNudge(_ id: Int, _ dx: Double, _ dy: Double) -> Bool {
    guard let p = winPos(id) else { return false }
    return winPlace(id, p.x + dx, p.y + dy) != nil
}

// An ordinary window of some other program that lets itself be moved. Never
// Activity Monitor or anything floating above the rest, so you can always get
// at those to stop him, and never a window of a stickman.
func winThrowable(_ id: Int) -> Bool {
    if PROP_PANELS[id] != nil { return true }
    guard let w = WIN_BY_ID[id], w.layer == 0, !w.maxed, !STICK_PIDS.contains(w.pid),
          w.owner != "Activity Monitor" else { return false }
    // asking the program is slow, and the answer hardly ever changes
    let now = ProcessInfo.processInfo.systemUptime
    if let c = throwableCache[id], now - c.at < 2 { return c.ok }
    var ok = false
    if let e = axWindow(id) {
        var settable: DarwinBoolean = false
        let asked = AXUIElementIsAttributeSettable(e, "AXPosition" as CFString, &settable)
        ok = asked == .success && settable.boolValue &&
            axBool(e, "AXMinimized") != true && axBool(e, "AXFullScreen") != true
    }
    throwableCache[id] = (at: now, ok: ok)
    return ok
}
var throwableCache: [Int: (at: Double, ok: Bool)] = [:]

// ---------------------------------------------------------------------- his name
// Activity Monitor lists him under the name LaunchServices has for him: 'Stick
// figure', or whatever you named the symbol when you converted him. Windows
// needs a new exe for every name (see stickhost.cs); here the name of the
// running process can simply be changed, the way Chromium names its helper
// processes. The calls are private, so they are looked up at run time and
// quietly skipped if they are not there.
func setProcessName(_ name: String) {
    ProcessInfo.processInfo.processName = name
    typealias GetASN = @convention(c) () -> UnsafeRawPointer?
    typealias SetItem = @convention(c) (Int32, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?) -> Int32
    guard let ls = CFBundleGetBundleWithIdentifier("com.apple.LaunchServices" as CFString),
          let getP = CFBundleGetFunctionPointerForName(ls, "_LSGetCurrentApplicationASN" as CFString),
          let setP = CFBundleGetFunctionPointerForName(ls, "_LSSetApplicationInformationItem" as CFString),
          let keyP = CFBundleGetDataPointerForName(ls, "_kLSDisplayNameKey" as CFString) else { return }
    let getASN = unsafeBitCast(getP, to: GetASN.self)
    let setItem = unsafeBitCast(setP, to: SetItem.self)
    guard let asn = getASN(), let key = keyP.load(as: UnsafeRawPointer?.self) else { return }
    let value = name as CFString
    withExtendedLifetime(value) {
        _ = setItem(-2, asn, key, UnsafeRawPointer(Unmanaged.passUnretained(value).toOpaque()), nil)
    }
}

// ---------------------------------------------------------------- the desktop
// What each desktop label actually points at. Only apps, folders, aliases and
// web links are listed, so stray documents on the desktop are never opened.
func desktopFiles() -> [String: URL] {
    var m: [String: URL] = [:]
    let fm = FileManager.default
    guard let desk = fm.urls(for: .desktopDirectory, in: .userDomainMask).first else { return m }
    let keys: [URLResourceKey] = [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey]
    guard let items = try? fm.contentsOfDirectory(at: desk, includingPropertiesForKeys: keys, options: []) else { return m }
    for u in items {
        let v = try? u.resourceValues(forKeys: Set(keys))
        let ext = u.pathExtension.lowercased()
        let ok = (v?.isDirectory ?? false) || (v?.isAliasFile ?? false) || (v?.isSymbolicLink ?? false) ||
            ["app", "webloc", "inetloc", "fileloc"].contains(ext)
        if !ok { continue }
        m[u.lastPathComponent.lowercased()] = u
        m[u.deletingPathExtension().lastPathComponent.lowercased()] = u
    }
    return m
}

func finderPid() -> Int32 {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier ?? 0
}

// another copy of him, in a process of its own
func launchAnother() {
    let b = Bundle.main.bundleURL
    if b.pathExtension == "app" {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: b, configuration: cfg, completionHandler: nil)
    } else if let exe = Bundle.main.executableURL {
        _ = try? Process.run(exe, arguments: [])
    }
}
