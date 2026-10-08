// Menu.swift
// His menu (on his menu-bar icon, and on a right-click on him), the Convert
// to Symbol dialog with its hidden names, and the loop that runs him.

import Cocoa

// ----------------------------------------------------------- convert to symbol
// Hidden names. Call the symbol after one of Alan Becker's stick figures and he
// becomes it: he takes its colour and does the thing that figure is known for.
struct Egg { let name: String; let r: Double, g: Double, b: Double; let act: String }

let EGGS: [String: Egg] = [
    "victim":       Egg(name: "The Victim",        r: 20,  g: 20,  b: 26,  act: "launch"),
    "chosenone":    Egg(name: "The Chosen One",    r: 40,  g: 46,  b: 64,  act: "launch"),
    "tco":          Egg(name: "The Chosen One",    r: 40,  g: 46,  b: 64,  act: "launch"),
    "chosen":       Egg(name: "The Chosen One",    r: 40,  g: 46,  b: 64,  act: "launch"),
    "darklord":     Egg(name: "The Dark Lord",     r: 58,  g: 30,  b: 74,  act: "chase"),
    "dark":         Egg(name: "The Dark Lord",     r: 58,  g: 30,  b: 74,  act: "chase"),
    "secondcoming": Egg(name: "The Second Coming", r: 247, g: 148, b: 29,  act: "cheer"),
    "tsc":          Egg(name: "The Second Coming", r: 247, g: 148, b: 29,  act: "cheer"),
    "orange":       Egg(name: "The Second Coming", r: 247, g: 148, b: 29,  act: "cheer"),
    "red":          Egg(name: "Red",               r: 224, g: 49,  b: 49,  act: "launch"),
    "green":        Egg(name: "Green",             r: 47,  g: 158, b: 68,  act: "wave"),
    "blue":         Egg(name: "Blue",              r: 28,  g: 126, b: 214, act: "chase"),
    "yellow":       Egg(name: "Yellow",            r: 240, g: 180, b: 20,  act: "cheer"),
    "purple":       Egg(name: "Purple",            r: 146, g: 58,  b: 190, act: "wave"),
    "alanbecker":   Egg(name: "Alan Becker",       r: 60,  g: 60,  b: 66,  act: "wave"),
    "alan":         Egg(name: "Alan Becker",       r: 60,  g: 60,  b: 66,  act: "wave"),
    "becker":       Egg(name: "Alan Becker",       r: 60,  g: 60,  b: 66,  act: "wave"),
    "animator":     Egg(name: "Alan Becker",       r: 60,  g: 60,  b: 66,  act: "wave"),
    "noogai":       Egg(name: "Alan Becker",       r: 60,  g: 60,  b: 66,  act: "wave")
]

// the names offered in the dialog as you type, so you do not have to guess
let EGG_NAMES: [String] = Array(Set(EGGS.values.map { $0.name })).sorted()

// 'The Second Coming', 'second coming' and 'TSC' all have to land on one key.
// Case, spaces, punctuation and a leading 'the' are thrown away first, and if
// that still misses, a name with the character buried in it counts too, so
// 'red guy', 'chosen one 2' and 'blue stickman' all find their figure.
func findEgg(_ name: String) -> Egg? {
    var k = String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    if k.isEmpty { return nil }
    if k.hasPrefix("the") { k = String(k.dropFirst(3)) }
    if let e = EGGS[k] { return e }
    for key in EGGS.keys.sorted(by: { $0.count > $1.count }) where k.contains(key) { return EGGS[key] }
    return nil
}

// he takes the colour at once, and his move is queued for the moment he is back
// on something solid - see the pending block in stepPhysics
func applyEgg(_ e: Egg) {
    S.figure = e.name
    S.ink = RGB(r: e.r, g: e.g, b: e.b)
    S.pending = e.act
    S.pendTTL = 400
}

// the moves themselves, each one built only out of states the rest of the
// code already knows how to get back out of
func doEggAct(_ act: String) {
    switch act {
    case "cheer": S.state = "cheer"; S.timer = 90; S.cool = 180; S.phase = 0
    case "wave":  S.state = "wave"; S.timer = 90; S.cool = 180; S.phase = 0
    case "launch":
        S.drag = false
        S.state = "fall"
        S.vy = -14.0 * SC
        S.vx = Double(rnd(-3, 4)) * SC
    case "chase":
        let c = cursorPos()
        S.tx = c.x
        S.ty = c.y
        S.chase = 300
        S.state = "chase"
        S.phase = 0
        S.chasePeer = -1
        face(c.x - S.x)
    default: break
    }
}

struct SymbolChoice { var name: String; var type: String; var reg: Int; var fight: Bool }

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// A small stand-in for Flash's F8 dialog: a name, a symbol type and the 3x3
// registration grid. Returns what you chose, or nil if you cancelled.
func showSymbolDialog() -> SymbolChoice? {
    let alert = NSAlert()
    alert.messageText = "Convert to Symbol"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let acc = FlippedView(frame: NSRect(x: 0, y: 0, width: 344, height: 196))
    func label(_ text: String, _ x: Double, _ y: Double) {
        let l = NSTextField(labelWithString: text)
        l.frame = NSRect(x: x, y: y, width: 92, height: 20)
        acc.addSubview(l)
    }

    label("Name:", 0, 4)
    let name = NSComboBox(frame: NSRect(x: 96, y: 0, width: 240, height: 26))
    name.addItems(withObjectValues: EGG_NAMES)      // start typing a figure's name and the rest is offered
    name.completes = true
    name.stringValue = "Symbol \(S.symNum)"
    acc.addSubview(name)

    label("Type:", 0, 40)
    let type = NSPopUpButton(frame: NSRect(x: 96, y: 36, width: 150, height: 26), pullsDown: false)
    type.addItems(withTitles: ["Movie Clip", "Button", "Graphic"])
    type.selectItem(withTitle: S.symType)
    acc.addSubview(type)

    label("Registration:", 0, 80)
    let grid = FlippedView(frame: NSRect(x: 96, y: 76, width: 58, height: 58))
    grid.wantsLayer = true
    grid.layer?.borderWidth = 1
    grid.layer?.borderColor = NSColor.separatorColor.cgColor
    var regs: [NSButton] = []
    for i in 0..<9 {
        let b = NSButton(radioButtonWithTitle: "", target: HANDLER, action: #selector(Actions.regPicked(_:)))
        b.frame = NSRect(x: 2 + (i % 3) * 18, y: 2 + (i / 3) * 18, width: 18, height: 18)
        b.tag = i
        b.state = i == S.symReg ? .on : .off
        grid.addSubview(b)
        regs.append(b)
    }
    acc.addSubview(grid)

    // Animator vs. Animation, with your pointer as the animator (see startFight)
    let fight = NSButton(checkboxWithTitle: "Fight mode", target: nil, action: nil)
    fight.frame = NSRect(x: 172, y: 76, width: 170, height: 20)
    fight.state = F.on ? .on : .off
    acc.addSubview(fight)

    let note = NSTextField(wrappingLabelWithString:
        "He fights your pointer: grabs it, drags it off, throws windows at it (they go back after). Click him to hit back, Esc stops it.")
    note.frame = NSRect(x: 172, y: 98, width: 170, height: 96)
    note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .secondaryLabelColor
    acc.addSubview(note)

    alert.accessoryView = acc
    alert.layout()
    alert.window.level = .floating
    alert.window.initialFirstResponder = name
    DIALOG = alert.window                   // a window like any other: he may stand on it
    NSApp.activate(ignoringOtherApps: true)
    let res = alert.runModal()
    DIALOG = nil

    if res != .alertFirstButtonReturn { return nil }
    var n = String(name.stringValue.trimmingCharacters(in: .whitespaces).prefix(24))
    if n.isEmpty { n = "Symbol \(S.symNum)" }
    let reg = regs.firstIndex(where: { $0.state == .on }) ?? 4
    return SymbolChoice(name: n, type: type.titleOfSelectedItem ?? "Movie Clip", reg: reg, fight: fight.state == .on)
}

// wraps him in the symbol the dialog came back with
func convertSymbol(_ r: SymbolChoice) {
    S.symbol = true
    S.symType = r.type
    S.symReg = r.reg
    S.figure = ""
    S.ink = nil
    S.symNum += 1

    if let egg = findEgg(r.name) {
        applyEgg(egg)
        S.symName = egg.name                // 'tsc' fills itself in properly
        S.symFlashMax = 26                  // a longer flash, in his new colour
    } else {
        S.symName = r.name
        S.symFlashMax = 14
    }
    S.symFlash = S.symFlashMax
    if r.fight { startFight() } else if F.on { endFight() }
    syncSymbolItem()
}

func breakSymbol() {
    S.symbol = false
    S.figure = ""
    S.ink = nil
    S.pending = ""
    S.symFlashMax = 8
    S.symFlash = 8
    if F.on { endFight() }
    syncSymbolItem()
}

// the name Activity Monitor should list him under once sym is applied: the
// symbol's name (in full, for one of the hidden figures), or 'Stick figure'
func bodyName(_ sym: SymbolChoice?) -> String {
    guard let s = sym else { return PLAIN }
    if let egg = findEgg(s.name) { return egg.name }
    return s.name
}

// Converting or breaking apart. On Windows he moves into a new exe named after
// the symbol; here the running process simply takes the new name.
func switchBody(_ sym: SymbolChoice?) {
    if let s = sym { convertSymbol(s) } else { breakSymbol() }
    setProcessName(bodyName(sym))
}

// ------------------------------------------------------------------------- menu
final class Actions: NSObject {
    @objc func tick() { mainTick() }
    @objc func toss() {
        S.drag = false
        S.state = "fall"
        S.vy = -13.0 * SC
        S.vx = Double(rnd(-3, 4)) * SC
    }
    @objc func wave() { S.state = "wave"; S.timer = 70; S.phase = 0 }
    @objc func toggleShove() { S.shove.toggle(); syncChecks() }
    @objc func toggleWhite() {
        Ink.white.toggle()
        syncChecks()
        if Ink.white && !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()      // puts him in the list in System Settings
            notice("To see what is white on screen he needs Screen Recording.",
                   "Turn on \"\(PLAIN)\" under System Settings > Privacy & Security > Screen Recording, then quit him and start him again.")
        }
    }
    @objc func toggleClick() { S.click.toggle(); syncChecks() }
    @objc func toggleOpen() { S.openOn.toggle(); syncChecks() }
    @objc func toggleThrow() { S.throwOn.toggle(); syncChecks() }
    @objc func toggleGrab() {
        S.grabPtr.toggle()
        if !S.grabPtr { releasePointer() }
        syncChecks()
    }
    @objc func allowAccess() {
        askForAccessibility()
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }
    @objc func convert() { if let r = showSymbolDialog() { switchBody(r) } }
    // converting again while he already is one just swaps the figure, so this
    // is the only way back to his plain self
    @objc func breakApart() { switchBody(nil) }
    @objc func stopFight() { endFight() }
    @objc func another() { launchAnother() }
    @objc func quit() { quitStickman() }
    @objc func quitAll() { Peers.quitAll(); quitStickman() }
    @objc func regPicked(_ sender: NSButton) { }     // the radio buttons group themselves
}
let HANDLER = Actions()

func menuItem(_ title: String, _ action: Selector, _ tip: String? = nil) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
    i.target = HANDLER
    i.toolTip = tip
    return i
}

let MENU = NSMenu()
let accessItem = menuItem("Allow him to move windows\u{2026}", #selector(Actions.allowAccess),
                          "Pushing, knocking and throwing windows, and finding buttons and desktop icons, need the Accessibility permission.")
let shoveItem = menuItem("Let him push windows", #selector(Actions.toggleShove))
let whiteItem = menuItem("Let him stand on anything white", #selector(Actions.toggleWhite),
                         "Also lets him walk on the ink in a paint program or on the Gravity Pencil page. Needs Screen Recording.")
let clickItem = menuItem("Let him really press buttons", #selector(Actions.toggleClick),
                         "Off by default: when on, standing on a button actually presses it.")
let openItem = menuItem("Let him open desktop icons", #selector(Actions.toggleOpen),
                        "When he stamps on a desktop icon it opens, at most once every 45 seconds. Only apps, folders, aliases and web links.")
let throwItem = menuItem("Let him throw windows in a fight", #selector(Actions.toggleThrow),
                         "In fight mode he throws windows at your pointer. They are only moved, never closed, and go back where they were when the fight ends.")
let grabItem = menuItem("Let him grab the pointer in a fight", #selector(Actions.toggleGrab),
                        "In fight mode he grabs your pointer and drags it off. Wiggle the mouse hard or click him to get it back; he never clicks anything.")
let symItem = menuItem("Convert to Symbol\u{2026}", #selector(Actions.convert),
                       "Wraps him in a symbol box with a registration point, the way F8 does in Flash.")
let breakItem = menuItem("Break apart", #selector(Actions.breakApart), "Unwraps the symbol and gives him his own ink back.")
let fightItem = menuItem("Stop the fight", #selector(Actions.stopFight), "Ends fight mode. Esc does the same.")

var statusItem: NSStatusItem? = nil

func buildMenu() {
    MENU.autoenablesItems = false
    MENU.addItem(accessItem)
    MENU.addItem(menuItem("Toss in the air", #selector(Actions.toss)))
    MENU.addItem(menuItem("Wave at me", #selector(Actions.wave)))
    MENU.addItem(shoveItem)
    MENU.addItem(whiteItem)
    MENU.addItem(clickItem)
    MENU.addItem(openItem)
    MENU.addItem(throwItem)
    MENU.addItem(grabItem)
    MENU.addItem(NSMenuItem.separator())
    MENU.addItem(symItem)
    MENU.addItem(breakItem)
    MENU.addItem(fightItem)
    MENU.addItem(NSMenuItem.separator())
    MENU.addItem(menuItem("Add another stickman", #selector(Actions.another)))
    MENU.addItem(NSMenuItem.separator())
    MENU.addItem(menuItem("Quit", #selector(Actions.quit)))
    MENU.addItem(menuItem("Quit all stickmen", #selector(Actions.quitAll)))
    accessItem.isHidden = axTrusted()
    whiteItem.isEnabled = Ink.supported
    if !Ink.supported { whiteItem.toolTip = "Needs macOS 14 or later." }
    syncChecks()
    syncSymbolItem()
}

func syncChecks() {
    shoveItem.state = S.shove ? .on : .off
    whiteItem.state = Ink.white ? .on : .off
    clickItem.state = S.click ? .on : .off
    openItem.state = S.openOn ? .on : .off
    throwItem.state = S.throwOn ? .on : .off
    grabItem.state = S.grabPtr ? .on : .off
}

// keeps the menu entries and the menu-bar tooltip in step with what he currently is
func syncSymbolItem() {
    breakItem.isEnabled = S.symbol
    fightItem.isHidden = !F.on
    var tip: String
    if S.symbol {
        symItem.toolTip = "He is the symbol '\(S.symName)' (\(S.symType)). Converting again just swaps him."
        tip = S.figure.isEmpty ? "Desktop Stickman - \(S.symName)" : "Desktop Stickman - \(S.figure)"
    } else {
        symItem.toolTip = "Wraps him in a symbol box with a registration point, the way F8 does in Flash."
        tip = "Desktop Stickman"
    }
    if F.on { tip += " (fighting)" }
    statusItem?.button?.toolTip = tip
}

// right-click (or Control-click) on him
func showMenu(_ e: NSEvent, _ v: NSView) {
    NSMenu.popUpContextMenu(MENU, with: e, for: v)
}

func notice(_ title: String, _ text: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    a.runModal()
}

// the menu-bar icon, drawn from the same stick figure as the Windows tray icon
func trayImage() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        guard let g = NSGraphicsContext.current?.cgContext else { return false }
        let k = 18.0 / 32.0
        g.setStrokeColor(CGColor(gray: 0, alpha: 1))
        g.setLineWidth(1.7)
        g.setLineCap(.round)
        g.strokeEllipse(in: CGRect(x: 11 * k, y: 3 * k, width: 10 * k, height: 10 * k))
        let lines: [(Double, Double, Double, Double)] = [
            (16, 13, 16, 21), (16, 15, 9, 20), (16, 15, 23, 20), (16, 21, 10, 29), (16, 21, 22, 29)
        ]
        g.beginPath()
        for s in lines {
            g.move(to: CGPoint(x: s.0 * k, y: s.1 * k))
            g.addLine(to: CGPoint(x: s.2 * k, y: s.3 * k))
        }
        g.strokePath()
        return true
    }
    img.isTemplate = true                   // black or white to suit the menu bar
    return img
}

// ------------------------------------------------------------------- main loop
var keyMonitors: [Any] = []
var napBlocker: NSObjectProtocol? = nil

func startStickman() {
    refreshScreens()
    // an app that is not answering must never hold him up for long
    _ = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
    // he is always on screen and moving, so App Nap must not slow him down
    napBlocker = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                       reason: "Animating the stick figure")
    STICK_PIDS.insert(getpid())
    setProcessName(PLAIN)
    ME = Peers.join()

    Ink.white = Ink.supported && CGPreflightScreenCaptureAccess()
    Ink.start()
    SCAN.setFinder(finderPid())
    SCAN.start()

    makeSprite()
    buildMenu()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = trayImage()
    item.menu = MENU
    statusItem = item
    syncSymbolItem()

    // Esc stops a fight; a global monitor sees it in other programs, once he
    // has the Accessibility permission
    if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { e in
        if e.keyCode == 53 { ESC_TAPPED = true }
    }) { keyMonitors.append(m) }
    if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in
        if e.keyCode == 53 { ESC_TAPPED = true }
        return e
    }) { keyMonitors.append(m) }

    let vs = virtualScreen()
    S.x = Double(rnd(ri(vs.left + 150 * SC), ri(vs.right - 150 * SC)))
    S.y = vs.top + 40 * SC
    updateWorld()
    placeSprite()

    // the first time he runs, macOS is asked to let him move windows
    if !axTrusted() && !UserDefaults.standard.bool(forKey: "askedForAccessibility") {
        UserDefaults.standard.set(true, forKey: "askedForAccessibility")
        askForAccessibility()
    }

    let t = Timer(timeInterval: 0.03, target: HANDLER, selector: #selector(Actions.tick), userInfo: nil, repeats: true)
    t.tolerance = 0.004
    RunLoop.main.add(t, forMode: .common)       // keeps going while a menu or the dialog is open
}

func mainTick() {
    refreshScreens()
    stepPhysics()
    if F.grab { stepGrab() }        // after he has moved, so it sits right in his hand
    // tell the others where he is, and see if one of them asked everyone to go
    publishSelf()
    if Peers.quitAsked() { quitStickman(); return }
    if S.symFlash > 0 { S.symFlash -= 1 }
    placeSprite()
    if F.fx > 0 { drawFx() }
    if S.tick % 50 == 0 {
        // stay above other floating windows without ever taking the focus
        spriteWin?.orderFrontRegardless()
        accessItem.isHidden = axTrusted()
    }
}

func quitStickman() {
    for p in PROPS { removeProp(p) }
    putWindowsBack()
    releasePointer()
    Peers.leave()
    if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
    NSApp.terminate(nil)
}
