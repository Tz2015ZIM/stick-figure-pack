package com.desktopstickman;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.AffineTransform;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Line2D;
import java.awt.geom.Path2D;
import java.awt.geom.Rectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import javax.imageio.ImageIO;

// Runs the stickmen on a plain JVM, with no phone: draws every pose into a
// contact sheet, then lets a few of them loose on a made-up screen for a few
// thousand frames, in peace and in a fight, and reports what they got up to.
//
//   javac -d out src/com/desktopstickman/*.java tools/Preview.java
//   java -cp out com.desktopstickman.Preview <folder for the PNGs>
public final class Preview {
    static final float SC = 2.75f;              // a 440-dpi phone
    static final int W = 1080, H = 2340;

    public static void main(String[] args) throws Exception {
        File dir = new File(args.length > 0 ? args[0] : ".");
        dir.mkdirs();
        sheet(new File(dir, "poses.png"));
        int bad = peace(dir) + fight(dir);
        System.out.println(bad == 0 ? "ALL GOOD" : bad + " PROBLEMS");
        if (bad != 0) System.exit(1);
    }

    static Room room() {
        Room r = new Room(SC);
        // a 1080 x 2340 screen: 63 px of status bar, 132 px of navigation bar
        r.setScreen(0, 0, W, H, 0, 63, W, H - 132);
        r.hands = new Room.Hands() {
            public boolean openApp(String label) { opened++; return true; }
            public void press(Ledge b) { pressed++; }
        };
        return r;
    }
    static int opened, pressed;

    // ---------------------------------------------------------------- poses
    static final String[] POSES = {
        "walk", "idle", "fall", "climb", "leap", "cheer", "wave", "sit", "press", "knock", "push",
        "hifive", "chat", "guard", "taunt", "punch", "kick", "heave", "hurl", "haul", "fling",
        "flykick", "hurt", "flip", "win", "shock", "ko",
    };

    static void sheet(File out) throws Exception {
        Room r = room();
        Stick s = r.add();
        int cols = 9, cell = (int) (Stick.DW * 3) + 20, rowH = (int) (Stick.DH * 3) + 40;
        int rows = (POSES.length * 2 + cols - 1) / cols;
        BufferedImage img = new BufferedImage(cols * cell, rows * rowH, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setColor(new Color(0xB8C7D9));
        g.fillRect(0, 0, img.getWidth(), img.getHeight());
        Figure.Pose p = new Figure.Pose();
        int i = 0;
        for (int pass = 0; pass < 2; pass++) {
            for (String name : POSES) {
                s.state = name; s.dir = 1; s.phase = 1.1; s.timer = 9; s.drag = false; s.f.air = "";
                s.f.on = pass == 1; s.f.hp = 5; s.f.max = 8;
                s.symbol = pass == 1; s.symReg = 4; s.hasInk = pass == 1 && name.length() % 3 == 0;
                s.ink = 0xFF1C7ED6;
                if (name.equals("flykick") || name.equals("hurt") || name.equals("flip")) { s.state = "fall"; s.f.air = name; }
                if (name.equals("hifive") || name.equals("chat")) { s.state = "social"; s.act = name.equals("hifive") ? "highfive" : "chat"; s.with = 1; s.timer = name.equals("chat") ? 10 : 20; }
                if (name.equals("haul")) s.timer = Stick.GRAB_HOLD - 20;
                if (name.equals("press")) s.timer = 22;
                if (name.equals("win")) s.timer = 10;
                Figure.pose(s, p);
                int cx = (i % cols) * cell + 10, cy = (i / cols) * rowH + 10;
                AffineTransform at = g.getTransform();
                g.translate(cx, cy);
                g.scale(3, 3);
                drawPose(g, p);
                g.setTransform(at);
                g.setColor(Color.BLACK);
                g.setFont(new Font("SansSerif", Font.PLAIN, 13));
                g.drawString(name, cx, cy + rowH - 16);
                i++;
            }
        }
        g.dispose();
        ImageIO.write(img, "png", out);
    }

    // Art.figure, in Java2D
    static void drawPose(Graphics2D g, Figure.Pose p) {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        AffineTransform base = g.getTransform();
        g.translate(0, p.lift);
        BasicStroke halo = new BasicStroke(6.5f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND);
        BasicStroke main = new BasicStroke(3.0f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND);
        Ellipse2D head = new Ellipse2D.Float(p.headX - 6.5f, p.headY - 6.5f, 13, 13);
        g.setColor(new Color(p.halo, true));
        g.setStroke(halo);
        for (int i = 0; i < p.n; i++) g.draw(new Line2D.Float(p.seg[4 * i], p.seg[4 * i + 1], p.seg[4 * i + 2], p.seg[4 * i + 3]));
        g.draw(head);
        g.setColor(Color.WHITE);
        g.fill(head);
        g.setColor(new Color(p.ink, true));
        g.setStroke(main);
        for (int i = 0; i < p.n; i++) g.draw(new Line2D.Float(p.seg[4 * i], p.seg[4 * i + 1], p.seg[4 * i + 2], p.seg[4 * i + 3]));
        g.draw(head);
        for (int i = 0; i < p.dots; i++) {
            g.setColor(new Color(p.halo, true));
            g.fill(new Ellipse2D.Float(p.dotX[i] - 2.2f, 1.3f, 4.4f, 4.4f));
            g.setColor(new Color(p.ink, true));
            g.fill(new Ellipse2D.Float(p.dotX[i] - 1.3f, 2.2f, 2.6f, 2.6f));
        }
        if (p.stars) {
            for (int i = 0; i < 3; i++) {
                float sx = p.starX[i], sy = p.starY[i];
                for (int k = 0; k < 2; k++) {
                    g.setColor(k == 0 ? new Color(0xFF18181C, true) : new Color(0xFFFFD600, true));
                    g.setStroke(new BasicStroke(k == 0 ? 3.3f : 1.5f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
                    g.draw(new Line2D.Float(sx - 2.6f, sy, sx + 2.6f, sy));
                    g.draw(new Line2D.Float(sx, sy - 2.6f, sx, sy + 2.6f));
                }
            }
        }
        g.setTransform(base);
        if (p.hp) {
            g.setColor(new Color(p.halo, true)); g.fill(new Rectangle2D.Float(7, 3, 30, 4.5f));
            g.setColor(new Color(0xFF5A1818, true)); g.fill(new Rectangle2D.Float(8, 4, 28, 2.5f));
            g.setColor(new Color(0xFFE83434, true)); g.fill(new Rectangle2D.Float(8, 4, 28 * p.hpFrac, 2.5f));
        }
        if (p.symbol) {
            float bw = (float) Stick.DW - 3, bh = (float) Stick.DH - 3;
            g.setStroke(new BasicStroke(1.3f));
            g.setColor(new Color(p.tint, true));
            g.draw(new Rectangle2D.Float(1.5f, 1.5f, bw, bh));
            float rx = 1.5f + bw * ((p.reg % 3) / 2f), ry = 1.5f + bh * ((p.reg / 3) / 2f);
            g.draw(new Line2D.Float(rx - 3, ry, rx + 3, ry));
            g.draw(new Line2D.Float(rx, ry - 3, rx, ry + 3));
        }
    }

    // ---------------------------------------------------------------- scenes
    // a dialog with two buttons, the keyboard, and a row of app icons
    static Ledge[] world() {
        List<Ledge> l = new ArrayList<>();
        l.add(Ledge.window(101, 120, 900, 960, 1500, false));          // a dialog
        l.add(Ledge.keyboard(102, 0, 1500, 1080, 2208));               // the keyboard
        l.add(Ledge.button(201, 560, 1360, 740, 1460));                // its OK and Cancel
        l.add(Ledge.button(202, 780, 1360, 940, 1460));
        for (int i = 0; i < 4; i++) l.add(Ledge.appIcon(301 + i, 80 + i * 260, 500, 280 + i * 260, 700, "App " + i));
        return l.toArray(new Ledge[0]);
    }

    static int problems;
    static void check(boolean ok, String what) {
        if (!ok) { problems++; if (problems < 20) System.out.println("  PROBLEM: " + what); }
    }

    static void inBounds(Room r, Stick s, int frame) {
        check(!Double.isNaN(s.x) && !Double.isNaN(s.y), "NaN position at frame " + frame);
        check(s.x >= r.scrL && s.x <= r.scrR, "x off screen (" + s.x + ") in " + s.state + " at frame " + frame);
        check(s.y >= r.scrT - 400 * SC && s.y <= r.scrB + 130 * SC, "y off screen (" + s.y + ") in " + s.state + " at frame " + frame);
    }

    static final long[] SEEDS = { 1, 2, 3 };

    static int peace(File dir) throws Exception {
        problems = 0;
        keyboard();
        for (long seed : SEEDS) peace(dir, seed);
        System.out.println("peace: " + problems + " problems");
        return problems;
    }

    // the keyboard comes up under someone on the ground and lifts him onto it;
    // it goes, and he drops back down to the bottom of the screen
    static void keyboard() {
        Room r = room();
        r.rng.setSeed(9);
        Stick s = r.add();
        for (int i = 0; i < 200 && !(s.ledge != null && s.ledge.ground); i++) r.step();
        check(s.ledge != null && s.ledge.ground && s.y == r.workB, "never landed on the ground");
        s.state = "idle"; s.timer = 100000;
        r.seen = new Ledge[] { Ledge.keyboard(102, 0, 1500, 1080, 2208) };
        for (int i = 0; i < 10; i++) r.step();
        check(s.y == 1500 && s.ledge.ground, "left behind the keyboard (y " + s.y + ")");
        r.seen = new Ledge[0];
        for (int i = 0; i < 10; i++) r.step();
        check(s.state.equals("fall"), "stood on a keyboard that went");
        for (int i = 0; i < 80; i++) r.step();
        check(s.y == r.workB && s.ledge != null && s.ledge.ground, "never got back down after the keyboard went");
        System.out.println("keyboard: lifted and dropped");
    }

    static void peace(File dir, long seed) throws Exception {
        Room r = room();
        r.rng.setSeed(seed);
        r.seen = world();
        r.add(); r.add(); r.add();
        Map<String, Integer> seen = new TreeMap<>();
        int social = 0;
        opened = 0; pressed = 0;
        for (int frame = 0; frame < 40000; frame++) {
            // now and then you tap something, or the keyboard goes away and comes back
            if (frame % 1700 == 900) r.tapped(200 + (frame % 600), 1400);
            if (frame % 5000 == 2500) r.seen = new Ledge[] { world()[0], world()[2], world()[3] };
            if (frame % 5000 == 4000) r.seen = world();
            r.step();
            for (Stick s : r.sticks) {
                inBounds(r, s, frame);
                seen.merge(s.drag ? "drag" : s.state, 1, Integer::sum);
                if (s.state.equals("social")) social++;
                // nobody is ever left standing on the ground behind the keyboard
                if (s.ledge != null && s.ledge.ground && s.tick % 5 == 0 && !Stick.in(s.state, "climb", "leap", "fall")) {
                    check(s.y == r.floor(), "on the ground at " + s.y + " with it at " + r.floor() + ", in " + s.state);
                }
            }
            if (frame == 3000 && seed == SEEDS[0]) scene(r, new File(dir, "peace.png"));
        }
        System.out.println("peace " + seed + ": states " + seen);
        System.out.println("peace " + seed + ": social frames " + social + ", apps opened " + opened + ", buttons pressed " + pressed + " (pressing off)");
        check(seen.containsKey("climb"), "never climbed");
        check(seen.containsKey("press"), "never stamped on anything");
        check(social > 0, "never met up");
        check(pressed == 0, "pressed a button with pressing switched off");
        check(opened <= 40000 / Stick.OPEN_GAP + 1, "opened apps more often than once every 45 seconds");
    }

    static int fight(File dir) throws Exception {
        problems = 0;
        for (long seed : SEEDS) fight(dir, seed, false);
        fight(dir, SEEDS[0], true);
        System.out.println("fight: " + problems + " problems");
        return problems;
    }

    static void fight(File dir, long seed, boolean hard) throws Exception {
        Room r = room();
        r.rng.setSeed(seed);
        r.seen = world();
        Stick s = r.add();
        for (int i = 0; i < 60; i++) r.step();      // let him land
        s.convertSymbol("blue stickman", "Movie Clip", 4, true, hard);
        check(s.f.on && s.charName.equals("Blue") && r.ptr.up, "fight did not start as Blue");
        check(s.f.max == (hard ? 20 : 8) && r.ptr.max == (hard ? 6 : 10), "wrong hits for " + (hard ? "hard" : "normal") + " mode");
        // a finger anywhere and the pointer is there; a drag and it follows
        r.ptr.fingerDown(150, 900);
        check(r.ptr.x == 150 && r.ptr.y == 900, "pointer did not jump to the finger");
        r.ptr.fingerMove(400, 1000);
        check(r.ptr.x == 400 && r.ptr.y == 1000, "pointer did not follow the finger");
        r.ptr.fingerUp(400, 1000);
        // a mouse cursor moving about, nothing pressed: the pointer is where it is
        r.ptr.hover(700, 500);
        r.ptr.hover(720, 520);
        check(r.ptr.x == 720 && r.ptr.y == 520, "pointer did not follow the mouse");
        // while he has it, moving the mouse is pulling at it, and hard enough gets it back
        s.startGrab();
        r.step();
        float hx = r.ptr.x;
        r.ptr.hover(100, 300);
        check(s.f.grab && r.ptr.x == hx, "the mouse moving took it straight out of his hand");
        for (int k = 0; k < 12 && s.f.grab; k++) { r.ptr.hover(k % 2 == 0 ? 900 : 100, 300); r.step(); }
        check(!s.f.grab, "wiggling the mouse never got it back from him");
        r.ptr.hoverGone();
        for (int i = 0; i < 60; i++) r.step();
        // and a tap gets it back too, where you tapped, and hurts him
        r.ptr.restore();
        s.startGrab();
        int hp = s.f.hp;
        r.ptr.fingerDown(800, 600);
        check(s.f.grab, "a finger coming down took it out of his hand");
        r.ptr.fingerUp(800, 600);
        check(!s.f.grab && r.ptr.x == 800 && r.ptr.y == 600, "a tap did not get the pointer back from him");
        check(s.f.hp == hp - 1 || s.f.inv == 8, "a tap while he had it did not count as a hit");
        for (int i = 0; i < 60; i++) r.step();      // let him get back on his feet
        Map<String, Integer> seen = new TreeMap<>();
        int breaks = 0, maxPanels = 0, hits = 0, blows = 0, yanks = 0;
        boolean wasDead = false;
        int lastPtrHp = r.ptr.hp;
        java.util.Random you = new java.util.Random(seed + 7);
        float fx = 0, fy = 0;
        for (int frame = 0; frame < 30000 && r.sticks.contains(s); frame++) {
            // you: leave the arrow up out of his reach a while, so out come the panels
            if (frame >= 1500 && frame < 2400) {
                if (frame == 1500) { r.ptr.fingerUp(fx, fy); r.ptr.restore(); fx = s.x < W / 2 ? r.workR - 60 : r.workL + 60; }
                if (!r.ptr.dead) r.ptr.move(fx, r.workT + 20);      // kept up in the far corner
                r.step();
                maxPanels = Math.max(maxPanels, s.props.size());
                if (r.ptr.dead && !wasDead) breaks++;
                wasDead = r.ptr.dead;
                if (frame == 1800 && seed == SEEDS[0] && !hard) scene(r, new File(dir, "fight-panels.png"));
                continue;
            }
            // he has your pointer: now and then you wiggle it hard to get it back
            if (s.f.grab && frame % 7 == 0 && you.nextInt(3) == 0) {
                r.ptr.fingerDown(r.ptr.x, r.ptr.y);
                for (int k = 0; k < 6; k++) r.ptr.fingerMove(r.ptr.x + (k % 2 == 0 ? 90 : -90) * SC, r.ptr.y);
                r.step();
                if (!s.f.grab) yanks++;
                r.ptr.fingerUp(r.ptr.x, r.ptr.y);
                continue;
            }
            // otherwise drag the arrow about, sometimes right at him, and now and then tap him
            if (!r.ptr.dead && frame % 120 == 0) {
                fx = r.ptr.x; fy = r.ptr.y;
                r.ptr.fingerDown(fx, fy);
            }
            if (r.ptr.held && frame % 120 < 50) {
                double tx = frame % 240 < 120 ? s.x + 20 * SC : 200 + you.nextInt(600);
                double ty = frame % 240 < 120 ? s.y - 34 * SC : 600 + you.nextInt(800);
                fx += (float) ((tx - fx) * 0.15); fy += (float) ((ty - fy) * 0.15);
                r.ptr.fingerMove(fx, fy);
            }
            if (frame % 120 == 50) r.ptr.fingerUp(fx, fy);
            if (frame > 4000 && frame % 97 == 0 && s.gone == 0) {
                s.touchDown((float) s.x, (float) (s.y - 30 * SC));
                s.touchUp((float) s.x, (float) (s.y - 30 * SC));
                hits++;
            }
            r.step();
            if (r.sticks.contains(s)) inBounds(r, s, frame);
            String st = s.state.equals("fall") && !s.f.air.isEmpty() ? s.f.air : s.state;
            seen.merge(st, 1, Integer::sum);
            maxPanels = Math.max(maxPanels, s.props.size());
            if (r.ptr.dead && !wasDead) breaks++;
            if (r.ptr.hp < lastPtrHp) blows++;
            lastPtrHp = r.ptr.hp;
            wasDead = r.ptr.dead;
            if ((frame == 700 || frame == 1400) && seed == SEEDS[0] && !hard) scene(r, new File(dir, "fight" + frame + ".png"));
            check(r.ptr.x >= r.workL && r.ptr.x < r.workR && r.ptr.y >= r.workT && r.ptr.y < r.workB, "pointer off screen");
        }
        String name = "fight " + seed + (hard ? " hard" : "");
        System.out.println(name + ": states " + seen);
        System.out.println(name + ": blows on the pointer " + blows + ", pointer broken " + breaks + " times, most panels at once "
                           + maxPanels + ", taps on him " + hits + ", pointer pulled back " + yanks + " times");
        check(seen.containsKey("hunt"), "never ran after the pointer");
        check(!r.sticks.contains(s), "never knocked out and gone");
        check(breaks > 0, "never broke the pointer");
        check(maxPanels > 0, "never threw a panel");
        check(seen.containsKey("haul"), "never grabbed the pointer");
        check(!r.ptr.up, "pointer still up after he was beaten");
    }

    // the whole screen, shrunk: ledges, panels, the pointer and them
    static void scene(Room r, File out) throws Exception {
        float k = 0.4f;
        BufferedImage img = new BufferedImage((int) (W * k), (int) (H * k), BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.scale(k, k);
        g.setColor(new Color(0xDDE6EF)); g.fillRect(0, 0, W, H);
        g.setColor(new Color(0x9BB0C6)); g.fillRect(0, r.workB, W, H - r.workB);
        for (Ledge l : r.seen) {
            g.setColor(l.btn ? new Color(0x5B8DEF) : l.icon ? new Color(0x67B26F) : new Color(0xFFFFFF));
            g.fill(new Rectangle2D.Double(l.l, l.t, l.r - l.l, l.b - l.t));
            g.setColor(Color.GRAY);
            g.draw(new Rectangle2D.Double(l.l, l.t, l.r - l.l, l.b - l.t));
        }
        for (Stick s : r.sticks) {
            for (Panel pr : s.props) {
                g.setColor(new Color(0xEEEEEE)); g.fill(new Rectangle2D.Double(pr.x, pr.y, pr.w, pr.h));
                g.setColor(new Color(0x333333)); g.fill(new Rectangle2D.Double(pr.x, pr.y, pr.w, Panel.TITLE * SC));
            }
            Figure.Pose p = new Figure.Pose();
            Figure.pose(s, p);
            AffineTransform at = g.getTransform();
            g.translate(s.x - s.CX, s.y - s.FOOT);
            g.scale(SC, SC);
            drawPose(g, p);
            g.setTransform(at);
        }
        if (r.ptr.up && !r.ptr.dead) {
            Path2D.Float a = new Path2D.Float();
            float ak = Pointer.ARROW * SC;
            for (int i = 0; i < Pointer.ARROW_XY.length; i += 2) {
                float px = r.ptr.x + Pointer.ARROW_XY[i] * ak, py = r.ptr.y + Pointer.ARROW_XY[i + 1] * ak;
                if (i == 0) a.moveTo(px, py); else a.lineTo(px, py);
            }
            a.closePath();
            g.setColor(Color.WHITE); g.fill(a);
            g.setColor(Color.BLACK); g.setStroke(new BasicStroke(1.2f * ak)); g.draw(a);
        }
        g.dispose();
        ImageIO.write(img, "png", out);
    }
}
