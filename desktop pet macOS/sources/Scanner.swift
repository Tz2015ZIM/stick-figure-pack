// Scanner.swift
// The buttons inside a window, and the icons on the desktop, both come from
// the Accessibility API, which is far too slow to walk from the animation
// loop. So it runs on a thread of its own and leaves what it finds here, the
// way stickman.ps1 runs UI Automation in a runspace of its own.

import Cocoa
import ApplicationServices

final class Scanner {
    private let lock = NSLock()
    private var target: (id: Int, pid: Int32, frame: CGRect)? = nil
    private var buttons: [CGRect] = []
    private var elements: [AXUIElement] = []        // the matching elements, worker-only
    private var click: (idx: Int, rect: CGRect)? = nil
    private var icons: [(rect: CGRect, name: String)] = []
    private var finder: Int32 = 0

    static let BUTTONS: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXMenuButton"]
    // the red, yellow and green title bar buttons: never, whatever the menu says
    static let WINDOW_CONTROLS: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"]

    func start() {
        Thread.detachNewThread { self.loop() }
    }

    // the window the scanner should look inside, or nil
    func setTarget(_ w: Win?) {
        lock.lock()
        defer { lock.unlock() }
        guard let w = w else {
            if target != nil { target = nil; buttons = []; elements = [] }
            return
        }
        if target?.id != w.id { buttons = []; elements = [] }
        target = (id: w.id, pid: w.pid, frame: CGRect(x: w.left, y: w.top, width: w.right - w.left, height: w.bottom - w.top))
    }

    func currentButtons() -> [CGRect] { lock.lock(); defer { lock.unlock() }; return buttons }
    func currentIcons() -> [(rect: CGRect, name: String)] { lock.lock(); defer { lock.unlock() }; return icons }
    func setFinder(_ pid: Int32) { lock.lock(); finder = pid; lock.unlock() }

    // main thread asks for a press; the button has to still be at rect
    func press(_ idx: Int, _ rect: CGRect) { lock.lock(); click = (idx: idx, rect: rect); lock.unlock() }

    private func loop() {
        var n = 0
        while true {
            autoreleasepool {
                if AXIsProcessTrusted() {
                    pressIfAsked()
                    scanButtons()
                    if n % 3 == 0 { scanIcons() }
                } else {
                    lock.lock(); buttons = []; elements = []; icons = []; lock.unlock()
                }
            }
            n += 1
            Thread.sleep(forTimeInterval: 0.9)
        }
    }

    // the list may have been rebuilt since he stepped on it, so only press
    // the thing that is still where he is standing
    private func pressIfAsked() {
        lock.lock()
        let asked = click
        click = nil
        let els = elements
        lock.unlock()
        guard let c = asked, c.idx >= 0, c.idx < els.count, let f = axFrame(els[c.idx]) else { return }
        if abs(f.minX - c.rect.minX) < 3 && abs(f.minY - c.rect.minY) < 3 && abs(f.maxX - c.rect.maxX) < 3 {
            _ = AXUIElementPerformAction(els[c.idx], "AXPress" as CFString)
        }
    }

    private func scanButtons() {
        lock.lock()
        let tgt = target
        lock.unlock()
        guard let t = tgt, let win = axFindWindow(t.pid, t.frame) else {
            lock.lock(); buttons = []; elements = []; lock.unlock()
            return
        }
        var found: [AXUIElement] = []
        var rects: [CGRect] = []
        var queue: [(AXUIElement, Int)] = [(win, 0)]
        var head = 0
        // Every question is a round trip into the other program, so the walk
        // is kept short, and web pages - thousands of elements in a browser
        // or an Electron app - are left out.
        while head < queue.count && rects.count < 40 && head < 400 {
            let (e, depth) = queue[head]
            head += 1
            let role = axString(e, "AXRole") ?? ""
            if role == "AXWebArea" { continue }
            if Scanner.BUTTONS.contains(role) {
                let sub = axString(e, "AXSubrole") ?? ""
                if !Scanner.WINDOW_CONTROLS.contains(sub), axBool(e, "AXEnabled") != false, let f = axFrame(e),
                   f.width >= 22, f.height >= 12, f.width <= 700, f.height <= 140, f.intersects(t.frame) {
                    found.append(e)
                    rects.append(f)
                }
                continue            // nothing to stand on inside a button
            }
            if depth < 12 && queue.count < 1500 {
                for k in axChildren(e) { queue.append((k, depth + 1)) }
            }
        }
        lock.lock()
        if target?.id == t.id { elements = found; buttons = rects }
        lock.unlock()
    }

    // Finder draws the desktop, and shows each icon on it to Accessibility as
    // an image inside the desktop's scroll area, with the item's name on it.
    private func scanIcons() {
        lock.lock()
        let pid = finder
        lock.unlock()
        var out: [(rect: CGRect, name: String)] = []
        if pid > 0 {
            let app = AXUIElementCreateApplication(pid)
            var queue: [(AXUIElement, Int)] = []
            for k in axChildren(app) where axString(k, "AXRole") == "AXScrollArea" { queue.append((k, 0)) }
            var head = 0
            while head < queue.count && out.count < 120 && head < 500 {
                let (e, depth) = queue[head]
                head += 1
                if axString(e, "AXRole") == "AXImage" {
                    if let f = axFrame(e), f.width >= 8, f.height >= 8 {
                        let title = axString(e, "AXTitle") ?? ""
                        let name = title.isEmpty ? (axString(e, "AXDescription") ?? "") : title
                        out.append((rect: f, name: name))
                    }
                    continue
                }
                if depth < 3 { for k in axChildren(e) { queue.append((k, depth + 1)) } }
            }
        }
        lock.lock()
        icons = out
        lock.unlock()
    }
}
