# Desktop Stickman for macOS

The Mac version of Desktop Stickman: the same stick figure, the same moves,
fights and hidden names, rewritten in Swift because PowerShell and Win32
aren't available on a Mac.

## Build and start him

1. Copy this folder to the Mac.
2. Open **Terminal**, `cd` into the folder, and run:

   ```
   bash build.sh
   ```

   The first time, macOS may offer to install the *command line developer
   tools* (the Swift compiler). Accept, wait for it to finish, and run
   `bash build.sh` again.
3. Double-click **Desktop Stickman.app** (or `open "Desktop Stickman.app"`).
   He drops in from the top of the screen, and a little stick figure appears
   in the menu bar. That icon holds his menu.

`bash build.sh universal` builds one app that runs on both Apple silicon and
Intel Macs, if you want to pass it on.

To have him start with the Mac: System Settings > General > Login Items >
**+** > Desktop Stickman.app.

## Permissions

macOS asks before a program can touch other programs' windows or look at the
screen. The stickman works without either permission, just with fewer tricks.

| Permission | What it unlocks | Where |
|---|---|---|
| **Accessibility** | pushing, knocking and throwing windows; standing on buttons inside windows; standing on and opening desktop icons | asked for on first launch, or menu > *Allow him to move windows…* |
| **Screen Recording** | *Let him stand on anything white*, and walking on the ink in a paint program or on the Gravity Pencil page (macOS 14+) | turn the menu item on; macOS adds him to the list |

Both are in System Settings > Privacy & Security. The entry is called
**Stick figure**. After you allow Screen Recording, quit him and start him
again.

**After a rebuild**, macOS treats the new build as a different app. If windows
stop moving, open Privacy & Security > Accessibility, remove *Stick figure*
with **−**, and add the app again (or switch it off and on).

## Differences from the Windows version

- **Menu**: his menu-bar icon replaces the tray icon. Right-click him, or
  Control-click him, for the same menu. *Wave at me* replaces double-clicking
  the tray icon.
- **Ground**: he walks on top of the Dock (the bottom of the usable screen)
  instead of the taskbar.
- **Activity Monitor name**: he shows up as *Stick figure*, or under the
  symbol's name after you convert him. Windows needs a separate exe for each
  name; on the Mac the running process just renames itself, so there is no
  `processes` folder.
- **Desktop icons**: he stamps on the icons Finder shows on the desktop. Only
  apps, folders, aliases and web links on your Desktop open, at most once
  every 45 seconds.
- **Buttons**: *Let him really press buttons* (off by default) presses
  buttons through Accessibility. He never touches the red, yellow or green
  window buttons.
- **Paint ink**: Paint doesn't exist on the Mac. He treats any app whose name
  starts with "Paint" (Paintbrush, for example), or Pinta, the same way, plus
  the Gravity Pencil page in any browser.
- **Fight mode**: works the same. He never throws Activity Monitor or anything
  that floats above normal windows, and everything he threw glides back when
  the fight ends or when he quits. Esc stops the fight.

## Files

| File | Windows counterpart |
|---|---|
| `Sources/Stickman.swift` | the behaviour in `stickman.ps1`: world, moves, friends, fight |
| `Sources/Drawing.swift` | `Draw-Figure`, sparks, grip pad, prop panels |
| `Sources/Menu.swift` | tray menu, Convert to Symbol dialog, hidden names, main loop |
| `Sources/Platform.swift` | the `[SM]` class: windows, pointer, screens, his name |
| `Sources/Scanner.swift` | the UI Automation runspace (buttons) and desktop icon lookup |
| `Sources/Ink.swift` | the `[Ink]` class (white and ink ground) |
| `Sources/Peers.swift` | the `[Peers]` class (shared memory between copies) |
| `build.sh`, `Info.plist`, `stickman.icns` | `stickhost.cs`, `Start Stickman.vbs`, `stickman.ico` |
