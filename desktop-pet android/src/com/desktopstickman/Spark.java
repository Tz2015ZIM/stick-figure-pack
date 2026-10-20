package com.desktopstickman;

import java.util.Random;

// A blow that lands pops a comic-book spark where it hit (Pop-Spark, Draw-Fx).
final class Spark {
    static final int LEN = 10;

    int n;                  // frames left
    float x, y;             // where, on screen
    double rot;

    void pop(double x, double y, Random rng) {
        n = LEN; this.x = (int) x; this.y = (int) y; rot = rng.nextDouble();
    }

    // once a frame, before it is drawn: it pops out and fades, then goes
    void step() { if (n > 0) n--; }

    boolean on() { return n > 0; }

    // 0 as it pops, nearly 1 as it goes
    double t() { return 1.0 - n / (double) LEN; }
}
