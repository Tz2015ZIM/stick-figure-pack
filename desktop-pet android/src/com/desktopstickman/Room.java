package com.desktopstickman;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

// Everything the stickmen share: the screen and what is on it, your pointer in
// a fight, the settings from the menu, and each other. On Windows every copy
// of him is a process of its own and they meet through shared memory (the
// [Peers] class); here they all live in one service, and this is that memory.
//
// Nothing in here, or in Stick, Pointer, Panel and Figure, touches Android, so
// all of it also runs on a plain JVM (see tools/Preview.java).
final class Room {
    // what only the phone can do for him
    interface Hands {
        boolean openApp(String label);  // stamping on an app icon opens that app
        void press(Ledge b);            // stamping on a button presses it, if you allowed it
    }

    static final int SLOTS = 16;

    final float sc;                     // pixels per design unit: his 96-dpi units on Windows, dp here
    final Random rng = new Random();
    final Pointer ptr;
    final List<Stick> sticks = new ArrayList<>();
    Hands hands;

    // the whole screen, and the part apps use: inside the status bar and the
    // navigation bar, which is where his ground is
    int scrL, scrT, scrR, scrB;
    int workL, workT, workR, workB;

    // what the accessibility service last saw: windows, the keyboard, buttons, app icons
    Ledge[] seen = new Ledge[0];

    // the tray menu's ticks
    boolean open = true;        // stamping on an app icon opens it
    boolean click = false;      // standing on a button really presses it
    boolean throwOk = true;     // he throws things at your pointer in a fight
    boolean grabPtr = true;     // he grabs your pointer and runs off with it
    boolean killPtr = true;     // he breaks your pointer when its hits run out

    // A phone has no pointer hovering about. The nearest thing is a finger on
    // one of his windows (dragging him, a friend, or your pointer in a fight).
    boolean hover;
    float hoverX, hoverY;

    // where you last tapped, for the moves that run at "the pointer"
    float tapX = -1, tapY = -1;

    long frame;                 // frames so far
    long lastOpen = -99999;     // frame of the last app he opened, to keep it occasional

    Room(float sc) {
        this.sc = sc;
        this.ptr = new Pointer(this);
    }

    void setScreen(int l, int t, int r, int b, int wl, int wt, int wr, int wb) {
        scrL = l; scrT = t; scrR = r; scrB = b;
        workL = wl; workT = wt; workR = wr; workB = wb;
    }

    // The bottom of the screen, or the top of the keyboard while it is up: the
    // keyboard is drawn over every app's floating windows, him included, so
    // standing behind it he would just vanish.
    double floor() {
        double y = workB;
        for (Ledge l : seen) if (docked(l) && l.t < y) y = l.t;
        return y;
    }

    // a keyboard across the bottom of the screen; a floating one is just
    // something else to stand on
    boolean docked(Ledge l) {
        return l.kbd && l.r - l.l >= (workR - workL) * 0.9 && l.b >= workB - 8 * sc;
    }

    // the ground, a little in from the sides (Get-Ground)
    Ledge ground() {
        return new Ledge(0, workL + 4 * sc, floor(), workR - 4 * sc, 1e6, true, false, false, false, "");
    }

    Stick add() {
        if (sticks.size() >= SLOTS) return null;
        boolean[] used = new boolean[SLOTS];
        for (Stick s : sticks) used[s.slot] = true;
        int slot = 0;
        while (used[slot]) slot++;
        Stick s = new Stick(this, slot);
        sticks.add(s);
        return s;
    }

    void remove(Stick s) {
        s.dropEverything();
        sticks.remove(s);
        if (!anyFighting()) ptr.hide();
    }

    Stick bySlot(int slot) {
        for (Stick s : sticks) if (s.slot == slot) return s;
        return null;
    }

    // every other stickman, as he last published himself (Peers.Others)
    List<Peer> others(Stick me) {
        List<Peer> list = new ArrayList<>();
        for (Stick s : sticks) if (s != me && s.pub.live) list.add(s.pub);
        return list;
    }

    boolean anyFighting() {
        for (Stick s : sticks) if (s.f.on) return true;
        return false;
    }

    // you tapped something on screen (the accessibility service saw it)
    void tapped(float x, float y) {
        tapX = x; tapY = y;
        for (Stick s : sticks) s.onTap(x, y);
    }

    // one frame for all of them, in the order the Windows timer runs a copy of him
    void step() {
        frame++;
        // while the pointer cracks, everything stops, them included
        boolean frozen = ptr.dead && ptr.t < Pointer.CRACK_LEN;
        for (Stick s : new ArrayList<>(sticks)) {
            if (frozen) continue;
            try {
                s.stepPhysics();
                if (s.f.grab) s.stepGrab();     // after he has moved, so it sits right in his hand
            } catch (RuntimeException e) {
                Log.trail("step", e);
                s.state = "fall"; s.vy = 0.0;
            }
        }
        if (ptr.dead) {
            try { ptr.stepWreck(); }
            catch (RuntimeException e) {
                // anything going wrong with the pieces: the pointer is simply back
                Log.trail("pointer", e);
                ptr.restore();
            }
        }
        if (ptr.bar > 0) ptr.stepBar();
        ptr.spark.step();
        for (Stick s : new ArrayList<>(sticks)) {
            s.publish();
            // you beat him, and he has faded right away: this copy of him is done
            if (s.gone > 0 && --s.gone <= 0) { remove(s); continue; }
            if (s.symFlash > 0) s.symFlash--;
            s.stepFx();
        }
    }
}
