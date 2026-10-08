// main.swift
// Desktop Stickman for macOS - a port of stickman.ps1.
//
// A stick figure that lives on your desktop. He walks the ground, walks across
// the tops of your open windows, climbs up their edges, and interacts with
// what is around him:
//
//   * walks the ground (the top of the Dock), window title bars and the
//     buttons inside windows
//   * stands and walks on anything solid white on screen (menu toggle; needs
//     the Screen Recording permission)
//   * climbs the desktop icons and stands on them, when the desktop shows
//   * stamping on a desktop icon opens it (menu toggle, on by default, once a
//     minute at most; only apps, folders, aliases and web links)
//   * drops off a title bar down onto the buttons below and stamps on them
//   * rides a window as you drag it around
//   * notices your mouse pointer and waves at it
//   * knocks on a window edge he does not feel like climbing
//   * shoves a window a little sideways (toggle it off in the menu)
//   * sits on the edge of a window and swings his legs
//   * runs over to wherever you click and cheers when he gets there
//   * run more than one and they meet up: they wave, high-five, chat, dance,
//     play tag, wave back across the screen, and join in when one cheers
//   * drag him with the mouse, click him for a jump
//   * right-click (or Control-click) him, or use his menu-bar icon, to quit
//   * shows up in Activity Monitor as 'Stick figure', or as whatever you
//     named the symbol when you converted him
//   * tick Fight mode when you convert him and he takes on your mouse pointer,
//     Animator vs. Animation style: punches, kicks, grabbing it and dragging
//     it off, and windows thrown at it (they go back where they were
//     afterwards; with none to hand he throws little Flash panels of his own);
//     click him to hit back, Esc to stop
//
// Moving windows, finding buttons and finding desktop icons all need the
// Accessibility permission; standing on white needs Screen Recording. Without
// them he still walks, climbs, chats and fights - he just leaves your windows
// alone.

import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)     // no Dock icon: he lives in the menu bar
startStickman()
app.run()
