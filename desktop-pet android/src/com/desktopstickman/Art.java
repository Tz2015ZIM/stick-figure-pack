package com.desktopstickman;

import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;

import java.util.Random;

// Everything he and his things look like, drawn onto a canvas: Draw-Figure,
// Draw-SymbolBox, Draw-Fx, Paint-KoText, New-PropImage, the arrow and its bar,
// and Draw-Wreck. All in design units, scaled by sc.
final class Art {
    static final int DARK = 0xFF18181C;
    static final int FLASH_BLUE = 0xFF0099FF;

    final float sc;
    private final Paint halo = stroke(6.5f), main = stroke(3.0f), fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint thin = stroke(1.0f);
    private final RectF rect = new RectF();
    private final Path path = new Path();

    Art(float sc) {
        this.sc = sc;
        fill.setStyle(Paint.Style.FILL);
        newKoArt();
    }

    static Paint stroke(float w) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(w);
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setStrokeJoin(Paint.Join.ROUND);
        return p;
    }

    static int argb(int a, int c) { return (Math.max(0, Math.min(255, a)) << 24) | (c & 0xFFFFFF); }

    // ------------------------------------------------------------------- him
    void figure(Canvas c, Figure.Pose p) {
        c.save();
        c.scale(sc, sc);                    // design units from here on
        c.save();
        c.translate(0, p.lift);

        halo.setColor(p.halo);
        halo.setStrokeWidth(6.5f);
        main.setColor(p.ink);
        main.setStrokeWidth(3.0f);
        float[] s = p.seg;
        for (int i = 0; i < p.n; i++) c.drawLine(s[4 * i], s[4 * i + 1], s[4 * i + 2], s[4 * i + 3], halo);
        c.drawCircle(p.headX, p.headY, 6.5f, halo);
        fill.setColor(0xFFFFFFFF);
        c.drawCircle(p.headX, p.headY, 6.5f, fill);
        for (int i = 0; i < p.n; i++) c.drawLine(s[4 * i], s[4 * i + 1], s[4 * i + 2], s[4 * i + 3], main);
        c.drawCircle(p.headX, p.headY, 6.5f, main);

        for (int i = 0; i < p.dots; i++) {
            float dx = p.dotX[i];
            fill.setColor(p.halo);
            c.drawCircle(dx, 3.5f, 2.2f, fill);
            fill.setColor(p.ink);
            c.drawCircle(dx, 3.5f, 1.3f, fill);
        }

        if (p.stars) {
            // stars going round his head
            for (int i = 0; i < 3; i++) {
                float sx = p.starX[i], sy = p.starY[i];
                for (int k = 0; k < 2; k++) {
                    halo.setColor(k == 0 ? DARK : 0xFFFFD600);
                    halo.setStrokeWidth(k == 0 ? 3.3f : 1.5f);
                    c.drawLine(sx - 2.6f, sy, sx + 2.6f, sy, halo);
                    c.drawLine(sx, sy - 2.6f, sx, sy + 2.6f, halo);
                }
            }
        }
        c.restore();                        // the cheer hop must not move what follows

        if (p.hp) {
            // the hits he can still take, staying put while he hops about
            fill.setColor(p.halo);       c.drawRect(7, 3, 37, 7.5f, fill);
            fill.setColor(0xFF5A1818);   c.drawRect(8, 4, 36, 6.5f, fill);
            fill.setColor(0xFFE83434);   c.drawRect(8, 4, 8 + 28 * p.hpFrac, 6.5f, fill);
        }
        if (p.symbol || p.flash > 0) symbolBox(c, p);
        c.restore();
    }

    // The Flash-style wrapper: the selection rectangle plus the little
    // registration cross at whichever of the nine points you picked.
    private void symbolBox(Canvas c, Figure.Pose p) {
        float bx = 1.5f, by = 1.5f;
        float bw = (float) (Stick.DW - 3.0), bh = (float) (Stick.DH - 3.0);
        if (p.flash > 0) {
            fill.setColor(argb(p.flash, p.tint));
            c.drawRect(bx, by, bx + bw, by + bh, fill);
        }
        if (!p.symbol) return;
        // a white halo so the thin line survives a light wallpaper, then the line itself
        thin.setStrokeCap(Paint.Cap.BUTT);
        thin.setStrokeJoin(Paint.Join.MITER);
        thin.setColor(0x96FFFFFF); thin.setStrokeWidth(3.2f);
        c.drawRect(bx, by, bx + bw, by + bh, thin);
        thin.setColor(p.tint); thin.setStrokeWidth(1.3f);
        c.drawRect(bx, by, bx + bw, by + bh, thin);

        float rx = bx + bw * ((p.reg % 3) / 2f);
        float ry = by + bh * ((p.reg / 3) / 2f);
        float arm = 3.0f;
        thin.setColor(0x96FFFFFF); thin.setStrokeWidth(3.2f);
        c.drawLine(rx - arm, ry, rx + arm, ry, thin);
        c.drawLine(rx, ry - arm, rx, ry + arm, thin);
        thin.setColor(p.tint); thin.setStrokeWidth(1.7f);
        c.drawLine(rx - arm, ry, rx + arm, ry, thin);
        c.drawLine(rx, ry - arm, rx, ry + arm, thin);
        thin.setStrokeCap(Paint.Cap.ROUND);
        thin.setStrokeJoin(Paint.Join.ROUND);
    }

    // ----------------------------------------------------------------- spark
    static final float FXS = 72.0f;         // spark window, design units

    int sparkSize() { return Math.round(FXS * sc); }

    // one frame of the spark: an eight-pointed star that pops out and fades
    void spark(Canvas c, Spark f) {
        double t = f.t();
        int a = (int) (255 * (1.0 - t * t));
        double ro = 9.0 + 22.0 * Math.sqrt(t);
        c.save();
        c.scale(sc, sc);
        star(ro, ro * 0.45, f.rot);
        fill.setColor(argb(a, 0xFFFFFF));
        c.drawPath(path, fill);
        thin.setColor(argb(a, DARK)); thin.setStrokeWidth(1.8f);
        c.drawPath(path, thin);
        star(ro * 0.55, ro * 0.25, f.rot + 0.2);
        fill.setColor(argb(a, 0xFFCC00));
        c.drawPath(path, fill);
        c.restore();
    }

    private void star(double ro, double ri, double rot) {
        float m = FXS / 2f;
        path.rewind();
        for (int i = 0; i < 16; i++) {
            double r = i % 2 == 0 ? ro : ri;
            double a = i * Math.PI / 8 + rot;
            float x = (float) (m + Math.cos(a) * r), y = (float) (m + Math.sin(a) * r);
            if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        path.close();
    }

    // ------------------------------------------------------------------ K.O.
    // "K.O.!" typed above him the way the animator would with Flash's Text
    // tool: a text box with its little round handle in the corner grows a
    // letter at a time, the caret blinking at its end, then the text is left
    // selected, in Flash blue.
    static final float KO_EM = 36.0f;       // letter size, design units
    static final float KO_PAD = 5.0f;       // text to box
    static final float KO_M = 6.0f;         // box to window edge: room for the halo and the handle
    static final float KO_ABOVE = 36.0f;    // the bottom of the box, down from the top of his sprite

    private Path[] koPaths;
    private final RectF koBox = new RectF();
    int kow, koh;
    private final Paint koInk = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint koHalo = stroke(4.5f), koRim = stroke(3.0f), koLine = stroke(1.0f), koBlue = stroke(1.3f);

    // the text as it stands after each letter, all on the same baseline
    private void newKoArt() {
        Paint tp = new Paint(Paint.ANTI_ALIAS_FLAG);
        tp.setTypeface(Typeface.create("sans-serif-black", Typeface.NORMAL));
        tp.setTextSize(KO_EM);
        String text = Stick.KO_TEXT;
        koPaths = new Path[text.length() + 1];
        for (int i = 0; i <= text.length(); i++) {
            Path p = new Path();
            if (i > 0) tp.getTextPath(text, 0, i, 0, 0, p);
            koPaths[i] = p;
        }
        koPaths[text.length()].computeBounds(koBox, true);   // all of it, once it is typed
        kow = (int) Math.ceil((koBox.width() + 2 * KO_PAD + 2 * KO_M) * sc);
        koh = (int) Math.ceil((koBox.height() + 2 * KO_PAD + 2 * KO_M) * sc);
        koInk.setColor(DARK);
        koHalo.setColor(0xFFFFFFFF);
        koRim.setColor(0xC8FFFFFF);
        koRim.setStrokeCap(Paint.Cap.BUTT);
        koLine.setColor(DARK);
        koLine.setStrokeCap(Paint.Cap.BUTT);
        koBlue.setColor(FLASH_BLUE);
    }

    // n letters typed so far, in their box: being edited, with the handle and
    // maybe the caret, or selected, in blue
    void koText(Canvas c, int n, boolean caret, boolean selected) {
        c.save();
        c.scale(sc, sc);
        float w = 0;
        if (n > 0) { koPaths[n].computeBounds(rect, true); w = rect.right - koBox.left; }
        float bx = KO_M, by = KO_M;
        float bw = w + 2 * KO_PAD, bh = koBox.height() + 2 * KO_PAD;
        c.drawRect(bx, by, bx + bw, by + bh, koRim);
        c.drawRect(bx, by, bx + bw, by + bh, selected ? koBlue : koLine);
        if (!selected) {
            // the round handle of a text box that grows as you type
            float r = 2.6f;
            fill.setColor(0xFFFFFFFF);
            c.drawCircle(bx + bw, by, r, fill);
            c.drawCircle(bx + bw, by, r, koLine);
        }
        c.translate(KO_M + KO_PAD - koBox.left, KO_M + KO_PAD - koBox.top);
        if (n > 0) {
            c.drawPath(koPaths[n], koHalo);
            c.drawPath(koPaths[n], koInk);
        }
        if (caret) {
            float cx = koBox.left + w + 2.6f;
            c.drawLine(cx, koBox.top - 1.5f, cx, koBox.bottom + 1.5f, koRim);
            c.drawLine(cx, koBox.top - 1.5f, cx, koBox.bottom + 1.5f, koLine);
        }
        c.restore();
    }

    // ----------------------------------------------------------------- panels
    // a Flash panel: a tool window's title bar, then its rows (New-PropImage)
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);

    void panel(Canvas c, Panel pr, int w, int h) {
        float k = (float) (sc * Panel.K);
        float uw = w / k, uh = h / k;           // Windows design units from here on
        c.save();
        c.scale(k, k);
        fill.setColor(0xFFEEEEEE);
        c.drawRect(0, 0, uw, uh, fill);
        float title = (float) (Panel.TITLE / Panel.K);
        fill.setColor(0xFFFFFFFF);
        c.drawRect(0, 0, uw, title, fill);
        text.setColor(0xFF000000);
        text.setTextSize(12f);
        text.setTypeface(Typeface.DEFAULT);
        c.drawText(Panel.TITLES[pr.kind], 8, title * 0.68f, text);
        thin.setColor(0xFF000000); thin.setStrokeWidth(1.1f);
        float xx = uw - 14, xy = title / 2;
        c.drawLine(xx - 4, xy - 4, xx + 4, xy + 4, thin);
        c.drawLine(xx - 4, xy + 4, xx + 4, xy - 4, thin);

        float rowH = 22, pad = 6;
        String[] rows = Panel.ROWS[pr.kind];
        for (int i = 0; i < rows.length; i++) {
            float y = title + pad + i * rowH;
            if (i % 2 == 0) { fill.setColor(0xFFFAFAFA); c.drawRect(pad, y, uw - pad, y + rowH, fill); }
            fill.setColor(FLASH_BLUE);
            c.drawRect(pad * 2, y + rowH * 0.3f, pad * 2 + rowH * 0.4f, y + rowH * 0.7f, fill);
            c.drawText(rows[i], pad * 3 + rowH * 0.4f, y + rowH * 0.7f, text);
        }
        thin.setColor(0xFF8A8A8A); thin.setStrokeWidth(1.0f);
        c.drawRect(0.5f, 0.5f, uw - 0.5f, uh - 0.5f, thin);
        c.restore();
    }

    // -------------------------------------------------------------- the arrow
    // The pointer's window, with its tip at (TIP_X, TIP_Y) design units, and
    // room under it for the bar that shows how many hits it has left.
    static final float PTR_BOX = 64, TIP_X = 16, TIP_Y = 8;

    private final Paint arrowFill = new Paint(Paint.ANTI_ALIAS_FLAG), arrowEdge = stroke(1.2f);

    // the arrow with its tip at (0, 0), in design units
    private void arrowPath() {
        float k = Pointer.ARROW;
        float[] xy = Pointer.ARROW_XY;
        path.rewind();
        for (int i = 0; i < xy.length; i += 2) {
            if (i == 0) path.moveTo(xy[i] * k, xy[i + 1] * k); else path.lineTo(xy[i] * k, xy[i + 1] * k);
        }
        path.close();
    }

    private void arrow(Canvas c, ColorMatrixColorFilter tint) {
        arrowPath();
        arrowFill.setColor(0xFFFFFFFF);
        arrowFill.setColorFilter(tint);
        arrowEdge.setColor(0xFF000000);
        arrowEdge.setColorFilter(tint);
        arrowEdge.setStrokeWidth(1.2f * Pointer.ARROW);
        c.drawPath(path, arrowFill);
        c.drawPath(path, arrowEdge);
    }

    void pointer(Canvas c, Pointer p) {
        c.save();
        c.scale(sc, sc);
        c.save();
        c.translate(TIP_X, TIP_Y);
        arrow(c, null);
        c.restore();
        if (p.bar > 0) {
            // blue, going red when it is nearly done for, fading at the end
            int a = (int) (255 * Math.min(1.0, p.bar / 12.0));
            boolean low = p.hp <= p.max * 0.34;
            float x0 = TIP_X - 11, y0 = TIP_Y + 38, bw = 34, bh = 6;
            fill.setColor(argb(a, 0xFFFFFF));
            c.drawRect(x0, y0, x0 + bw, y0 + bh, fill);
            fill.setColor(argb(a, low ? 0x5A1818 : 0x103054));
            c.drawRect(x0 + 1, y0 + 1, x0 + bw - 1, y0 + bh - 1, fill);
            fill.setColor(argb(a, low ? 0xE83434 : FLASH_BLUE));
            c.drawRect(x0 + 1, y0 + 1, x0 + 1 + (bw - 2) * (float) (Math.max(0.0, p.shown) / p.max), y0 + bh - 1, fill);
        }
        c.restore();
    }

    // -------------------------------------------------------------- the wreck
    private final Path tri = new Path();

    void wreck(Canvas c, Pointer p, Random rng) {
        int glow = p.glow();
        if (glow >= 0) { mended(c, p, glow); return; }
        float k = Pointer.ARROW * sc;
        for (Pointer.Shard sh : p.shards) {
            double[] at = p.shardPose(sh, rng);
            c.save();
            c.translate((float) (at[0] - p.wx), (float) (at[1] - p.wy));
            c.rotate((float) at[2]);
            c.translate((float) -sh.px, (float) -sh.py);
            tri.rewind();
            tri.moveTo(sh.tri[0], sh.tri[1]);
            tri.lineTo(sh.tri[2], sh.tri[3]);
            tri.lineTo(sh.tri[4], sh.tri[5]);
            tri.close();
            c.clipPath(tri);
            // the picture: the arrow, its tip a little in from the corner
            c.scale(k, k);
            c.translate(Pointer.ARROW_PAD, Pointer.ARROW_PAD);
            c.scale(1 / Pointer.ARROW, 1 / Pointer.ARROW);
            arrow(c, null);
            c.restore();
        }
    }

    // whole again: it flashes blue-white and fades back to itself, and a ring
    // goes out from it
    private void mended(Canvas c, Pointer p, int n) {
        float k = 1f - n / (float) Pointer.GLOW_LEN;
        ColorMatrix cm = new ColorMatrix(new float[] {
            1 - k, 0, 0, 0, 0.55f * k * 255,
            0, 1 - k, 0, 0, 0.8f * k * 255,
            0, 0, 1 - k, 0, k * 255,
            0, 0, 0, 1, 0,
        });
        ColorMatrixColorFilter tint = new ColorMatrixColorFilter(cm);
        float ix = p.bx - p.hx - p.wx, iy = p.by - p.hy - p.wy;
        float ak = Pointer.ARROW * sc;
        c.save();
        c.translate(ix, iy);
        c.scale(ak, ak);
        c.translate(Pointer.ARROW_PAD, Pointer.ARROW_PAD);
        c.scale(1 / Pointer.ARROW, 1 / Pointer.ARROW);
        arrow(c, tint);
        c.restore();
        float r = (6 + 34 * (1 - k)) * sc;
        float mx = ix + p.cx, my = iy + p.cy;
        int a = (int) (255 * k);
        thin.setColor(argb(a, 0xFFFFFF)); thin.setStrokeWidth(4 * sc);
        c.drawCircle(mx, my, r, thin);
        thin.setColor(argb(a, FLASH_BLUE)); thin.setStrokeWidth(2 * sc);
        c.drawCircle(mx, my, r, thin);
    }
}
