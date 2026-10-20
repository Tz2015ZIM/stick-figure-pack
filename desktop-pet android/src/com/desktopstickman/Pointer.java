package com.desktopstickman;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

// Your pointer, in a fight. A phone has none, so when a fight starts a white
// arrow turns up on screen and that is the animator: drag it about with a
// finger. He teleports to it, punches and kicks it, grabs it and runs off with
// it, and throws things at it. A blow knocks it out of your finger.
//
// It has hits of its own: the little bar that shows under it for a moment each
// time he lands one. Run it down to nothing and he breaks it. It hangs there
// cracking while everything freezes, bursts into pieces that clatter down onto
// whatever is below, and he celebrates. Then the pieces shiver, fly back
// together, and with a flash it is whole again, at full strength - and he
// squares up for another round. Tap the pieces to mend it sooner.
//
// Everything here is $PTR and its functions in stickman.ps1, shared by every
// stickman in a fight, since a phone has just the one of you.
final class Pointer {
    static final int CRACK_LEN  = 10;   // frames it hangs there cracking, everything frozen, before it bursts
    static final int DEAD_LEN   = 120;  // frames from breaking to starting to mend, unless you tap it
    static final int SHIVER_LEN = 14;   // the pieces shiver where they lie,
    static final int REJOIN_LEN = 24;   // fly back together,
    static final int GLOW_LEN   = 14;   // and it flashes whole again
    static final int BAR_SHOW   = 60;   // frames the bar stays up after a hit
    static final int SHARDS     = 8;

    // the plain white arrow with a black edge (New-ArrowImage), in design
    // units; bigger than a mouse pointer, so a finger can find it
    static final float ARROW = 1.5f;
    static final float[] ARROW_XY = { 0, 0, 0, 16.5f, 4, 12.6f, 6.8f, 19.2f, 9.4f, 18.1f, 6.7f, 11.7f, 11.8f, 11.7f };
    static final float ARROW_W = 15, ARROW_H = 23, ARROW_PAD = 1.5f;

    final Room room;
    final float sc;
    final double shardGrav;

    boolean up;                 // on screen: somebody is fighting it
    float x, y;                 // its tip, on screen
    boolean held;               // your finger has it
    boolean loose;              // knocked out of your finger, which is still down
    float offX, offY;           // tip minus finger, while held
    float pullX, pullY;         // how far your finger dragged at it since he last looked, while he has it
    private float lastFX, lastFY;
    private double travel;      // how far the finger went since it came down

    int hp = 10, max = 10;      // hits it can take, see Stick.Level
    double shown = 10;          // what the bar shows, easing after hp
    int bar;                    // frames left of the bar showing
    boolean dead;               // in pieces
    int t;                      // frames since it broke
    boolean mend;               // pulling itself back together
    int mt;                     // frames into that
    boolean hurry;              // you tapped: mend as soon as the pieces are down
    float bx, by;               // where it broke, and where it stays meanwhile
    double kx, ky;              // the way the blow that broke it was going
    final Spark spark = new Spark();

    // the picture the pieces are cut from: the arrow, in pixels
    float imgW, imgH, hx, hy, cx, cy;
    final List<Shard> shards = new ArrayList<>();
    float wx, wy, ww, wh;       // the wreck window, on screen
    double floor;               // what the pieces land on

    static final class Shard {
        float[] tri;                    // the wedge, in picture pixels
        double px, py;                  // what it turns about, in the picture
        double dx, dy;                  // which way it faces out from the middle
        double hx, hy;                  // home: where that sits with the pointer whole
        double x, y, vx, vy, rot, vr;
        boolean rest;
        double sx, sy, sr;              // where it set off from, mending
    }

    Pointer(Room room) {
        this.room = room;
        this.sc = room.sc;
        this.shardGrav = 0.55 * sc;
    }

    // a fight started: it turns up a little above the middle of the screen
    void show() {
        if (up) return;
        up = true;
        held = false; loose = false;
        x = (room.workL + room.workR) / 2f;
        y = room.workT + (room.workB - room.workT) * 0.4f;
    }

    // nobody is fighting it any more
    void hide() {
        restore();
        up = false; bar = 0; held = false; loose = false;
    }

    // put the tip at (nx, ny), never off the screen, or under the status or
    // navigation bar where your finger could not get at it
    void move(double nx, double ny) {
        x = (float) Math.max(room.workL, Math.min(room.workR - 1, Math.round(nx)));
        y = (float) Math.max(room.workT, Math.min(room.workB - 1, Math.round(ny)));
    }

    // ------------------------------------------------------------ your finger
    Stick holder() {
        for (Stick s : room.sticks) if (s.f.grab) return s;
        return null;
    }

    void fingerDown(float fx, float fy) {
        if (dead) { hurry = true; return; }
        held = true; loose = false;
        offX = x - fx; offY = y - fy;
        lastFX = fx; lastFY = fy;
        travel = 0; pullX = pullY = 0;
    }

    void fingerMove(float fx, float fy) {
        float dx = fx - lastFX, dy = fy - lastFY;
        lastFX = fx; lastFY = fy;
        travel += Math.sqrt(dx * dx + dy * dy);
        if (!held || dead) return;
        // he has hold of it: that is you pulling against him, see Stick.stepGrab
        if (holder() != null) { pullX += dx; pullY += dy; return; }
        move(fx + offX, fy + offY);
    }

    void fingerUp(float fx, float fy) {
        boolean tap = held && travel < 6 * sc;
        held = false; loose = false;
        // a tap on it while he has it lands on him, as a click on the grip pad
        // does on Windows: he lets go, and it counts as a hit
        Stick s = holder();
        if (tap && s != null) s.gripTap(fx, fy);
    }

    // a blow lands on it: whatever finger had it, it is knocked out of
    void knock() {
        if (held) { held = false; loose = true; }
    }

    // you pulled it out of his hand: it is back under your finger
    void yanked() {
        if (held) move(lastFX + offX, lastFY + offY);
    }

    // ------------------------------------------------------------ breaking it
    // a blow landed on it: true if that broke it
    boolean hurt(int dmg, double kx, double ky) {
        if (!room.killPtr || dead) return false;
        hp = Math.max(0, hp - dmg);
        bar = BAR_SHOW;
        if (hp > 0) return false;
        breakIt(kx, ky);
        return true;
    }

    void breakIt(double kx, double ky) {
        for (Stick s : room.sticks) { s.releasePointer(); s.f.kn = 0; }
        dead = true; t = 0; mend = false; mt = 0; hurry = false;
        bx = x; by = y; this.kx = kx; this.ky = ky;
        bar = 0;
        knock();
        picture();
        openWreck();
        newShards();
        // whatever he had hold of it with, he lets go to celebrate
        for (Stick s : room.sticks) {
            if (s.state.equals("haul") || s.state.equals("fling")) { s.state = "guard"; s.phase = 0.0; }
        }
    }

    // the arrow's picture: its size, its hot spot, and where the cracks start
    // from (the middle of what can be seen of it)
    void picture() {
        float k = ARROW * sc;
        imgW = (float) Math.ceil(ARROW_W * k);
        imgH = (float) Math.ceil(ARROW_H * k);
        hx = hy = Math.round(ARROW_PAD * k);
        double a = 0, mx = 0, my = 0;
        int n = ARROW_XY.length / 2;
        for (int i = 0; i < n; i++) {
            double x0 = ARROW_XY[2 * i], y0 = ARROW_XY[2 * i + 1];
            double x1 = ARROW_XY[2 * ((i + 1) % n)], y1 = ARROW_XY[2 * ((i + 1) % n) + 1];
            double c = x0 * y1 - x1 * y0;
            a += c; mx += (x0 + x1) * c; my += (y0 + y1) * c;
        }
        cx = (float) ((ARROW_PAD + mx / (3 * a)) * k);
        cy = (float) ((ARROW_PAD + my / (3 * a)) * k);
    }

    // the top of whatever is under the spot where it broke: a window, a button,
    // an app icon, or the bottom of the screen
    double findFloor() {
        double best = room.floor();
        if (best < by + 12 * sc) best = room.scrB;         // it broke down on the navigation bar, or the keyboard
        for (Ledge l : room.seen) {
            if (bx < l.l || bx > l.r) continue;
            if (l.t > by + 12 * sc && l.t < best) best = l.t;
        }
        return Math.max(best, by + 12 * sc);
    }

    // the wreck window: wide enough for the pieces to scatter, and reaching
    // down to where they land
    void openWreck() {
        int half = (int) (170 * sc);
        floor = findFloor();
        wx = bx - half; ww = 2 * half;
        wy = by - (int) (110 * sc);
        wh = (float) Math.ceil(floor - wy + 6 * sc);
    }

    // The picture cut into wedges from the middle out. Each is a triangle far
    // bigger than the pointer, so between them they cover all of it, and filled
    // with the picture it shows just its own piece.
    void newShards() {
        Random rng = room.rng;
        shards.clear();
        double far = 2.0 * (imgW + imgH);
        double step = 2 * Math.PI / SHARDS;
        double a0 = rng.nextDouble() * step;
        double[] cuts = new double[SHARDS];
        for (int i = 0; i < SHARDS; i++) cuts[i] = a0 + i * step + (rng.nextDouble() - 0.5) * 0.5 * step;
        double left = bx - hx, top = by - hy;              // where the picture sits on screen
        double pr = 0.18 * Math.min(imgW, imgH);
        for (int i = 0; i < SHARDS; i++) {
            double a = cuts[i];
            double b = i + 1 < SHARDS ? cuts[i + 1] : cuts[0] + 2 * Math.PI;
            double m = (a + b) / 2.0;
            Shard sh = new Shard();
            sh.tri = new float[] {
                cx, cy,
                (float) (cx + Math.cos(a) * far), (float) (cy + Math.sin(a) * far),
                (float) (cx + Math.cos(b) * far), (float) (cy + Math.sin(b) * far),
            };
            sh.px = cx + Math.cos(m) * pr;
            sh.py = cy + Math.sin(m) * pr;
            sh.dx = Math.cos(m); sh.dy = Math.sin(m);
            sh.hx = left + sh.px; sh.hy = top + sh.py;
            sh.x = sh.hx; sh.y = sh.hy;
            shards.add(sh);
        }
    }

    // the moment it bursts: a spark, and every piece goes flying, out from the
    // middle and on the way the blow was going
    void burst() {
        Random rng = room.rng;
        spark.pop(bx, by, rng);
        double kl = Math.max(1.0, Math.sqrt(kx * kx + ky * ky));
        for (Shard sh : shards) {
            double v = (2.5 + 3.5 * rng.nextDouble()) * sc;
            sh.vx = sh.dx * v * 0.8 + kx / kl * 2.5 * sc;
            sh.vy = sh.dy * v - (2.5 + 2.0 * rng.nextDouble()) * sc + ky / kl * 1.5 * sc;
            sh.vr = (rng.nextDouble() * 2 - 1) * 16.0;
        }
    }

    // one piece, one frame, flying or bouncing; false once it lies still
    boolean stepShard(Shard sh) {
        if (sh.rest) return false;
        sh.vy += shardGrav;
        sh.vx *= 0.96;
        sh.x += sh.vx; sh.y += sh.vy;
        sh.rot += sh.vr;
        double lo = floor - 2 * sc;
        if (sh.y > lo) {
            sh.y = lo;
            sh.vy = sh.vy > 3 * sc ? -sh.vy * 0.4 : 0.0;
            sh.vx *= 0.6; sh.vr *= 0.6;
            if (sh.vy == 0.0 && Math.abs(sh.vx) < 0.3 * sc) sh.rest = true;
        }
        // the edges of the wreck window hold them in
        double edge = 6 * sc;
        if (sh.x < wx + edge) { sh.x = wx + edge; sh.vx = Math.abs(sh.vx) * 0.4; }
        else if (sh.x > wx + ww - edge) { sh.x = wx + ww - edge; sh.vx = -Math.abs(sh.vx) * 0.4; }
        if (sh.y < wy + edge) { sh.y = wy + edge; sh.vy = Math.abs(sh.vy) * 0.3; }
        return true;
    }

    void startMend() {
        mend = true; mt = 0;
        for (Shard sh : shards) {
            sh.sx = sh.x; sh.sy = sh.y;
            double r = sh.rot % 360.0;                      // the short way back round to upright
            if (r > 180) r -= 360; else if (r < -180) r += 360;
            sh.sr = r;
        }
    }

    // every frame it is in pieces
    void stepWreck() {
        t++;
        if (t > DEAD_LEN + 300) { restore(); return; }     // never stuck like this
        if (t < CRACK_LEN) return;
        if (t == CRACK_LEN) burst();
        if (!mend) {
            if (t >= DEAD_LEN || (hurry && t >= CRACK_LEN + 24)) {
                startMend();
            } else {
                for (Shard sh : shards) stepShard(sh);
                return;
            }
        }
        mt++;
        if (mt >= SHIVER_LEN + REJOIN_LEN + GLOW_LEN) restore();
    }

    // where a piece is drawn this frame: x, y on screen, and its turn in degrees
    double[] shardPose(Shard sh, Random rng) {
        if (t < CRACK_LEN) {
            // still in one piece, but the cracks are opening and it shakes
            double gap = Math.pow(t / (double) CRACK_LEN, 2) * 1.6 * sc;
            double j = (t % 2 == 0 ? 1 : -1) * 0.8 * sc;
            return new double[] { sh.hx + sh.dx * gap + j, sh.hy + sh.dy * gap, 0.0 };
        }
        if (!mend) return new double[] { sh.x, sh.y, sh.rot };
        if (mt <= SHIVER_LEN) {
            double j = 1.2 * sc;
            return new double[] { sh.sx + (rng.nextDouble() * 2 - 1) * j, sh.sy + (rng.nextDouble() * 2 - 1) * j,
                                  sh.sr + (rng.nextDouble() * 2 - 1) * 6 };
        }
        // home on an arc, easing in and out, turning upright as it goes
        double u = Math.min(1.0, (mt - SHIVER_LEN) / (double) REJOIN_LEN);
        double e = u * u * (3 - 2 * u);
        double lift = Math.sin(u * Math.PI) * 36 * sc;
        return new double[] { sh.sx + (sh.hx - sh.sx) * e, sh.sy + (sh.hy - sh.sy) * e - lift, sh.sr * (1 - e) };
    }

    // frames into the flash once it is whole again, or -1
    int glow() { return mend ? mt - SHIVER_LEN - REJOIN_LEN : -1; }

    // whole again, and yours: full strength, right where it broke
    void restore() {
        if (!dead) return;
        dead = false; mend = false;
        x = bx; y = by;
        hp = max; shown = 0.0; bar = BAR_SHOW;     // the bar fills back up
        shards.clear();
        for (Stick s : room.sticks) {
            s.f.kn = 0;
            if (s.state.equals("win") || s.state.equals("shock")) { s.state = "taunt"; s.timer = 50; s.phase = 0.0; }
        }
    }

    // the bar, every frame it is up (Draw-PtrBar)
    void stepBar() {
        if (--bar <= 0 || dead || !room.anyFighting()) { bar = 0; return; }
        shown += (hp - shown) * 0.2;
    }
}
