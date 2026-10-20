package com.desktopstickman;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.PixelFormat;
import android.os.Build;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.PointerIcon;
import android.view.View;
import android.view.WindowManager;

// One window floating over every app: him, a spark, the K.O., a panel, your
// pointer, the pieces of it. The Windows version gives each of these a
// layered window of its own; so does this. Ones that take no touches let them
// fall straight through to whatever is underneath.
final class Win extends View {
    interface Painter { void paint(Canvas c); }
    interface Touch { boolean touch(MotionEvent e); }

    private final WindowManager wm;
    private final WindowManager.LayoutParams lp;
    private boolean added;
    Painter painter;
    Touch touch;
    Touch hover;                        // a mouse, touchpad or pen moving over it, nothing pressed

    Win(Context ctx, WindowManager wm, int w, int h, boolean touchable) {
        super(ctx);
        this.wm = wm;
        int flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                  | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                  | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                  | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
        if (!touchable) flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE;
        lp = new WindowManager.LayoutParams(Math.max(1, w), Math.max(1, h),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, flags, PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        lp.setTitle("Stickman");
        // Android only lets a tap through to the app underneath a window like
        // this if the window is at most 80% opaque
        if (!touchable) lp.alpha = 0.8f;
        if (Build.VERSION.SDK_INT >= 30) {
            // the whole screen is his, status bar and cutout included, in screen coordinates
            lp.setFitInsetsTypes(0);
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
        } else if (Build.VERSION.SDK_INT >= 28) {
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
    }

    // fully opaque after all: for a window that only ever sits over the fight
    // arena, which is his, so it blocks nobody's taps
    void opaque() { lp.alpha = 1f; }

    // no system cursor over it: in a fight, his arrow is the cursor
    private boolean noCursor;
    void hideCursor(boolean hide) {
        if (hide == noCursor) return;
        noCursor = hide;
        setPointerIcon(hide ? PointerIcon.getSystemIcon(getContext(), PointerIcon.TYPE_NULL) : null);
    }

    // top-left corner on screen, shown
    void place(int x, int y) {
        if (getVisibility() != VISIBLE) setVisibility(VISIBLE);
        if (!added) {
            lp.x = x; lp.y = y;
            try { wm.addView(this, lp); added = true; } catch (RuntimeException e) { Log.trail("window", e); }
        } else if (lp.x != x || lp.y != y) {
            lp.x = x; lp.y = y;
            wm.updateViewLayout(this, lp);
        }
        invalidate();
    }

    void resize(int w, int h) {
        w = Math.max(1, w); h = Math.max(1, h);
        if (lp.width == w && lp.height == h) return;
        lp.width = w; lp.height = h;
        if (added) wm.updateViewLayout(this, lp);
    }

    // out of sight, and out of the way of every touch, but kept for next time
    void hide() {
        if (added && getVisibility() != GONE) setVisibility(GONE);
    }

    void close() {
        if (!added) return;
        try { wm.removeViewImmediate(this); } catch (RuntimeException ignored) { }
        added = false;
    }

    @Override protected void onDraw(Canvas c) {
        if (painter != null) painter.paint(c);
    }

    @Override public boolean onTouchEvent(MotionEvent e) {
        return touch != null && touch.touch(e);
    }

    @Override public boolean onHoverEvent(MotionEvent e) {
        return hover != null ? hover.touch(e) : super.onHoverEvent(e);
    }
}
