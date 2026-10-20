package com.desktopstickman;

// How he looks this frame (Draw-Figure): his lines and head in design units
// inside his 44 x 68 sprite box, and what goes round them. Art draws a Pose on
// an Android canvas; tools/Preview.java draws the same Pose into a PNG.
final class Figure {
    static final int HURT_INK = 0xFFE22E2E;     // the red he flashes when you land one
    static final int DARK = 0xFF18181C, WHITE = 0xFFFFFFFF, FLASH_BLUE = 0xFF0099FF;

    static final class Pose {
        static final int MAX = 16;
        final float[] seg = new float[MAX * 4];
        int n;                          // lines
        float headX, headY;
        float lift;                     // the whole figure off the ground: the cheer hop, the start in shock
        int ink, halo;                  // his colour, and the outline that keeps it off the wallpaper
        int dots;                       // speech dots over his head while he chats
        final float[] dotX = new float[3];
        boolean stars;                  // knocked out: stars going round his head
        final float[] starX = new float[3], starY = new float[3];
        boolean hp; float hpFrac;       // in a fight, the hits he can still take
        boolean symbol;                 // the symbol box, Flash style
        int flash;                      // alpha of the flash after converting him, 0 for none
        int tint;                       // the box's colour
        int reg;                        // registration point, 0..8

        void add(double ax, double ay, double bx, double by) {
            if (n >= MAX) return;
            int i = 4 * n++;
            seg[i] = (float) ax; seg[i + 1] = (float) ay; seg[i + 2] = (float) bx; seg[i + 3] = (float) by;
        }
    }

    static int luminance(int c) {
        int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
        return (int) (0.299 * r + 0.587 * g + 0.114 * b);
    }

    static void pose(Stick s, Pose p) {
        p.n = 0; p.dots = 0; p.stars = false; p.lift = 0;

        // whichever figure he currently is. A pale colour needs a dark halo or he
        // disappears into a light wallpaper, so the outline flips with the ink.
        int ink = s.hasInk ? s.ink : Eggs.INK;
        if (s.f.hurt > 0 && s.f.hurt % 4 < 2) ink = HURT_INK;      // you landed one
        p.ink = ink;
        p.halo = luminance(ink) / 255.0 > 0.62 ? DARK : WHITE;

        double ph  = s.phase;
        double sin = Math.sin(ph);
        int d      = s.dir;
        double lean  = 0.0;
        double headY = 14.0;
        double headX = 22.0;

        String pose = s.drag ? "fall" : s.state;
        if (pose.equals("meet"))   pose = s.waiting ? "idle" : "walk";
        if (pose.equals("social")) pose = Stick.socialPose(s.act);
        if (pose.equals("fall") && !s.f.air.isEmpty() && !s.drag) pose = s.f.air;
        if (pose.equals("win") && s.timer >= Stick.PUMP_LEN) pose = "cheer";   // done punching the air
        if (pose.equals("cheer")) {
            // the whole figure leaves the ground for the hop
            p.lift = (float) (-Math.abs(Math.sin(ph * 1.4)) * 9.0);
        }
        if (pose.equals("shock") && s.timer < 12) {
            p.lift = (float) (-Math.sin(s.timer / 12.0 * Math.PI) * 7.0);       // a start
        }

        switch (pose) {
            case "climb":
                p.add(22, 21, 22, 40);                              // spine
                p.add(22, 25, 14, 13 - sin * 5);                    // arms reaching up
                p.add(22, 25, 30, 13 + sin * 5);
                p.add(22, 40, 14, 52 + sin * 5);                    // bent legs
                p.add(22, 40, 30, 52 - sin * 5);
                break;
            case "fall":
                headY = 15.0;
                p.add(22, 22, 22, 40);
                p.add(22, 26, 11, 15);
                p.add(22, 26, 33, 17);
                p.add(22, 40, 13, 60);
                p.add(22, 40, 30, 62);
                break;
            case "idle": {
                double bob = sin * 1.2;
                headY = 14.0 + bob;
                p.add(22, 21 + bob, 22, 40 + bob);
                p.add(22, 26 + bob, 16, 38 + bob);
                p.add(22, 26 + bob, 28, 38 + bob);
                p.add(22, 40 + bob, 17, 62);
                p.add(22, 40 + bob, 27, 62);
                break;
            }
            case "leap":
                // stretched out, both arms reaching for the corner
                headY = 16.0;
                p.add(22, 23, 22, 41);
                p.add(22, 26, 22 - d * 6, 9);
                p.add(22, 26, 22 + d * 9, 11);
                p.add(22, 41, 22 - d * 7, 56);                      // legs tucked and trailing
                p.add(22 - d * 7, 56, 22 - d * 12, 62);
                p.add(22, 41, 22 - d * 2, 60);
                break;
            case "cheer": {
                double sw = Math.sin(ph * 1.4);
                p.add(22, 21, 22, 40);
                p.add(22, 26, 12, 13 - sw * 3);                     // both arms up
                p.add(22, 26, 32, 13 + sw * 3);
                p.add(22, 40, 22 - 5 - sw * 3, 62);                 // legs kicking out
                p.add(22, 40, 22 + 5 + sw * 3, 62);
                break;
            }
            case "wave":
                headX = 22 + d * 1.5;
                p.add(22, 21, 22, 40);
                p.add(22, 26, 22 - d * 7, 38);                      // arm down
                p.add(22, 26, 22 + d * 10, 15 + sin * 5);           // arm waving
                p.add(22, 40, 17, 62);
                p.add(22, 40, 27, 62);
                break;
            case "sit":
                headY = 30.0;
                headX = 22 + d * 1.5;
                p.add(22, 37, 22 - d * 2, 54);                      // spine, leaning back
                p.add(22, 41, 22 - d * 8, 55);                      // arm propped behind
                p.add(22, 41, 22 + d * 5, 50);
                p.add(22 - d * 2, 54, 22 + d * 12, 53);             // thigh along the edge
                p.add(22 + d * 12, 53, 22 + d * 12 + sin * 3, 64);  // shin swinging
                break;
            case "press": {
                // squat down and stamp on the button
                double c = Math.sin(((42.0 - s.timer) / 42.0) * Math.PI);
                headY = 14.0 + 11.0 * c;
                p.add(22, 21 + 11 * c, 22, 40 + 6 * c);
                p.add(22, 26 + 10 * c, 22 - d * 8, 30 + 14 * c);
                p.add(22, 26 + 10 * c, 22 + d * 8, 30 + 14 * c);
                p.add(22, 40 + 6 * c, 22 - 6 - 5 * c, 52 + 2 * c);  // knees out
                p.add(22 - 6 - 5 * c, 52 + 2 * c, 22 - 6, 62);
                p.add(22, 40 + 6 * c, 22 + 6 + 5 * c, 52 + 2 * c);
                p.add(22 + 6 + 5 * c, 52 + 2 * c, 22 + 6, 62);
                break;
            }
            case "knock": {
                double rap = Math.max(0.0, sin);
                p.add(22, 21, 22, 40);
                p.add(22, 26, 22 + d * (8 + rap * 4), 25);          // knuckles on the glass
                p.add(22, 26, 22 - d * 6, 38);
                p.add(22, 40, 22 - d * 4, 62);
                p.add(22, 40, 22 + d * 4, 62);
                break;
            }
            case "push":
                lean  = d * 4.0;
                headX = 22 + lean * 1.3;
                headY = 16.0;
                p.add(22 + lean, 23, 22 - lean * 0.3, 40);
                p.add(22 + lean * 0.6, 27, 22 + d * 12, 29);
                p.add(22 + lean * 0.6, 27, 22 + d * 12, 33);
                p.add(22 - lean * 0.3, 40, 22 - d * 11, 62);        // braced back leg
                p.add(22 - lean * 0.3, 40, 22 + d * 3, 62);
                break;
            case "hifive": {
                // the arm goes up and out to meet his friend's hand in the middle
                double r = Math.sin(((40.0 - s.timer) / 40.0) * Math.PI);
                lean  = d * 1.5 * r;
                headX = 22 + lean;
                p.add(22 + lean * 0.6, 21, 22, 40);
                p.add(22 + lean * 0.4, 26, 22 + d * (4 + 8 * r), 24 - 14 * r);
                p.add(22 + lean * 0.4, 26, 22 - d * 6, 38);
                p.add(22, 40, 22 - d * 6, 62);
                p.add(22, 40, 22 + d * 4, 62);
                break;
            }
            case "chat": {
                // they take turns: one talks with his hands, the other nods along
                int first = s.slot < s.with ? 0 : 1;
                boolean talk = ((int) Math.floor(s.timer / 35.0) % 2) == first;
                p.add(22, 21, 22, 40);
                p.add(22, 26, 22 - d * 5, 38);
                if (talk) {
                    double gs = Math.sin(ph * 3.0);
                    p.add(22, 26, 22 + d * 8, 34);
                    p.add(22 + d * 8, 34, 22 + d * 13, 27 + gs * 3);
                    p.dots = 1 + (int) (Math.floor(ph * 1.5) % 3);
                } else {
                    headY = 14.0 + Math.abs(sin) * 1.5;
                    p.add(22, 26, 22 + d * 5, 38);
                }
                p.add(22, 40, 18, 62);
                p.add(22, 40, 26, 62);
                break;
            }
            case "guard": {
                // fists up, knees bent, bouncing on his toes
                double b = Math.abs(Math.sin(ph * 1.6)) * 1.6;
                headX = 22 + d * 2.0;
                headY = 18.0 + b;
                p.add(22 + d * 1.5, 25 + b, 22 - d * 0.5, 42 + b);
                p.add(22 + d * 1.2, 29 + b, 22 + d * 9, 35 + b);       // lead fist out front
                p.add(22 + d * 9, 35 + b, 22 + d * 12, 27 + b);
                p.add(22 + d * 1.2, 29 + b, 22 + d * 3, 37 + b);       // rear fist by his chin
                p.add(22 + d * 3, 37 + b, 22 + d * 7, 29 + b);
                p.add(22 - d * 0.5, 42 + b, 22 + d * 7, 52 + b / 2);   // lead leg
                p.add(22 + d * 7, 52 + b / 2, 22 + d * 9, 62);
                p.add(22 - d * 0.5, 42 + b, 22 - d * 6, 52 + b / 2);   // back leg
                p.add(22 - d * 6, 52 + b / 2, 22 - d * 10, 62);
                break;
            }
            case "taunt": {
                // 'come on, then': hand out, palm up, fingers beckoning
                double k = Math.max(0.0, Math.sin(ph * 3.0));
                headX = 22 + d * 1.0;
                headY = 17.0;
                p.add(22 + d * 1, 24, 22, 42);
                p.add(22 + d * 1, 28, 22 + d * 13, 31);
                p.add(22 + d * 13, 31, 22 + d * (17 - 3 * k), 31 - 5 * k);
                p.add(22 + d * 1, 28, 22 - d * 5, 35);                 // other hand on his hip
                p.add(22 - d * 5, 35, 22 - d * 1, 40);
                p.add(22, 42, 22 + d * 7, 52);
                p.add(22 + d * 7, 52, 22 + d * 9, 62);
                p.add(22, 42, 22 - d * 6, 52);
                p.add(22 - d * 6, 52, 22 - d * 10, 62);
                break;
            }
            case "punch": {
                // jab and cross in turn, lunging in behind it
                double e = Math.sin(((14.0 - s.timer) / 14.0) * Math.PI);
                lean  = d * 2.5 * e;
                headX = 22 + d * 2 + lean;
                headY = 18.0;
                double sx = 22 + d * 1.2 + lean;
                p.add(22 + d * 1.5 + lean, 25, 22 - d * 0.5, 42);
                double ex = 22 + d * (8 + 6 * e) + lean * 0.4;
                double fx = 22 + d * (11 + 7.5 * e) + lean * 0.4;
                p.add(sx, 29, ex, 34 - 7 * e);                         // the punching arm
                p.add(ex, 34 - 7 * e, fx, 27 - e);
                p.add(sx, 29, 22 + d * 3, 37);                         // the other stays up
                p.add(22 + d * 3, 37, 22 + d * 7, 29);
                p.add(22 - d * 0.5, 42, 22 + d * 8, 51);
                p.add(22 + d * 8, 51, 22 + d * 10, 62);
                p.add(22 - d * 0.5, 42, 22 - d * 6, 52);
                p.add(22 - d * 6, 52, 22 - d * 11, 62);
                break;
            }
            case "kick": {
                // leans back and snaps a kick out at the pointer
                double e = Math.sin(((20.0 - s.timer) / 20.0) * Math.PI);
                double back = d * 4.0 * e;
                headX = 22 + d * 1 - back;
                headY = 17.0 + 2 * e;
                p.add(22 + d * 1 - back * 0.9, 24 + 2 * e, 22 - d * 1, 42);
                p.add(22 + d * 1 - back * 0.7, 28 + 2 * e, 22 - d * 9, 34);            // arm out for balance
                p.add(22 + d * 1 - back * 0.7, 28 + 2 * e, 22 + d * 7, 25 + 2 * e);
                p.add(22 - d * 1, 42, 22 - d * 3, 52);                                 // standing leg
                p.add(22 - d * 3, 52, 22 - d * 5, 62);
                p.add(22 - d * 1, 42, 22 + d * (4 + 8 * e), 50 - 10 * e);              // kicking leg
                p.add(22 + d * (4 + 8 * e), 50 - 10 * e, 22 + d * (6 + 13 * e), 60 - 26 * e);
                break;
            }
            case "heave": {
                // wrenching a panel loose, trembling with the effort: both hands
                // on its side, leaning back further and further
                double k = Math.sin(ph * 6.0) * 0.7;
                double t  = 1.0 - s.timer / (double) (s.f.fly != null ? s.f.fly.len : Stick.HEAVE_LEN);
                double bk = d * 3.5 * t;
                headX = 22 - bk * 1.2;
                headY = 17.0;
                p.add(22 - bk, 24, 22, 41);
                p.add(22 - bk * 0.8, 28, 22 + d * 7 - bk * 0.5, 29 + k);
                p.add(22 + d * 7 - bk * 0.5, 29 + k, 22 + d * 14, 27 + k);
                p.add(22 - bk * 0.8, 28, 22 + d * 7 - bk * 0.5, 33 + k);
                p.add(22 + d * 7 - bk * 0.5, 33 + k, 22 + d * 14, 31 + k);
                p.add(22, 41, 22 + d * 6, 51); p.add(22 + d * 6, 51, 22 + d * 9, 62);
                p.add(22, 41, 22 - d * 6, 52); p.add(22 - d * 6, 52, 22 - d * 11, 62);
                break;
            }
            case "hurl": {
                // the follow-through: lunging after it, arms out at the pointer
                double e = Math.sin(((14.0 - s.timer) / 14.0) * Math.PI);
                lean  = d * 3.0 * e;
                headX = 22 + d * 2 + lean;
                headY = 17.0 + e;
                double sx = 22 + d * 1.2 + lean * 0.8;
                p.add(22 + d * 1.5 + lean, 24 + e, 22 - d * 0.5, 42);
                p.add(sx, 28, 22 + d * (8 + 3 * e) + lean * 0.5, 24 - 2 * e);
                p.add(22 + d * (8 + 3 * e) + lean * 0.5, 24 - 2 * e, 22 + d * (14 + 4 * e), 20 - 3 * e);
                p.add(sx, 28, 22 + d * (7 + 3 * e), 31);
                p.add(22 + d * (7 + 3 * e), 31, 22 + d * (13 + 3 * e), 28);
                p.add(22 - d * 0.5, 42, 22 + d * 8, 51); p.add(22 + d * 8, 51, 22 + d * 11, 62);
                p.add(22 - d * 0.5, 42, 22 - d * 6, 52); p.add(22 - d * 6, 52, 22 - d * 12, 62);
                break;
            }
            case "haul": {
                // the arm with your pointer in it comes from grabHand, which
                // stepGrab uses too, so the pointer sits right in his fist
                double[] hd = s.grabHand();
                if (Stick.GRAB_HOLD - s.timer < Stick.GRAB_SNATCH) {
                    // lunging in to take it, other fist up
                    headX = 22 + d * 3; headY = 17.0;
                    p.add(22 + d * 2.5, 24, 22 - d * 0.5, 42);
                    p.add(22 + d * 1, 27, hd[0], hd[1]);
                    p.add(22 + d * 1, 29, 22 + d * 3, 37); p.add(22 + d * 3, 37, 22 + d * 7, 29);
                    p.add(22 - d * 0.5, 42, 22 + d * 8, 51); p.add(22 + d * 8, 51, 22 + d * 10, 62);
                    p.add(22 - d * 0.5, 42, 22 - d * 6, 52); p.add(22 - d * 6, 52, 22 - d * 11, 62);
                } else {
                    // running off, dragging it along behind him
                    double sw = sin * 9.0;
                    headX = 22 + d * 3.5; headY = 16.0;
                    p.add(22 + d * 2.5, 23, 22, 40);
                    p.add(22 + d * 1, 27, hd[0], hd[1]);
                    p.add(22 + d * 1, 27, 22 + d * 1 + sw * 0.7, 37);
                    p.add(22, 40, 22 + sw, 62);
                    p.add(22, 40, 22 - sw, 62);
                }
                break;
            }
            case "fling": {
                // swinging it up over his head and letting fly
                double[] hd = s.grabHand();
                double e = Math.min(1.0, (Stick.FLING_LEN - s.timer) / (double) (Stick.FLING_LEN - Stick.FLING_AT));
                lean  = d * 3.0 * e;
                headX = 22 + d * 1 + lean; headY = 17.0;
                p.add(22 + d * 1.5 + lean * 0.8, 24, 22 - d * 0.5, 42);
                p.add(22 + d * 1, 27, hd[0], hd[1]);
                p.add(22 + d * 1, 28, 22 - d * 10, 33 - 4 * e);
                p.add(22 - d * 0.5, 42, 22 + d * 8, 51); p.add(22 + d * 8, 51, 22 + d * 11, 62);
                p.add(22 - d * 0.5, 42, 22 - d * 6, 52); p.add(22 - d * 6, 52, 22 - d * 12, 62);
                break;
            }
            case "flykick":
                // one leg straight out at the pointer, the other tucked under
                headX = 22 - d * 5;
                headY = 15.0;
                p.add(22 - d * 4, 22, 22 + d * 1, 38);
                p.add(22 + d * 1, 38, 22 + d * 19, 34);
                p.add(22 + d * 1, 38, 22 - d * 3, 49);
                p.add(22 - d * 3, 49, 22 - d * 10, 45);
                p.add(22 - d * 3, 26, 22 + d * 7, 21);
                p.add(22 - d * 3, 26, 22 - d * 13, 30);
                break;
            case "hurt":
                // knocked back: head snapped back, arms and legs flung forward
                headX = 22 - d * 6;
                headY = 16.0;
                p.add(22 - d * 4.5, 22.5, 22 + d * 1, 40);
                p.add(22 - d * 3, 27, 22 + d * 9, 19);
                p.add(22 - d * 3, 27, 22 + d * 10, 31);
                p.add(22 + d * 1, 40, 22 + d * 10, 55);
                p.add(22 + d * 1, 40, 22 + d * 4, 61);
                break;
            case "flip":
                // a quick hop back out of the way, knees tucked
                headX = 22 - d * 2;
                headY = 19.0;
                p.add(22 - d * 1.5, 25.5, 22, 40);
                p.add(22 - d * 1, 29, 22 + d * 9, 25);
                p.add(22 - d * 1, 29, 22 - d * 9, 33);
                p.add(22, 40, 22 + d * 7, 47);
                p.add(22 + d * 7, 47, 22 + d * 2, 55);
                p.add(22, 40, 22 + d * 4, 50);
                p.add(22 + d * 4, 50, 22 - d * 2, 58);
                break;
            case "win": {
                // punching the air over the pieces, other hand on his hip
                double pump = Math.abs(Math.sin(ph * 1.3));
                headX = 22 + d * 1.0;
                headY = 14.0 + pump * 0.8;
                p.add(22, 21 + pump * 0.8, 22, 40);
                p.add(22, 26, 22 + d * 9, 21 - 2 * pump);                         // fist to the sky
                p.add(22 + d * 9, 21 - 2 * pump, 22 + d * 10, 10 - 3 * pump);
                p.add(22, 26, 22 - d * 6, 33);                                    // hand on his hip
                p.add(22 - d * 6, 33, 22 - d * 2, 39);
                p.add(22, 40, 22 - d * 6, 62);                                    // feet planted wide
                p.add(22, 40, 22 + d * 6, 62);
                break;
            }
            case "shock": {
                // it is mending: he jumps back, hands up, trembling, with a '!'
                double q = Math.sin(ph * 9.0) * 0.5;
                headX = 22 - d * 3 + q;
                headY = 16.0;
                p.add(22 - d * 2 + q, 23, 22, 41);
                p.add(22 - d * 1.5 + q, 27, 22 + d * 5, 23);
                p.add(22 + d * 5, 23, 22 + d * 8, 15 + q);
                p.add(22 - d * 1.5 + q, 27, 22 + d * 4, 32);
                p.add(22 + d * 4, 32, 22 + d * 10, 27 - q);
                p.add(22, 41, 22 + d * 5, 51); p.add(22 + d * 5, 51, 22 + d * 4, 62);
                p.add(22, 41, 22 - d * 5, 52); p.add(22 - d * 5, 52, 22 - d * 9, 62);
                double ex = 22 + d * 16;
                p.add(ex, 7, ex, 13.5);
                p.add(ex, 17.4, ex, 17.8);
                break;
            }
            case "ko":
                // flat on his back with his knees up
                headX = 22 - d * 12;
                headY = 55.0;
                p.add(22 - d * 5.5, 58, 22 + d * 5, 60);
                p.add(22 - d * 4, 58, 22 + d * 1, 51);
                p.add(22 - d * 4, 58, 22 - d * 10, 62);
                p.add(22 + d * 5, 60, 22 + d * 11, 50);
                p.add(22 + d * 11, 50, 22 + d * 17, 61);
                p.add(22 + d * 5, 60, 22 + d * 13, 53);
                p.add(22 + d * 13, 53, 22 + d * 18, 62);
                break;
            default: {  // walk
                lean = d * 2.0;
                double swing = sin * 7.0;
                headX = 22 + lean * 0.9;
                p.add(22 + lean * 0.7, 21, 22, 40);
                p.add(22 + lean * 0.4, 26, 22 - swing, 37 - Math.abs(sin) * 2);
                p.add(22 + lean * 0.4, 26, 22 + swing, 37 - Math.abs(sin) * 2);
                p.add(22, 40, 22 + swing, 62);
                p.add(22, 40, 22 - swing, 62);
                break;
            }
        }

        p.headX = (float) headX;
        p.headY = (float) headY;
        for (int i = 0; i < p.dots; i++) p.dotX[i] = (float) (22 + d * (9 + i * 4));

        if (pose.equals("ko")) {
            p.stars = true;
            for (int i = 0; i < 3; i++) {
                double a = ph * 2.2 + i * 2.0944;
                p.starX[i] = (float) (headX + Math.cos(a) * 8.0);
                p.starY[i] = (float) (headY - 11.0 + Math.sin(a) * 2.5);
            }
        }

        p.hp = s.f.on;
        p.hpFrac = (float) (Math.max(0, s.f.hp) / (double) s.f.max);

        // the box takes the figure's colour when he is one of the hidden names,
        // and stays Flash blue when he is just a symbol
        p.symbol = s.symbol;
        p.tint = s.hasInk ? s.ink : FLASH_BLUE;
        p.flash = s.symFlash > 0 ? (int) (80.0 * s.symFlash / Math.max(1, s.symFlashMax)) : 0;
        p.reg = s.symReg;
    }

    private Figure() { }
}
