package com.desktopstickman;

// Something he can stand on, climb, or stamp on: the bottom of the screen, a
// window (a dialog, one half of a split screen, the keyboard), a button inside
// one, or an app icon on the home screen. Same fields as New-Ledge in
// stickman.ps1, with a long id standing in for the window handle.
final class Ledge {
    final long h;                   // stays the same while it is the same thing, so he can ride it
    final double l, t, r, b;
    final boolean ground;           // the bottom of the screen
    final boolean max;              // takes up the whole screen
    final boolean btn;              // a button
    final boolean icon;             // an app icon on the home screen
    final String name;              // the icon's label
    boolean kbd;                    // the keyboard: while it is up, its top is the ground (see Room.floor)

    Ledge(long h, double l, double t, double r, double b, boolean ground, boolean max, boolean btn, boolean icon, String name) {
        this.h = h; this.l = l; this.t = t; this.r = r; this.b = b;
        this.ground = ground; this.max = max; this.btn = btn; this.icon = icon;
        this.name = name == null ? "" : name;
    }

    static Ledge keyboard(long h, double l, double t, double r, double b) {
        Ledge k = new Ledge(h, l, t, r, b, false, false, false, false, "");
        k.kbd = true;
        return k;
    }

    static Ledge window(long h, double l, double t, double r, double b, boolean max) {
        return new Ledge(h, l, t, r, b, false, max, false, false, "");
    }

    static Ledge button(long h, double l, double t, double r, double b) {
        return new Ledge(h, l, t, r, b, false, false, true, false, "");
    }

    static Ledge appIcon(long h, double l, double t, double r, double b, String label) {
        return new Ledge(h, l, t, r, b, false, false, false, true, label);
    }
}
