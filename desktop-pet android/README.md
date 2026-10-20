# Desktop Stickman for Android

The phone version of Desktop Stickman: the same stick figure with the same
moves, friends, fights and hidden names, rewritten in Java because a phone has
no PowerShell, Win32, windows or mouse pointer.

## Install him

1. Copy `DesktopStickman.apk` to the phone and open it. Android asks to allow
   installing apps from whichever app opened it (Files, Chrome...): allow it.
2. Open **Desktop Stickman** and follow the screen:
   - **Display over other apps**: needed, it is what lets him be on screen.
   - **Notifications**: optional. His notification is his tray icon.
   - **Start the stickman**. He drops in from the top of the screen.
3. Optional: **let him see the screen** (see below).

He keeps running after you leave the app. Quit him from his menu or his
notification. Turning the screen off pauses him.

## Playing with him

| On Windows | On the phone |
|---|---|
| Drag him with the left button, click him for a jump | Drag him and let go to throw him; tap him and he jumps |
| Right-click him, or the tray icon, for the menu | Hold him down for his menu, or tap his notification |
| Double-click the tray icon: he waves | Every time you unlock the phone they all wave; or *Wave at me* |
| He runs to wherever you left-click | He runs to whatever you tap (needs the screen permission) |
| He waves at the mouse pointer | He waves at your finger when you drag something near him |
| Shows in Task Manager under his symbol's name | His notification lists everyone by name |

*Convert to Symbol* works as on Windows: a name (with the hidden Alan Becker
figures offered as you type), the symbol type, the registration point, and
Fight mode / Hard mode.

### Fight mode

A phone has no mouse pointer, so when a fight starts a white arrow appears:
that is your pointer, the animator. It is wherever your finger touches: it
jumps straight there and follows your finger as you drag. With a mouse, a
touchpad or a pen, it is wherever the cursor is, even with nothing pressed,
and the system's own cursor is hidden behind it, so it works like his real
pointer on Windows.

He hunts it, climbing whatever is in the way, punches, kicks and
flying-kicks it (each blow knocks it out of your finger until you touch
again), grabs it and runs off with it, and throws Flash panels at it when it
is out of reach. While he has it, wiggle your finger (or the mouse) hard to
pull it back, or just tap: he lets go, it counts as a hit, and the pointer
is where you tapped. Its health bar runs out and he smashes it to pieces and
celebrates; tap to mend it sooner. Tap him to hit back: knock him out and
"K.O.!" is typed above him as he fades away.

Android only tells an app where you touch (or where the mouse is) over its
own windows, so while there is a fight the whole screen is the arena: an
invisible window over everything, and taps go to the fight instead of your
apps. The status bar, the notifications and the keyboard still work, and so
should the home and back gestures. *Stop the fight* is in his menu (hold him
down) and on the notification (Esc on Windows).

## Let him see the screen (Accessibility)

Without it he walks the bottom of the screen and does everything else. With
it, the phone's version of looking at your windows and buttons:

- he stands on **dialogs**, either half of a **split screen** and
  picture-in-picture videos, climbs their sides and sits on their edges
- the **keyboard**: while it is up its top is the ground, so it lifts him
  up with it (otherwise he would be stuck behind it)
- **buttons and anything else you can tap** in the app you are using: he
  climbs them, stamps on them, and rides a list as you scroll it
- the **app icons on your home screen**: stamping on one opens it, at most
  once every 45 seconds (*Let him open apps he stamps on*, on by default)
- he **runs over to whatever you tap**

It only reads. It presses a button he is standing on only if you tick *Let
him really press buttons* (off by default), and never anything in the status
bar or notification shade, or his own menu. Mid-fight he never stamps on
anything at all.

Turn it on in Settings > Accessibility > Desktop Stickman. Android greys the
switch out for apps installed from an APK: go to Settings > Apps > Desktop
Stickman, tap the three dots at the top, choose **Allow restricted
settings**, and try again.

## Differences from the Windows version

- **Nothing of yours is ever moved.** Android does not let one app move
  another's windows, so he cannot push or knock windows around, ride a
  window you drag, or throw your windows in a fight: he always throws his
  own Flash panels (the fallback on Windows). He still knocks on and pushes
  against window edges; they just do not budge.
- **No Paint ink, no standing on anything white.** Seeing what is on screen
  pixel by pixel would need a screen recording, which Android only allows
  with your say-so every time and with a recording indicator up.
- **One process.** On Windows each stickman is its own process (with an exe
  per name, for Task Manager) and they find each other through shared
  memory. Here they all live in one service; the meet-ups, high-fives,
  chats, dances and games of tag work the same way.
- **Size.** He is drawn in the same design units, at 1 unit = 1 dp, so he is
  about as big on the phone as an app icon. The Flash panels are a little
  smaller than on Windows so they fit a phone screen.

## Building

Needs the JDK and three pieces of the Android SDK, no Android Studio or
Gradle. They were installed into `%USERPROFILE%\AndroidBuild` for this:

- `jdk\` - Microsoft Build of OpenJDK 21 (Windows ARM64)
- `sdk\platforms\android-36\` - the Android 16 platform
- `sdk\build-tools\36.1.0\` - aapt2, d8, zipalign, apksigner

Then, in this folder:

```
powershell -ExecutionPolicy Bypass -File build.ps1 -Test
```

`-Test` first runs him on the PC with no phone (`tools\Preview.java`): it
draws every pose into `build\preview\poses.png`, then runs three stickmen
for 40,000 frames on a made-up screen (a dialog, buttons, app icons, the
keyboard coming and going) and four fights to the K.O., and fails the build
if anything goes off screen, gets stuck behind the keyboard, opens apps too
often, presses a button with pressing off, or a fight never plays out.

The APK is signed with `stickman.keystore` (made by the first build). Keep
it: the phone only installs a new build over the old one if both are signed
with the same key. Errors he runs into on the phone go to
`stickman-error.log` in the app's files folder.

## Files

| File | Windows counterpart |
|---|---|
| `src/.../Stick.java` | `$S`, `$F` and everything that moves them: world, moves, friends, fight |
| `src/.../Figure.java` | `Draw-Figure`'s poses |
| `src/.../Pointer.java` | `$PTR`: the pointer's hits, breaking it, the pieces, mending |
| `src/.../Panel.java`, `Spark.java`, `Eggs.java` | the prop panels, `Pop-Spark`, the hidden names |
| `src/.../Room.java`, `Peer.java` | the `[Peers]` class (shared memory between copies), `Get-Ground` |
| `src/.../Art.java` | the drawing: figure, symbol box, sparks, K.O. text, panels, arrow, pieces |
| `src/.../StickService.java`, `Win.java` | the main loop, his layered windows, the tray icon |
| `src/.../Eyes.java` | `[SM]::Windows`, the UI Automation scanner, the desktop icons |
| `src/.../MenuActivity.java`, `SymbolActivity.java` | the tray menu, `Show-SymbolDialog` |
| `src/.../MainActivity.java` | (none: the setup screen) |
| `build.ps1`, `AndroidManifest.xml`, `res/` | `stickhost.cs`, `Start Stickman.vbs`, `stickman.ico` |
