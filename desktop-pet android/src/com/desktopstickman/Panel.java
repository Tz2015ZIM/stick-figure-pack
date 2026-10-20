package com.desktopstickman;

// The little Flash panels he conjures to throw at your pointer (Conjure-Prop).
// On Windows they are the fallback for when none of your windows will do; on a
// phone nobody else's windows can be moved, so they are all he ever throws.
// They are his, not yours: once one has landed it hangs about a moment and
// vanishes, and any left go when the fight ends.
final class Panel {
    static final String[] TITLES = { "Library", "Properties", "Timeline", "Actions - Frame", "Color Mixer", "Tools" };
    static final String[][] ROWS = {
        { "Symbol 1", "Stick figure", "Tween 1", "Sound 1" },
        { "Movie Clip", "W: 44    H: 68", "X: 400   Y: 200", "Instance of: Symbol 1" },
        { "Layer 1", "Layer 2", "Guide: Layer 1", "Actions" },
        { "stop();", "this.fight();", "gotoAndPlay(\"attack\");", "trace(\"run\");" },
        { "#000000", "#FFFFFF", "#0099FF", "#FF0000" },
        { "Selection", "Pencil", "Brush", "Eraser" },
    };
    // design units: 220 x 140 on Windows, a little smaller on a phone screen
    static final double K = 0.8, W = 220 * K, H = 140 * K, TITLE = 22 * K;

    final int kind;
    final double w, h;
    double x, y;                // top-left, on screen
    int life;                   // frames left once it has landed

    // in his hands, then in the air
    double hx, hy;              // where it sat when he took hold of it
    double vx, vy;
    int t, len;
    boolean hit;                // it has caught the pointer once already

    Panel(int kind, double x, double y, double w, double h) {
        this.kind = kind; this.x = x; this.y = y; this.w = w; this.h = h;
    }
}
