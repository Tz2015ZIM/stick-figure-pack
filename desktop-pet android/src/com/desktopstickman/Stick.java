package com.desktopstickman;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

// One stick figure: everything $S and $F hold in stickman.ps1, and every
// function that moves them, in the same order and under the same names where
// it can be. Where Windows has something a phone does not, this says what
// stands in for it:
//
//   * windows, buttons and desktop shortcuts are what the accessibility
//     service sees (Room.seen): dialogs, either half of a split screen, the
//     keyboard, buttons in the app in front, and the icons on the home screen
//   * a left-click somewhere is a tap the accessibility service saw (onTap)
//   * the mouse pointer hovering near him is a finger on one of his windows
//   * in a fight, your pointer is the arrow (Pointer), and since nobody's
//     windows can be moved on a phone, he throws his own Flash panels
//   * no Paint ink and no standing on anything white: a phone would only let
//     him see the screen through a recording, every time with your say-so
final class Stick {
    // sprite box, design units
    static final double DW = 44.0, DH = 68.0;
    static final double DCX = 22.0, DFT = 62.0;     // centre line and foot line, design units

    static final int OPEN_GAP = 1500;               // frames between app launches, about 45 seconds

    final Room room;
    final Random rng;
    final int slot;
    final double SC;
    final int BOXW, BOXH;
    final double CX, FOOT;
    final double GRAVITY, SPEED, CLIMB, VMAX;
    final double REACH;         // how far ahead he notices a wall
    final double MINWALL;       // shortest wall worth climbing
    final double EDGE;          // how close to a ledge end he gets before deciding
    final double HUG;           // how far off the wall his body sits while climbing
    final double STEPIN;        // where he plants his feet after topping out
    final double NOTICE;        // how close the pointer has to be before he reacts

    // ------------------------------------------------------------------ state
    double x = 400.0, y = 200.0;    // x = centre of body, y = the surface under his feet
    double vx, vy;
    String state = "fall";          // walk fall climb idle sit wave knock push press chase cheer leap meet social, and the fight's
    int dir = 1;                    // 1 right, -1 left
    double phase;                   // animation clock
    Ledge ledge;                    // what he is standing on
    Ledge wall;                     // what he is climbing / knocking on
    int timer;                      // frames left in the current one-shot pose
    int cool;                       // frames until he will notice the pointer again
    int tick;
    boolean drag;
    double grabX, grabY;
    double lastX;
    double dragged;
    float fingerX, fingerY;         // the finger dragging him, on screen
    Ledge[] ledges = new Ledge[0];
    long ignore;                    // window top to fall straight through, while diving in (0: none)
    double tx, ty;                  // where you last tapped, which he runs to
    int chase;                      // frames left before he gives up on getting there
    double ly0;                     // height he leapt from, to grab a window corner
    boolean hard;                   // fight in hard mode, see Level
    boolean symbol;                 // he is wrapped in a symbol box, Flash style
    String symName = "";            // what the instance was named in the dialog
    String symType = "Movie Clip";  // Movie Clip / Button / Graphic
    int symReg = 4;                 // registration point, 0..8 across the 3x3 grid
    int symNum = 1;                 // next default name, Symbol 1, Symbol 2, ...
    int symFlash;                   // frames left of the flash after converting
    int symFlashMax = 14;           // how long that flash was, so it can fade out
    String charName = "";           // the Alan Becker figure he was named after
    int ink;                        // that figure's colour...
    boolean hasInk;                 // ...or his own
    String pending = "";            // his new figure's move, waiting for him to settle
    int pendTTL;                    // frames it waits before being given up on
    List<Peer> peers = new ArrayList<>();   // the other stickmen
    int with = -1;                  // slot of the one he is meeting, or -1
    String act = "";                // what the two of them are doing together
    int meetT;                      // frames spent getting to each other
    boolean waiting;                // stood still, waiting for his friend to arrive
    int social = 300;               // frames until he goes looking for company again
    int chasePeer = -1;             // slot of the friend he is chasing in a game of tag
    int gone;                       // frames left fading away after you beat him, see 'ko'
    final Peer pub = new Peer();    // what the others see of him

    Stick(Room room, int slot) {
        this.room = room;
        this.rng = room.rng;
        this.slot = slot;
        SC = room.sc;
        BOXW = (int) Math.round(DW * SC);
        BOXH = (int) Math.round(DH * SC);
        CX = DCX * SC;
        FOOT = DFT * SC;
        GRAVITY = 0.85 * SC;
        SPEED   = 1.9  * SC;
        CLIMB   = 2.0  * SC;
        VMAX    = 26.0 * SC;
        REACH   = 14.0 * SC;
        MINWALL = 22.0 * SC;
        EDGE    = 6.0  * SC;
        HUG     = 7.0  * SC;
        STEPIN  = 10.0 * SC;
        NOTICE  = 120.0 * SC;
        WGRAV     = 0.9 * SC;
        FAR_OFF   = 300 * SC;
        // he drops in from the top of the screen
        int span = Math.max(1, (int) (room.workR - room.workL - 300 * SC));
        x = room.workL + 150 * SC + rng.nextInt(span);
        y = room.workT + 40 * SC;
    }

    static int sign(double v) { return v > 0 ? 1 : v < 0 ? -1 : 0; }
    static long round(double v) { return Math.round(v); }
    private int next(int lo, int hi) { return lo + rng.nextInt(hi - lo); }    // $RNG.Next(lo, hi)
    static boolean in(String s, String... set) { for (String k : set) if (k.equals(s)) return true; return false; }

    // ------------------------------------------------------------------ world
    // Rebuild the world, and carry him along with whatever he was holding on to,
    // so he rides a window (or a button scrolling past) instead of being left
    // in mid-air.
    void updateWorld() {
        Ledge old = ledge;
        Ledge ow  = wall;

        List<Ledge> list = new ArrayList<>(room.seen.length + 1);
        for (Ledge l : room.seen) if (!room.docked(l)) list.add(l);    // the keyboard is the ground, below
        list.add(room.ground());
        ledges = list.toArray(new Ledge[0]);

        if (state.equals("fall") || drag) return;

        if (state.equals("climb")) {
            Ledge m = null;
            if (ow != null) for (Ledge l : ledges) if (l.h == ow.h) { m = l; break; }
            if (m == null) { state = "fall"; vy = 0.0; wall = null; return; }
            x += dir > 0 ? m.l - ow.l : m.r - ow.r;
            wall = m;
            if (y < m.t || y > m.b) { state = "fall"; vy = 0.0; wall = null; }
            return;
        }

        if (old == null) { state = "fall"; return; }

        if (old.ground) {
            // the keyboard coming up lifts him with it; going away, it drops him
            // (mid-leap he is off it anyway, and 'leap' works out his height itself)
            Ledge g = room.ground();
            boolean leap = state.equals("leap");
            if (!leap && g.t > y + 2 * SC) { ledge = null; state = "fall"; vy = 0.0; return; }
            ledge = g;
            if (!leap) y = g.t;
            return;
        }

        Ledge match = null;
        for (Ledge l : ledges) if (l.h == old.h) { match = l; break; }
        if (match == null) { ledge = null; state = "fall"; vy = 0.0; return; }

        x += match.l - old.l;      // ride it
        y  = match.t;
        ledge = match;
        if (x < match.l || x > match.r) { ledge = null; state = "fall"; vy = 0.0; }
    }

    // A window edge directly in front of him, tall enough to be worth bothering with.
    Ledge findWall() {
        for (Ledge l : ledges) {
            if (l.ground) continue;
            double min = (l.btn || l.icon) ? 9 * SC : MINWALL;     // a button or icon is a low step up
            if (l.t > y - min) continue;            // too short
            if (l.b < y - 4 * SC) continue;         // ends above his feet
            if (dir > 0) {
                if (l.l >= x && l.l <= x + REACH) return l;
            } else {
                if (l.r <= x && l.r >= x - REACH) return l;
            }
        }
        return null;
    }

    // A button sitting inside the window he is standing on, close enough below to
    // drop down onto.
    Ledge findDropTarget(Ledge l) {
        for (Ledge b : ledges) {
            if (!b.btn) continue;
            if (b.t <= l.t + 12 * SC || b.t >= l.b) continue;
            if (x >= b.l + EDGE && x <= b.r - EDGE) return b;
        }
        return null;
    }

    // A window floating clear of the ground has no edge he can walk into, so he
    // jumps up and grabs its bottom corner instead, and climbs from there.
    Ledge findReach() {
        for (Ledge l : ledges) {
            if (l.ground || l.btn) continue;
            if (l.b >= y - 8 * SC) continue;        // not above him
            if (l.b < y - 240 * SC) continue;       // out of jumping range
            if (l.t > l.b - 24 * SC) continue;      // no side worth climbing
            if (dir > 0) {
                if (l.l >= x - REACH && l.l <= x + REACH) return l;
            } else {
                if (l.r <= x + REACH && l.r >= x - REACH) return l;
            }
        }
        return null;
    }

    void landOn(Ledge l) {
        ledge  = l;
        y      = l.t;
        vy     = 0.0;
        state  = "walk";
        wall   = null;
        ignore = 0;
        f.air  = "";
        if (f.on) return;                   // mid-fight he never stamps on buttons or icons
        if ((l.btn || l.icon) && rng.nextInt(3) == 0) {
            state = "press"; timer = 42; phase = 0.0;
        } else if (chase > 0) {
            state = "chase";                // he was on his way to you, carry on
        }
    }

    // how far your finger is, if one is down on any of his windows (1e9 if
    // not), and where it is across
    private double cursorX;
    double cursorDistance() {
        if (!room.hover) return 1e9;
        double dx = room.hoverX - x;
        double dy = room.hoverY - (y - 30 * SC);
        cursorX = room.hoverX;
        return Math.sqrt(dx * dx + dy * dy);
    }

    // A window edge anywhere nearby that he could climb, so he goes looking for
    // something to stand on instead of pacing the bottom of the screen all day.
    Double findClimb() {
        Double best = null;
        double bd = 700 * SC;
        for (Ledge l : ledges) {
            if (l.ground || l.btn) continue;
            if (l.t > y - MINWALL) continue;
            if (l.b < y - 4 * SC) continue;
            for (double e : new double[] { l.l, l.r }) {
                double d = Math.abs(e - x);
                if (d < bd && d > REACH) { bd = d; best = e; }
            }
        }
        return best;
    }

    // --------------------------------------------------------- other stickmen
    // Each of them publishes himself (see Peer), so they can see one another. A
    // meeting is a handshake done entirely through those: one of them sets
    // 'with' to the other and walks over, the other notices it is wanted, sets
    // 'with' back, and once both are close they play the act together.
    static final String[] ACTS = { "", "greet", "highfive", "chat", "dance", "tag" };
    static final int ST_DRAG = 15;

    static int stateCode(String s) {
        switch (s) {
            case "walk": return 1;  case "fall": return 2;   case "climb": return 3;  case "idle": return 4;
            case "sit": return 5;   case "wave": return 6;   case "knock": return 7;  case "push": return 8;
            case "press": return 9; case "chase": return 10; case "cheer": return 11; case "leap": return 12;
            case "meet": return 13; case "social": return 14;
            default: return 0;
        }
    }
    static int actTime(String a) {
        switch (a) { case "greet": return 60; case "highfive": return 40; case "chat": return 150; case "dance": return 80; default: return 24; }
    }
    static int actGap(String a) {     // how close they stand
        switch (a) { case "greet": return 34; case "highfive": return 24; case "chat": return 32; case "dance": return 30; default: return 22; }
    }
    static String socialPose(String a) {
        switch (a) { case "greet": return "wave"; case "highfive": return "hifive"; case "chat": return "chat"; case "dance": return "cheer"; default: return "knock"; }
    }
    static int actIndex(String a) {
        for (int i = 0; i < ACTS.length; i++) if (ACTS[i].equals(a)) return i;
        return -1;
    }

    void publish() {
        pub.slot  = slot;
        pub.x     = (int) round(x);
        pub.y     = (int) round(y);
        pub.dir   = dir;
        pub.state = drag ? ST_DRAG : stateCode(state);
        pub.with  = with;
        pub.act   = actIndex(act);
        pub.live  = true;
    }

    Peer getPeer(int s) {
        for (Peer p : peers) if (p.slot == s) return p;
        return null;
    }

    // free to be walked up to: pottering about and not already with someone
    static boolean testFree(Peer p) { return p.with < 0 && (p.state == 1 || p.state == 4 || p.state == 5); }

    void stopMeeting() {
        with    = -1;
        act     = "";
        waiting = false;
        social  = next(450, 1200);
        if (state.equals("meet") || state.equals("social")) state = "walk";
    }

    void startMeeting(Peer p, String a) {
        with    = p.slot;
        act     = a;
        state   = "meet";
        meetT   = 0;
        waiting = false;
        phase   = 0.0;
        if (p.x != (int) round(x)) dir = sign(p.x - x);
    }

    void stepFriends() {
        peers = room.others(this);
        if (social > 0) social--;

        // something else took him out of the meeting: a tap, a drag, a fall
        if (with >= 0 && !state.equals("meet") && !state.equals("social")) stopMeeting();
        if (peers.isEmpty()) return;
        if (with >= 0 || ledge == null) return;
        if (!in(state, "walk", "idle", "sit", "wave")) return;

        // somebody is on their way over to see him
        for (Peer p : peers) {
            if (p.with == slot && p.state == stateCode("meet") && Math.abs(p.y - y) < 8 * SC) {
                startMeeting(p, ACTS[Math.max(0, p.act)]);
                return;
            }
        }
        if (state.equals("wave")) return;

        Peer same = null; double sd = 1e9;      // nearest friend on the same ledge
        Peer far  = null; double fd = 1e9;      // nearest one anywhere else
        for (Peer p : peers) {
            double dx = p.x - x;
            double d  = Math.abs(dx);
            boolean level = Math.abs(p.y - y) < 6 * SC;

            // walking straight into each other: step back round instead of through
            if (level && state.equals("walk") && d < 16 * SC &&
                sign(dx) == dir && p.dir == -dir) dir = -dir;

            // one of them is cheering or waving: join in, facing them
            if (social <= 0 && tick % 10 == 0 && d < 300 * SC &&
                (p.state == stateCode("cheer") || p.state == stateCode("wave")) && rng.nextInt(3) == 0) {
                if (dx != 0) dir = sign(dx);
                state  = p.state == stateCode("cheer") ? "cheer" : "wave";
                timer  = 55; phase = 0.0; social = 400;
                return;
            }

            if (!testFree(p)) continue;
            if (level) { if (d < sd) { sd = d; same = p; } }
            else if (d < fd) { fd = d; far = p; }
        }

        // a friend stood about: look at them
        if (state.equals("idle") && same != null && sd < 260 * SC && same.x != (int) round(x)) {
            dir = sign(same.x - x);
        }

        if (social > 0 || tick % 15 != 0) return;

        // close by on the same ledge: go over and do something together
        if (same != null && sd < 280 * SC && rng.nextInt(3) == 0) {
            startMeeting(same, ACTS[next(1, ACTS.length)]);
            return;
        }
        // out of reach: a wave across the gap, which they will usually return
        if (far != null && fd < 420 * SC && rng.nextInt(6) == 0) {
            if (far.x != (int) round(x)) dir = sign(far.x - x);
            state = "wave"; timer = 60; phase = 0.0; social = 500;
        }
    }

    // ------------------------------------------------------------------ fight
    // Fight mode, ticked in the Convert to Symbol dialog: Animator vs. Animation,
    // with your pointer (the arrow) as the animator. He hunts it down, climbing
    // whatever is in the way, and throws punches, kicks and flying kicks at it;
    // a blow that lands pops a spark and knocks the pointer back a little. When
    // it is out of reach he conjures a Flash panel and throws that at it
    // instead, up to three in the air at once. The pointer has hits too, and
    // when they run out he breaks it and wins the round (see Pointer), until it
    // mends. Tap him to hit back - eight hits and he is out, and you have won:
    // he lies there seeing stars under a "K.O.!", fades away, and that copy of
    // him quits.
    //
    // It is all show. While he fights he never presses buttons or opens apps.
    static final class Level {
        final int hp, ptr;          // hits he can take, and hits the pointer can take
        final double pace;          // multiplies every wait between his attacks, throws and grabs
        final double reach, speed;  // multiply how far his blows reach, and how fast he closes in
        final int kick;             // hits a kick or flying kick takes off the pointer
        final int block;            // percent of the taps he sees coming that he blocks
        final boolean second;       // gets back up from his first knockout
        final int dodge, alert;     // percent chance he hops out of the way of a swipe this fast
        final int flying;           // panels in the air at once
        final double struggle;      // how hard you have to pull, design units, to get your pointer back
        final int inv;              // frames after a hit before he can be hit again
        Level(int hp, int ptr, double pace, double reach, double speed, int kick, int block, boolean second,
              int dodge, int alert, int flying, double struggle, int inv) {
            this.hp = hp; this.ptr = ptr; this.pace = pace; this.reach = reach; this.speed = speed;
            this.kick = kick; this.block = block; this.second = second; this.dodge = dodge; this.alert = alert;
            this.flying = flying; this.struggle = struggle; this.inv = inv;
        }
    }
    // Hard mode, ticked in the menu or the Convert to Symbol dialog: the same
    // fight, but he takes far more beating, blocks, gets back up from his first
    // knockout, attacks sooner and reaches further, runs faster, dodges more,
    // throws more at once, holds on to your pointer harder, and your pointer
    // breaks sooner.
    static final Level NORMAL = new Level(8, 10, 1.0, 1.0, 1.0, 1, 0, false, 33, 28, 3, 170, 12);
    static final Level HARD   = new Level(20, 6, 0.5, 1.25, 1.4, 2, 40, true, 67, 20, 5, 320, 18);
    Level tune = NORMAL;

    static final class Fight {
        boolean on;
        int hp = 8, max = 8;        // hits he can still take before he is knocked out
        boolean ko;                 // knocked out: he lies down as soon as he lands
        boolean second;             // he has already got back up from one knockout
        boolean intro;              // the first thing he does is square up to you
        int inv;                    // frames before he can be hit again
        int hurt;                   // frames left of the red flash
        int cool;                   // frames before his next attack
        int combo;                  // jab, cross, jab...
        String air = "";            // how he looks in the air: flykick, hurt, flip
        boolean hitDone;            // a flying kick lands once at most
        boolean gloat;              // taunt once the current blow is over
        double kx, ky; int kn;      // knock-back still owed to the pointer
        double kd = 0.62;           // how fast the knock-back dies away, per frame
        final Spark spark = new Spark();
        double px, py;              // the pointer last frame, to see you swipe at him
        int dodge;                  // frames before he will dodge again
        Panel fly;                  // the panel in his hands
        final List<Panel> flying = new ArrayList<>();   // the ones he has thrown, still in the air
        int throwCool;              // frames before he will throw another
        boolean far;                // the pointer is a long way off: time for throwing
        boolean grab;               // he has hold of your pointer
        int grabCool;               // frames before he will grab it again
        double gx, gy;              // where he last put the pointer
        double sx, sy;              // where it was when he grabbed it
        int run = 1;                // the way he is running off with it
        double struggle;            // how hard you have been pulling it back
    }
    final Fight f = new Fight();

    static final String[] FIGHT_STATES = { "hunt", "guard", "taunt", "punch", "kick", "ko", "heave", "hurl", "haul", "fling", "win", "shock" };
    static final int GONE_LEN = 50;     // frames he takes to fade away once you have beaten him
    static final int PUMP_LEN = 48;     // he punches the air this long over your broken pointer, then jumps for joy

    final double WGRAV;                 // panels fall a little faster than he does
    static final int HEAVE_LEN = 20;    // frames of wind-up before a panel flies
    final double FAR_OFF;               // the pointer further off than this: out come the panels

    static final int GRAB_HOLD   = 84;  // frames he runs about with your pointer before throwing it
    static final int GRAB_SNATCH = 8;   // the first of them, reaching out and taking it
    static final int FLING_LEN   = 14;  // the throw at the end
    static final int FLING_AT    = 5;   // the frame of the throw he lets go on

    final List<Panel> props = new ArrayList<>();
    static final int PROP_LINGER = 60;  // frames one stays about after it lands

    void setHard(boolean on) {
        hard = on;
        tune = hard ? HARD : NORMAL;
        // mid-fight, the bars change size but keep how full they were
        f.hp = Math.max(1, (int) Math.round(f.hp * tune.hp / (double) f.max)); f.max = tune.hp;
        Pointer p = room.ptr;
        if (!p.dead) p.hp = Math.max(1, (int) Math.round(p.hp * tune.ptr / (double) p.max));
        p.shown = p.shown * tune.ptr / p.max; p.max = tune.ptr;
    }

    void startFight() {
        Pointer p = room.ptr;
        p.show();
        f.on = true; f.max = tune.hp; f.hp = f.max; f.ko = false; f.second = false; f.intro = true;
        f.inv = 0; f.cool = (int) (20 * tune.pace); f.air = ""; f.px = p.x; f.py = p.y;
        f.fly = null; f.flying.clear(); f.throwCool = (int) (90 * tune.pace);    // fists first
        f.grab = false; f.grabCool = (int) (60 * tune.pace);
        p.max = tune.ptr; p.hp = p.max; p.shown = p.max;
        pending = "";                       // squaring up is his entrance now
        chase = 0; chasePeer = -1;
        if (with >= 0) stopMeeting();
    }

    void endFight() {
        f.on = false; f.ko = false; f.air = ""; f.kn = 0;
        f.fly = null; f.flying.clear();
        for (Panel pr : new ArrayList<>(props)) removeProp(pr);     // his panels just go
        releasePointer();
        if (in(state, FIGHT_STATES)) { state = "walk"; phase = 0.0; }
        // nobody left fighting: the pointer is whole again at once, and goes
        if (!room.anyFighting()) room.ptr.hide();
    }

    // his fist or foot, or a panel he threw, found the pointer: it is knocked
    // (kx, ky) pixels the first frame, and a little less each frame after, and
    // loses dmg of its hits
    void landBlow() { landBlow(dir * 14 * SC, -5 * SC, 1); }
    void landBlow(double kx, double ky, int dmg) {
        Pointer p = room.ptr;
        if (p.dead) return;                         // nothing there to hit
        if (p.hurt(dmg, kx, ky)) return;            // that one broke it
        f.spark.pop(p.x, p.y, rng);
        p.knock();                                  // out of your finger, if you had hold of it
        f.kx = kx; f.ky = ky; f.kn = 6; f.kd = 0.62;
        if (rng.nextInt(4) == 0) f.gloat = true;
    }

    // ------------------------------------------------------------- throwing
    // A throw is due. On Windows he goes and gets one of your windows; on a
    // phone nobody's windows can be moved, so a panel of his own pops up in
    // his hands instead.
    boolean tryThrow() {
        if (!room.throwOk || f.throwCool > 0 || f.fly != null || f.flying.size() >= tune.flying) return false;
        return ledge != null && conjureProp();
    }

    // take hold of it
    boolean startHeave(Panel pr, int d) {
        pr.hx = pr.x; pr.hy = pr.y;
        pr.vx = 0.0; pr.vy = 0.0; pr.t = 0;
        pr.len = HEAVE_LEN; pr.hit = false;
        f.fly = pr;
        dir = d;
        state = "heave"; timer = pr.len; phase = 0.0;
        return true;
    }

    // end of the wind-up: it goes, on an arc that meets the pointer where it is now
    void launchPanel() {
        Panel fl = f.fly;
        if (fl == null) { state = "guard"; return; }
        Pointer p = room.ptr;
        double dx = p.x - (fl.x + fl.w / 2.0);
        double dy = p.y - (fl.y + fl.h / 2.0);
        double n  = Math.max(10.0, Math.min(24.0, Math.sqrt(dx * dx + dy * dy) / (26 * SC)));
        fl.vx = dx / n;
        fl.vy = dy / n - 0.5 * WGRAV * n;
        fl.t  = 0;
        f.flying.add(fl);
        f.fly = null;
        if (round(p.x) != round(x)) dir = sign(p.x - x);
        state = "hurl"; timer = 14; phase = 0.0;
        f.throwCool = (int) (next(120, 240) * tune.pace);   // runs down four times as fast with the pointer far off
        f.cool = 16;
    }

    // every frame of a fight: the panel in his hands, and every one in the air
    void stepThrow() {
        if (f.fly == null && f.flying.isEmpty()) return;
        if (f.fly != null) stepHeld();
        for (Panel fl : new ArrayList<>(f.flying)) {
            if (!stepFlight(fl)) f.flying.remove(fl);
        }
    }

    // the wind-up, before a panel flies: it rattles harder and harder, dragged
    // back toward him
    void stepHeld() {
        Panel fl = f.fly;
        // knocked out of his hands, or gone
        if (!state.equals("heave") || !props.contains(fl)) { f.fly = null; return; }
        double j = SC * (tick % 2 == 0 ? 1 : -1);
        double t = 1.0 - timer / (double) fl.len;
        fl.x = fl.hx - dir * 10 * SC * t * t + (1.0 + 3.0 * t) * j;
        fl.y = fl.hy - 4 * SC * t;
    }

    // one frame of a thrown panel; false once it has come to rest
    boolean stepFlight(Panel fl) {
        if (!props.contains(fl)) return false;
        fl.t++;
        fl.vy += WGRAV;
        double nx = fl.x + fl.vx;
        double ny = fl.y + fl.vy;
        // the edges of the screen: it bounces off them, it never leaves
        double aL = room.workL, aT = room.workT, aR = room.workR, aB = room.floor();
        if (nx < aL) { nx = aL; fl.vx = -fl.vx * 0.5; }
        else if (nx + fl.w > aR) { nx = Math.max(aL, aR - fl.w); fl.vx = -fl.vx * 0.5; }
        if (ny < aT) { ny = aT; fl.vy = Math.abs(fl.vy) * 0.3; }
        boolean rest = false;
        if (ny + fl.h > aB) {
            ny = Math.max(aT, aB - fl.h);
            fl.vy = fl.vy > 4 * SC ? -fl.vy * 0.35 : 0.0;
            fl.vx *= 0.75;
            rest = fl.vy == 0.0 && Math.abs(fl.vx) < 0.8 * SC;
        }
        fl.x = nx; fl.y = ny;

        // it caught the pointer: a spark, and the pointer is knocked the way it flew
        if (!fl.hit) {
            Pointer p = room.ptr;
            if (p.x >= nx && p.x <= nx + fl.w && p.y >= ny && p.y <= ny + fl.h) {
                fl.hit = true;
                double sp = Math.max(1.0, Math.sqrt(fl.vx * fl.vx + fl.vy * fl.vy));
                landBlow(fl.vx / sp * 18 * SC, fl.vy / sp * 18 * SC, 2);
                fl.vx *= 0.5;
            }
        }
        return !(rest || fl.t > 90);
    }

    // a panel appears right in front of him, on the side the pointer is on,
    // with a spark, and he takes hold of it
    boolean conjureProp() {
        if (props.size() >= tune.flying) return false;
        Pointer p = room.ptr;
        double w = (int) (Panel.W * SC), h = (int) (Panel.H * SC);
        double aL = room.workL, aT = room.workT, aR = room.workR, aB = room.floor();
        int d = p.x >= x ? 1 : -1;
        double px = d > 0 ? x + 14 * SC : x - 14 * SC - w;
        if (px < aL || px + w > aR) {
            d = -d;                                         // no room that side: the other
            px = d > 0 ? x + 14 * SC : x - 14 * SC - w;
        }
        px = Math.max(aL, Math.min(aR - w, px));
        double py = Math.max(aT, Math.min(aB - h, y - 34 * SC - h / 2));
        Panel pr = new Panel(rng.nextInt(Panel.TITLES.length), px, py, w, h);
        pr.life = PROP_LINGER;
        props.add(pr);
        f.spark.pop(px + w / 2, py + h / 2, rng);
        return startHeave(pr, d);
    }

    void removeProp(Panel pr) {
        props.remove(pr);
        if (f.fly == pr) f.fly = null;
        f.flying.remove(pr);
    }

    // every frame: a panel in his hands or in the air stays; one that has
    // landed counts down and goes
    void stepProps() {
        for (Panel pr : new ArrayList<>(props)) {
            boolean busy = f.on && (f.fly == pr || f.flying.contains(pr));
            if (busy) { pr.life = PROP_LINGER; continue; }
            if (--pr.life <= 0) removeProp(pr);
        }
    }

    // ------------------------------------------------------ grabbing the pointer
    // In reach, now and then he grabs your pointer instead of hitting it, runs off
    // dragging it behind him, and throws it. Put a finger on it and wiggle hard
    // enough and it comes free; tap it, or tap him, and he lets go.
    void startGrab() {
        Pointer p = room.ptr;
        f.grab = true; f.struggle = 0.0; f.kn = 0;
        f.sx = p.x; f.sy = p.y; f.gx = p.x; f.gy = p.y;
        p.pullX = 0; p.pullY = 0;
        // he runs off with it whichever way there is more room
        Ledge l = ledge;
        f.run = (l != null && (l.r - x) < (x - l.l)) ? -1 : 1;
        state = "haul"; timer = GRAB_HOLD; phase = 0.0;
    }

    void releasePointer() {
        if (!f.grab) return;
        f.grab = false; f.struggle = 0.0;
        f.grabCool = (int) (next(150, 270) * tune.pace);
    }

    // where his holding hand is, in design units: reaching out for your pointer,
    // trailing it behind him as he runs, then swinging it up over his head and
    // out in front to throw it. The arm is 15 long, from his shoulder.
    double[] grabHand() {
        double th;
        if (state.equals("fling")) {
            double e = Math.min(1.0, (FLING_LEN - timer) / (double) (FLING_LEN - FLING_AT));
            th = 200.0 - 170.0 * e;
        } else if (GRAB_HOLD - timer < GRAB_SNATCH) {
            th = 10.0;
        } else {
            th = 200.0;
        }
        th *= Math.PI / 180.0;
        return new double[] { 22.0 + dir * (1.0 + 15.0 * Math.cos(th)), 27.0 - 15.0 * Math.sin(th) };
    }

    // every frame he has it: it stays in his hand, unless you pull it free
    void stepGrab() {
        if (!f.on || drag || !(state.equals("haul") || state.equals("fling"))) { releasePointer(); return; }
        Pointer p = room.ptr;
        // anything your finger dragged at it since last frame is you, pulling against him
        double ux = p.pullX, uy = p.pullY;
        p.pullX = 0; p.pullY = 0;
        f.struggle = f.struggle * 0.85 + Math.sqrt(ux * ux + uy * uy);
        if (f.struggle > tune.struggle * SC) {
            // you yanked it out of his hand, and he stumbles
            releasePointer();
            p.yanked();
            state = "fall"; f.air = "hurt"; wall = null;
            vy = -5.0 * SC; vx = -dir * 3.0 * SC;
            return;
        }
        double[] hd = grabHand();
        double hx = x + (hd[0] - DCX) * SC;
        double hy = y + (hd[1] - DFT) * SC;
        double k = (GRAB_HOLD - timer) / (double) GRAB_SNATCH;
        if (state.equals("haul") && k < 1.0) {
            // still snatching it: it is pulled from where it was into his hand
            hx = f.sx + (hx - f.sx) * k; hy = f.sy + (hy - f.sy) * k;
        }
        p.move(hx, hy);
        f.gx = p.x; f.gy = p.y;
    }

    // you tapped your pointer while he had it: he lets go, and it counts as a hit
    void gripTap(float cx, float cy) {
        releasePointer();
        if (f.on) hitHim(cx, cy);
    }

    // the end of the throw: he lets go and your pointer sails off the way it went
    void flingPointer() {
        releasePointer();
        Pointer p = room.ptr;
        if (p.hurt(2, dir * 44 * SC, -22 * SC)) return;     // it breaks as it leaves his hand
        p.knock();
        f.kx = dir * 44 * SC; f.ky = -22 * SC; f.kn = 12; f.kd = 0.8;
    }

    // you tapped him: he is thrown back, still facing you. On his feet and
    // facing you, he often sees it coming, blocks it, and hits straight back.
    void hitHim(double cx, double cy) {
        if (f.inv > 0 || state.equals("ko")) return;
        f.spark.pop(cx, cy, rng);
        boolean facing = round(cx) == round(x) || sign(cx - x) == dir;
        if (facing && in(state, "guard", "taunt", "hunt", "punch", "kick") && rng.nextInt(100) < tune.block) {
            f.inv = 8; f.cool = 0;
            state = "guard"; phase = 0.0;
            return;
        }
        f.hp--; f.inv = tune.inv; f.hurt = 12;
        if (f.hp <= 0) f.ko = true;
        int away = cx > x ? -1 : 1;
        dir   = -away;
        state = "fall"; f.air = "hurt";
        vy    = -7.0 * SC;
        vx    = away * 5.0 * SC;
        wall  = null;
    }

    void jumpKick(double dx, double dy) {
        // rise just far enough for his foot to meet the pointer at the top
        double h = Math.min(240 * SC, Math.max(40 * SC, -dy - 6 * SC));
        vy = -Math.sqrt(2 * GRAVITY * h);
        vx = Math.max(-9 * SC, Math.min(9 * SC, dx / (-vy / GRAVITY)));
        if (dx != 0) dir = sign(dx);
        state = "fall"; f.air = "flykick"; f.hitDone = false; phase = 0.0;
        f.cool = 10;
    }

    // how solid he is: fading away once you have beaten him
    float alpha() {
        return gone > 0 ? gone / (float) GONE_LEN : 1f;
    }

    // every frame of a fight, before his state moves him
    void stepFightFrame() {
        if (f.inv > 0)   f.inv--;
        if (f.hurt > 0)  f.hurt--;
        if (f.cool > 0)  f.cool--;
        if (f.dodge > 0) f.dodge--;
        stepThrow();
        Pointer p = room.ptr;

        // the pointer sliding away from a blow, a little less each frame
        if (f.kn > 0) {
            f.kn--;
            if (p.held || p.dead) f.kn = 0;
            else {
                p.move((int) round(p.x + f.kx), (int) round(p.y + f.ky));
                f.kx *= f.kd; f.ky *= f.kd;
            }
        }

        double swipe = Math.sqrt((p.x - f.px) * (p.x - f.px) + (p.y - f.py) * (p.y - f.py));
        f.px = p.x; f.py = p.y;

        // the pointer a long way off: out come the panels, one after another
        double fdx = p.x - x, fdy = p.y - (y - 34 * SC);
        f.far = (fdx * fdx + fdy * fdy) > FAR_OFF * FAR_OFF || fdy <= -250 * SC;
        if (f.throwCool > 0) f.throwCool -= f.far ? 4 : 1;
        if (f.grabCool > 0) f.grabCool--;

        // a flying kick: does his foot find the pointer on the way up?
        if (state.equals("fall") && f.air.equals("flykick") && !f.hitDone) {
            double fx = x + dir * 19 * SC - p.x;
            double fy = y - 28 * SC - p.y;
            double rr = 26 * SC * tune.reach;
            if (fx * fx + fy * fy < rr * rr) {
                f.hitDone = true;
                landBlow(dir * 14 * SC, -5 * SC, tune.kick);
            }
        }

        // anything he was doing on his own gives way to the fight
        if (in(state, "walk", "idle", "sit", "wave", "cheer", "chase", "knock", "push", "press", "meet", "social")) {
            wall = null; phase = 0.0;
            if (f.ko) {
                state = "ko"; timer = 160;
                if (!tune.second || f.second) koT = 0;      // down for good: up goes "K.O.!"
            }
            else if (f.intro) { f.intro = false; state = "taunt"; timer = 50; }
            else              { state = "guard"; }
        }

        // the pointer lies in pieces: he celebrates, and when it starts pulling
        // itself back together he jumps
        if (p.dead) {
            if (p.mend && in(state, "guard", "hunt", "taunt", "hurl", "win")) {
                state = "shock"; timer = 0; phase = 0.0;
            } else if (!p.mend && in(state, "guard", "hunt", "taunt", "hurl")) {
                state = "win"; timer = 0; phase = 0.0;
            }
            if (in(state, "win", "shock") && round(p.bx) != round(x)) dir = sign(p.bx - x);
        }

        // you swiped at him: now and then he hops back out of the way
        if (in(state, "guard", "hunt", "taunt") && f.dodge <= 0 && swipe > tune.alert * SC) {
            double dx = p.x - x, dy = p.y - (y - 34 * SC);
            double rr = 100 * SC * tune.reach;
            if (dx * dx + dy * dy < rr * rr) {
                f.dodge = (int) (40 * tune.pace);
                if (rng.nextInt(100) < tune.dodge) {
                    if (dx != 0) dir = sign(dx);
                    state = "fall"; f.air = "flip";
                    vy = -7.5 * SC;
                    vx = -dir * 4.5 * SC;
                }
            }
        }
    }

    // squared up to the pointer: attack it in reach, go after it out of reach
    void stepGuard() {
        Ledge l = ledge;
        if (l == null) { state = "fall"; return; }
        Pointer p = room.ptr;
        double dx = p.x - x;
        double dy = p.y - (y - 34 * SC);        // from his chest
        double ax = Math.abs(dx);
        if (ax > 2 * SC) dir = sign(dx);

        if (state.equals("taunt")) {
            phase += 0.25;
            if (--timer > 0) return;
            state = "guard";
        }
        phase += 0.20;
        if (f.cool > 0) return;

        if (ax < 30 * SC * tune.reach && dy > -44 * SC && dy < 24 * SC) {
            // in reach: now and then he grabs it and runs off with it
            if (room.grabPtr && f.grabCool <= 0 && !p.held && !p.dead && rng.nextInt(2) == 0) {
                startGrab(); return;
            }
            // otherwise jab, cross, and a kick for anything low or now and then
            state = (dy > 10 * SC || rng.nextInt(10) >= 7) ? "kick" : "punch";
            timer = state.equals("punch") ? 14 : 20;
            phase = 0.0;
        } else if (ax < 110 * SC && dy <= -44 * SC && dy > -250 * SC) {
            jumpKick(dx, dy);                   // above him, but not by much
        } else if (f.far && tryThrow()) {
            // a long way off, whichever way: a panel thrown at it
        } else if (ax < 110 * SC && dy <= -250 * SC) {
            state = "taunt"; timer = 60; phase = 0.0;   // well out of reach: 'come on, then'
        } else if (ax >= 80 * SC) {
            state = "hunt"; phase = 0.0;
        } else if (ax >= 30 * SC) {
            // shuffle in with his fists up, never off the edge
            double v = SPEED * 0.7 * tune.speed;
            x = Math.max(l.l + EDGE, Math.min(l.r - EDGE, x + dir * v));
        }
    }

    // a punch or kick: the blow lands, or misses, at full stretch
    void stepStrike() {
        phase += 0.2;
        int len = state.equals("punch") ? 14 : 20;
        timer--;
        if (timer == len / 2) {
            Pointer p = room.ptr;
            double hx = x + dir * 19 * SC - p.x;
            double hy = y - (state.equals("punch") ? 35 : 28) * SC - p.y;
            double rr = 28 * SC * tune.reach;
            if (hx * hx + hy * hy < rr * rr) {
                landBlow(dir * 14 * SC, -5 * SC, state.equals("kick") ? tune.kick : 1);
            }
        }
        if (timer <= 0) {
            f.combo++;
            f.cool  = (int) (next(5, 16) * tune.pace);
            phase = 0.0;
            if (f.gloat) { f.gloat = false; state = "taunt"; timer = 45; }
            else         { state = "guard"; }
        }
    }

    // running at the pointer, climbing or leaping at whatever is in the way
    void stepHunt() {
        Ledge l = ledge;
        if (l == null) { state = "fall"; return; }
        Pointer p = room.ptr;
        double dx = p.x - x;
        double dy = p.y - (y - 34 * SC);
        double ax = Math.abs(dx);
        if (ax < 60 * SC || (ax < 110 * SC && dy < -44 * SC)) {
            state = "guard"; return;            // close enough to fight
        }
        phase += 0.40;
        dir = sign(dx);

        // a throw is due, with the pointer far off: a panel of his own
        if (tick % 4 == 0 && f.far && tryThrow()) return;

        Ledge w = findWall();
        if (w != null) {
            wall  = w;
            state = "climb";
            x     = dir > 0 ? w.l - HUG : w.r + HUG;
            phase = 0.0;
            return;
        }
        if (dy < -44 * SC) {                    // it is up there: jump for a window corner
            Ledge up = findReach();
            if (up != null) {
                wall  = up;
                state = "leap";
                timer = 18;
                ly0   = y;
                phase = 0.0;
                x     = dir > 0 ? up.l - HUG : up.r + HUG;
                return;
            }
        }

        x += dir * SPEED * 2.2 * tune.speed;
        // he jumps off an edge to get at it; the floor's edge stops him
        if (x < l.l + EDGE) {
            if (l.ground) { x = l.l + EDGE; state = "taunt"; timer = 40; }
            else { state = "fall"; vx = -2.4 * SC; vy = -3.0 * SC; }
        } else if (x > l.r - EDGE) {
            if (l.ground) { x = l.r - EDGE; state = "taunt"; timer = 40; }
            else { state = "fall"; vx = 2.4 * SC; vy = -3.0 * SC; }
        }
    }

    // --------------------------------------------------------------- K.O.
    // Knock him out for good and "K.O.!" is typed above him the way the animator
    // would with Flash's Text tool (drawn by Art.koText): a letter at a time,
    // the caret blinking at its end, then left selected, in Flash blue, until it
    // fades away with him.
    static final String KO_TEXT = "K.O.!";
    static final int KO_WAIT = 10;      // frames after he lands before the first letter
    static final int KO_KEY  = 4;       // frames per letter
    static final int KO_EDIT = 18;      // frames the finished text is still being edited
    int koT = -1;                       // frames since it went up, or -1 while it is not up

    int koLetters() { return koT < KO_WAIT ? 0 : Math.min(KO_TEXT.length(), (koT - KO_WAIT) / KO_KEY + 1); }
    private int koLast() { return KO_WAIT + (KO_TEXT.length() - 1) * KO_KEY; }     // the frame the last letter goes in
    boolean koSelected() { return koT >= koLast() + KO_EDIT; }
    boolean koCaret() { return !koSelected() && (koT < koLast() || ((koT - koLast()) / 8) % 2 == 0); }  // steady while typing, then blinking

    // once a frame, after he has moved: the spark fades, the K.O. types on.
    // If the fight ends some other way while he is still down, it goes.
    void stepFx() {
        f.spark.step();
        if (koT >= 0) {
            if (gone <= 0 && !(f.on && state.equals("ko"))) koT = -1;
            else koT++;
        }
    }

    // ---------------------------------------------------------------- physics
    void stepPhysics() {
        tick++;
        if (tick % 5 == 0) updateWorld();
        if (!props.isEmpty()) stepProps();
        // beaten for good: he lies there seeing stars while he fades away
        if (gone > 0) { phase += 0.15; return; }
        if (cool > 0) cool--;
        if (chase > 0) chase--;

        if (drag) {
            lastX = x;
            x = fingerX - grabX + CX;
            y = fingerY - grabY + FOOT;
            dragged += Math.abs(x - lastX);
            phase += 0.2;
            return;
        }

        if (f.on) stepFightFrame(); else stepFriends();

        // A figure's move waits here until he is settled enough to perform it:
        // anything set while he is in the air would be thrown away by the fall.
        if (!pending.isEmpty()) {
            if (--pendTTL <= 0) {
                pending = "";
            } else if (!drag && ledge != null && !in(state, "climb", "leap", "fall", "knock", "push")) {
                String a = pending;
                pending = "";
                doEggAct(a);
            }
        }

        switch (state) {

            case "hunt":  stepHunt(); return;
            case "guard": stepGuard(); return;
            case "taunt": stepGuard(); return;
            case "punch": stepStrike(); return;
            case "kick":  stepStrike(); return;
            case "heave": {
                // wrenching it loose, see stepHeld; then it flies
                phase += 0.5;
                if (f.fly == null || ledge == null) { f.fly = null; state = "guard"; return; }
                if (--timer <= 0) launchPanel();
                break;
            }
            case "hurl": {
                phase += 0.2;
                if (--timer <= 0) { state = "guard"; phase = 0.0; }
                break;
            }
            case "haul": {
                // off he goes with your pointer, see stepGrab, turning at the ends
                phase += 0.42;
                Ledge l = ledge;
                if (l == null) { state = "fall"; vy = 0.0; }
                else if (GRAB_HOLD - timer >= GRAB_SNATCH) {
                    dir = f.run;
                    x += dir * SPEED * 1.8;
                    if (x < l.l + EDGE)      { x = l.l + EDGE; f.run = 1; }
                    else if (x > l.r - EDGE) { x = l.r - EDGE; f.run = -1; }
                }
                if (state.equals("haul") && --timer <= 0) { state = "fling"; timer = FLING_LEN; phase = 0.0; }
                break;
            }
            case "fling": {
                phase += 0.2;
                if (timer == FLING_AT) flingPointer();
                if (--timer <= 0) { state = "guard"; phase = 0.0; }
                break;
            }
            case "ko": {
                phase += 0.15;
                if (--timer <= 0) {
                    if (tune.second && !f.second) {
                        // hard mode: the first time, he gets back up with half his hits
                        f.second = true; f.ko = false;
                        f.hp = (int) Math.ceil(f.max / 2.0);
                        f.cool = 0;
                        state = "taunt"; timer = 50; phase = 0.0;
                    } else {
                        // you won: he stays down, fades away, and this copy of him quits
                        endFight();
                        state = "ko"; gone = GONE_LEN;
                    }
                }
                break;
            }
            case "win": {
                // he broke your pointer: punching the air, then jumping for joy
                phase += 0.30;
                timer++;
                if (!room.ptr.dead) { state = "guard"; phase = 0.0; }
                break;
            }
            case "shock": {
                // ...and it is putting itself back together
                phase += 0.30;
                timer++;
                if (!room.ptr.dead) { state = "taunt"; timer = 50; phase = 0.0; }
                break;
            }

            case "walk": {
                phase += 0.26;
                Ledge l = ledge;
                if (l == null) { state = "fall"; return; }

                // something is in front of him
                Ledge w = findWall();
                if (w != null) {
                    if (w.btn || w.icon) {              // a button or an icon is just a step up
                        wall  = w;
                        state = "climb";
                        x     = dir > 0 ? w.l - HUG : w.r + HUG;
                        phase = 0.0;
                        return;
                    }
                    int roll = rng.nextInt(100);
                    if (roll < 80) {
                        wall  = w;
                        state = "climb";
                        x     = dir > 0 ? w.l - HUG : w.r + HUG;
                        phase = 0.0;
                    } else if (roll < 90) {
                        wall = w; state = "knock"; timer = 54; phase = 0.0;
                    } else if (roll < 98 && !w.max) {
                        // he leans into it with all he has; on a phone it never budges
                        wall = w; state = "push"; timer = 60; phase = 0.0;
                    } else {
                        dir = -dir;
                    }
                    return;
                }

                // your finger came near
                double cd = cursorDistance();
                if (cool <= 0 && cd < NOTICE) {
                    if (cursorX != x) dir = sign(cursorX - x);
                    state = "wave"; timer = 60; cool = 200; phase = 0.0;
                    return;
                }

                // a window hanging overhead: jump for the corner
                Ledge up = findReach();
                if (up != null && rng.nextInt(100) < 75) {
                    wall  = up;
                    state = "leap";
                    timer = 18;
                    ly0   = y;
                    phase = 0.0;
                    x     = dir > 0 ? up.l - HUG : up.r + HUG;
                    return;
                }

                // nothing to stand on down here: go and find a window to get onto
                if (l.ground && tick % 40 == 0) {
                    Double e = findClimb();
                    if (e != null) dir = sign(e - x);
                }

                // drop off the top of a window down onto the buttons inside it
                if (!l.ground && !l.btn && rng.nextInt(45) == 0) {
                    if (findDropTarget(l) != null) {
                        ignore = l.h;
                        state  = "fall";
                        vy     = 0.0;
                        vx     = 0.0;
                        return;
                    }
                }

                x += dir * SPEED;

                // at the end of a ledge he almost always stays on it, and now and
                // then sits down on the edge instead of turning round
                if (x < l.l + EDGE) {
                    if (l.ground || rng.nextInt(100) < 96) {
                        x = l.l + EDGE;
                        if (!l.ground && !l.btn && rng.nextInt(4) == 0) {
                            state = "sit"; timer = next(90, 260); phase = 0.0;
                        } else dir = 1;
                    } else {
                        state = "fall"; vx = -1.2 * SC; vy = 0.0;
                    }
                } else if (x > l.r - EDGE) {
                    if (l.ground || rng.nextInt(100) < 96) {
                        x = l.r - EDGE;
                        if (!l.ground && !l.btn && rng.nextInt(4) == 0) {
                            state = "sit"; timer = next(90, 260); phase = 0.0;
                        } else dir = -1;
                    } else {
                        state = "fall"; vx = 1.2 * SC; vy = 0.0;
                    }
                }

                if (rng.nextInt(260) == 0) { state = "idle"; timer = 40; }
                break;
            }

            case "chase": {
                phase += 0.36;
                Ledge l = ledge;
                if (l == null) { state = "fall"; return; }

                // playing tag: the target is a friend, and they keep moving
                if (chasePeer >= 0) {
                    Peer p = getPeer(chasePeer);
                    if (p == null) chasePeer = -1; else { tx = p.x; ty = p.y; }
                }

                double gap = tx - x;
                if (Math.abs(gap) > 4 * SC) dir = sign(gap);

                // got there: a hop and a cheer
                if (Math.abs(gap) < 16 * SC && Math.abs(ty - y) < 90 * SC) {
                    state = "cheer"; timer = 60; phase = 0.0; cool = 120; chasePeer = -1;
                    return;
                }
                if (chase <= 0) { state = "walk"; chasePeer = -1; return; }

                // anything in the way gets climbed, no dithering about it
                Ledge w = findWall();
                if (w != null) {
                    wall  = w;
                    state = "climb";
                    x     = dir > 0 ? w.l - HUG : w.r + HUG;
                    phase = 0.0;
                    return;
                }

                Ledge up = findReach();
                if (up != null) {
                    wall  = up;
                    state = "leap";
                    timer = 18;
                    ly0   = y;
                    phase = 0.0;
                    x     = dir > 0 ? up.l - HUG : up.r + HUG;
                    return;
                }

                x += dir * SPEED * 1.9;

                // he will run off an edge to get to you
                if (x < l.l + EDGE) {
                    if (l.ground) { x = l.l + EDGE; dir = 1; }
                    else { state = "fall"; vx = -1.6 * SC; vy = 0.0; }
                } else if (x > l.r - EDGE) {
                    if (l.ground) { x = l.r - EDGE; dir = -1; }
                    else { state = "fall"; vx = 1.6 * SC; vy = 0.0; }
                }
                break;
            }

            case "cheer": {
                phase += 0.30;
                if (--timer <= 0) state = "walk";
                break;
            }

            case "meet": {
                Ledge l = ledge;
                Peer p = getPeer(with);
                if (l == null || p == null || Math.abs(p.y - y) > 8 * SC || ++meetT > 240) {
                    stopMeeting(); return;
                }
                boolean answered = p.with == slot;
                if (!answered && meetT > 30) { stopMeeting(); return; }   // busy with someone else
                // if both asked at once, the lower slot's idea wins
                if (answered && p.slot < slot && p.act > 0) act = ACTS[p.act];

                double gap = p.x - x;
                if (Math.abs(gap) > 1) dir = sign(gap);
                if (Math.abs(gap) > actGap(act) * SC) {
                    if (findWall() != null) { stopMeeting(); return; }   // a window in the way
                    waiting = false;
                    phase  += 0.26;
                    x      += dir * SPEED;
                    if (x < l.l + EDGE) { x = l.l + EDGE; waiting = true; }
                    if (x > l.r - EDGE) { x = l.r - EDGE; waiting = true; }
                } else {
                    waiting = true;
                    phase  += 0.12;
                    if (answered && (p.state == stateCode("meet") || p.state == stateCode("social"))) {
                        state = "social"; timer = actTime(act); phase = 0.0;
                    }
                }
                break;
            }

            case "social": {
                Peer p = getPeer(with);
                // they quit, or finished and wandered off a moment before him
                if (p == null || (p.with != slot && timer > 10)) { stopMeeting(); return; }
                if (p.x != (int) round(x)) dir = sign(p.x - x);
                phase += act.equals("chat") ? 0.14 : act.equals("greet") ? 0.34 : 0.30;
                if (--timer <= 0) {
                    String a = act; int who = with;
                    stopMeeting();
                    if (a.equals("tag")) {
                        // the lower slot is 'it' and runs for it, the other gives chase
                        if (slot < who) {
                            tx = x - dir * 600 * SC; ty = y; chase = 150;
                        } else {
                            chasePeer = who; tx = p.x; ty = p.y; chase = 260;
                        }
                        dir = sign(tx - x);
                        state = "chase"; phase = 0.0;
                    } else {
                        dir = -dir;         // and off they go their separate ways
                    }
                }
                break;
            }

            case "leap": {
                phase += 0.30;
                Ledge w = wall;
                if (w == null) { state = "fall"; vy = 0.0; return; }
                timer--;
                double t = 1.0 - (timer / 18.0);
                y = ly0 + (w.b - ly0) * Math.pow(t, 0.55);     // fast off the mark, easing into the grab
                x = dir > 0 ? w.l - HUG : w.r + HUG;
                if (timer <= 0) { y = w.b; state = "climb"; phase = 0.0; }
                break;
            }

            case "idle": {
                phase += 0.12;
                if (--timer <= 0) {
                    state = "walk";
                    if (rng.nextInt(2) == 0) dir = -dir;
                }
                break;
            }

            case "sit": {
                phase += 0.14;
                // he looks at your finger while he sits
                double cd = cursorDistance();
                if (cd < NOTICE && cursorX != x) dir = sign(cursorX - x);
                if (--timer <= 0) { state = "walk"; dir = -dir; }
                break;
            }

            case "wave": {
                phase += 0.34;
                if (--timer <= 0) state = "walk";
                break;
            }

            case "knock": {
                // a rap on the glass (on Windows the window rattles back)
                phase += 0.30;
                if (wall == null) { state = "walk"; return; }
                if (--timer <= 0) { state = "walk"; dir = -dir; wall = null; }
                break;
            }

            case "push": {
                phase += 0.18;
                Ledge w = wall;
                if (w == null || w.max) { state = "walk"; wall = null; return; }
                if (--timer <= 0) {
                    state = "walk";
                    wall = null;
                    if (rng.nextInt(2) == 0) dir = -dir;
                }
                break;
            }

            case "press": {
                phase += 0.16;
                Ledge l = ledge;
                if (l == null || !(l.btn || l.icon)) { state = "walk"; return; }
                // he crouches, then stamps on it halfway through
                if (timer == 22 && room.hands != null) {
                    if (l.icon) {
                        // jumping on an app icon opens it, but not more than once in a while
                        if (room.open && (room.frame - room.lastOpen) > OPEN_GAP) {
                            if (room.hands.openApp(l.name)) room.lastOpen = room.frame;
                        }
                    } else if (room.click) {
                        room.hands.press(l);
                    }
                }
                if (--timer <= 0) {
                    state = "walk";
                    if (rng.nextInt(2) == 0) dir = -dir;
                }
                break;
            }

            case "climb": {
                phase += 0.30;
                Ledge w = wall;
                if (w == null) { state = "fall"; return; }
                x = dir > 0 ? w.l - HUG : w.r + HUG;
                y -= CLIMB;
                if (y <= w.t) {
                    landOn(w);
                    x = dir > 0 ? w.l + STEPIN : w.r - STEPIN;
                }
                break;
            }

            case "fall": {
                double prev = y;
                vy = Math.min(vy + GRAVITY, VMAX);
                y += vy;
                x += vx;
                vx *= 0.985;
                phase += 0.2;

                for (Ledge l : ledges) {
                    if (ignore != 0 && l.h == ignore) continue;
                    if (x >= l.l + 5 * SC && x <= l.r - 5 * SC &&
                        prev <= l.t + SC && y >= l.t) {
                        landOn(l);
                        break;
                    }
                }

                if (state.equals("fall") && y > room.scrB + 120 * SC) {
                    int span = Math.max(1, (int) (room.workR - room.workL - 300 * SC));
                    x  = room.workL + 150 * SC + rng.nextInt(span);
                    y  = room.workT + 10 * SC;
                    vy = 0.0; vx = 0.0;
                }
                break;
            }
        }

        if (x < room.workL + 8 * SC) { x = room.workL + 8 * SC; dir = 1; }
        if (x > room.workR - 8 * SC) { x = room.workR - 8 * SC; dir = -1; }
    }

    // ------------------------------------------------------------ your finger
    // a finger came down on him: pick him up (and in a fight, that is a hit)
    void touchDown(float fx, float fy) {
        if (gone > 0) return;               // no picking him up as he fades
        grabX = fx - (x - CX);
        grabY = fy - (y - FOOT);
        lastX = x;
        dragged = 0.0;
        drag = true;
        fingerX = fx; fingerY = fy;
        if (f.on) hitHim(fx, fy);
    }

    void touchMove(float fx, float fy) { fingerX = fx; fingerY = fy; }

    void touchUp(float fx, float fy) {
        if (!drag) return;
        drag = false;
        if (f.on && dragged < 4 * SC) return;   // just a hit, already dealt with
        f.air = "";
        if (dragged < 4 * SC && ledge != null) {
            // a tap rather than a drag: he jumps on the spot
            state = "cheer"; timer = 70; cool = 160; phase = 0.0;
            if (round(fx) != round(x)) dir = sign(fx - x);
            return;
        }
        state = "fall";
        vy    = 0.0;
        vx    = Math.max(-9.0 * SC, Math.min(9.0 * SC, (x - lastX) * 0.7));
        if (vx != 0) dir = sign(vx);
    }

    // held long enough for the menu: he is put down where he is
    void touchCancel() {
        if (!drag) return;
        drag = false;
        f.air = "";
        state = "fall"; vy = 0.0; vx = 0.0;
    }

    // you tapped something on screen: he drops what he is doing and runs over
    // to look. In a fight a tap anywhere but on him is ignored.
    void onTap(float cx, float cy) {
        if (f.on || gone > 0 || drag || state.equals("climb")) return;
        tx    = cx;
        ty    = cy;
        chase = 300;
        state = "chase";
        phase = 0.0;
        chasePeer = -1;
        if (cx != x) dir = sign(cx - x);
    }

    void toss() {
        drag  = false;
        state = "fall";
        vy    = -13.0 * SC;
        vx    = next(-3, 4) * SC;
    }

    void waveAtYou() {
        if (f.on || gone > 0 || drag) return;
        state = "wave"; timer = 70; phase = 0.0;
    }

    // ----------------------------------------------------- convert to symbol
    // he takes the colour at once, and his move is queued for the moment he is
    // back on something solid - see the pending block in stepPhysics
    void applyEgg(Eggs.Egg egg) {
        charName = egg.name;
        ink      = egg.ink;
        hasInk   = true;
        pending  = egg.act;
        pendTTL  = 400;
    }

    // the moves themselves, each one built only out of states the rest of
    // this already knows how to get back out of
    void doEggAct(String a) {
        switch (a) {
            case "cheer":  state = "cheer"; timer = 90; cool = 180; phase = 0.0; break;
            case "wave":   state = "wave";  timer = 90; cool = 180; phase = 0.0; break;
            case "launch":
                drag  = false;
                state = "fall";
                vy    = -14.0 * SC;
                vx    = next(-3, 4) * SC;
                break;
            case "chase": {
                // at the pointer: where you last tapped (OK, in the dialog)
                double cx = room.tapX >= 0 ? room.tapX : (room.workL + room.workR) / 2.0;
                double cy = room.tapY >= 0 ? room.tapY : (room.workT + room.workB) / 2.0;
                tx    = cx;
                ty    = cy;
                chase = 300;
                state = "chase";
                phase = 0.0;
                chasePeer = -1;
                if (cx != x) dir = sign(cx - x);
                break;
            }
        }
    }

    // wraps him in the symbol the dialog came back with
    void convertSymbol(String name, String type, int reg, boolean fight, boolean hardMode) {
        symbol  = true;
        symType = type;
        symReg  = reg;
        charName = "";
        hasInk  = false;
        if (name == null || name.trim().isEmpty()) name = "Symbol " + symNum;
        symNum++;

        Eggs.Egg egg = Eggs.find(name);
        if (egg != null) {
            applyEgg(egg);
            symName = egg.name;             // 'tsc' fills itself in properly
            symFlashMax = 26;               // a longer flash, in his new colour
        } else {
            symName = name.trim();
            symFlashMax = 14;
        }
        symFlash = symFlashMax;
        setHard(hardMode);
        if (fight) startFight(); else if (f.on) endFight();
    }

    // converting again while he already is one just swaps the figure, so this
    // is the only way back to his plain self
    void breakSymbol() {
        symbol      = false;
        charName    = "";
        hasInk      = false;
        pending     = "";
        symFlashMax = 8;
        symFlash    = 8;
        if (f.on) endFight();
    }

    // the name he goes by: the symbol's name (in full, for one of the hidden
    // figures), or 'Stick figure'
    String bodyName() {
        if (!symbol) return "Stick figure";
        return charName.isEmpty() ? symName : charName;
    }

    // he is going away: nothing of his is left behind
    void dropEverything() {
        for (Panel pr : new ArrayList<>(props)) removeProp(pr);
        releasePointer();
        f.on = false;
        pub.live = false;
    }
}
