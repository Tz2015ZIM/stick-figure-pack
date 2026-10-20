package com.desktopstickman;

import android.accessibilityservice.AccessibilityService;
import android.graphics.Rect;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

// What lets him see what is on screen, if you switch it on in Accessibility
// settings: the phone's stand-in for EnumWindows, the UI Automation scanner
// and the desktop list view on Windows. It finds
//
//   * windows that do not fill the screen - dialogs, either half of a split
//     screen, a picture-in-picture video - and the keyboard, to stand on
//   * buttons, check boxes, switches and anything else you can tap in the app
//     in front, to climb and stamp on
//   * the app icons on the home screen, to stamp on (and open, once in a while)
//   * the things you tap, so he can run over and look
//
// It only ever reads. The one thing it can do is press a button he is
// standing on, and only with "Let him press buttons for real" ticked.
public final class Eyes extends AccessibilityService {
    static volatile Eyes me;
    private static volatile Ledge[] seen = new Ledge[0];

    private HandlerThread th;
    private Handler bg;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Map<Long, AccessibilityNodeInfo> nodes = new HashMap<>();     // buttons, worker thread only
    private boolean queued;

    static final int BTN_CAP = 40;
    static final int NODE_CAP = 2500;   // never walk more of an app than this in one look

    static Ledge[] seen() {
        return me != null ? seen : new Ledge[0];
    }

    @Override protected void onServiceConnected() {
        th = new HandlerThread("stickman-eyes");
        th.start();
        bg = new Handler(th.getLooper());
        me = this;
        bg.post(look);
    }

    @Override public boolean onUnbind(android.content.Intent i) {
        stop();
        return super.onUnbind(i);
    }

    @Override public void onDestroy() {
        stop();
        super.onDestroy();
    }

    private void stop() {
        me = null;
        seen = new Ledge[0];
        if (th != null) { th.quitSafely(); th = null; }
    }

    @Override public void onInterrupt() { }

    @Override public void onAccessibilityEvent(AccessibilityEvent e) {
        if (StickService.me == null) return;
        switch (e.getEventType()) {
            case AccessibilityEvent.TYPE_VIEW_CLICKED: {
                // you tapped something: he runs over to look
                CharSequence pkg = e.getPackageName();
                if (pkg != null && getPackageName().contentEquals(pkg)) return;
                AccessibilityNodeInfo n = e.getSource();
                if (n == null) return;
                Rect b = new Rect();
                n.getBoundsInScreen(b);
                if (b.isEmpty()) return;
                final float x = b.exactCenterX(), y = b.exactCenterY();
                main.post(() -> { StickService s = StickService.me; if (s != null) s.tapped(x, y); });
                soon(150);
                break;
            }
            case AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED:
            case AccessibilityEvent.TYPE_WINDOWS_CHANGED:
            case AccessibilityEvent.TYPE_VIEW_SCROLLED:
                soon(80);
                break;
            case AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED:
                soon(300);
                break;
        }
    }

    // look again shortly; a burst of events makes one look, not dozens
    private void soon(long ms) {
        Handler b = bg;
        if (b == null || queued) return;
        queued = true;
        b.postDelayed(() -> { queued = false; scan(); }, ms);
    }

    // ...and in any case about once a second, while he is about
    private final Runnable look = new Runnable() {
        @Override public void run() {
            scan();
            Handler b = bg;
            if (b != null) b.postDelayed(this, 900);
        }
    };

    private void scan() {
        StickService svc = StickService.me;
        if (svc == null) { seen = new Ledge[0]; nodes.clear(); return; }
        try {
            seen = find(svc);
        } catch (RuntimeException e) {
            Log.trail("eyes", e);
            seen = new Ledge[0];
        }
    }

    private Ledge[] find(StickService svc) {
        Room room = svc.room;
        float sc = room.sc;
        int sw = room.scrR - room.scrL, sh = room.scrB - room.scrT;
        String home = svc.homePackage;
        String self = getPackageName();

        List<Ledge> wins = new ArrayList<>(), btns = new ArrayList<>(), icons = new ArrayList<>();
        Map<Long, AccessibilityNodeInfo> found = new HashMap<>();
        Rect r = new Rect();
        int[] budget = { NODE_CAP };

        // front to back
        for (AccessibilityWindowInfo w : getWindows()) {
            int type = w.getType();
            w.getBoundsInScreen(r);
            if (type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) {
                // the keyboard: while it is up, its top is the ground
                if (!r.isEmpty()) wins.add(Ledge.keyboard(id(1, w.getId(), 0), r.left, r.top, r.right, r.bottom));
                continue;
            }
            if (type != AccessibilityWindowInfo.TYPE_APPLICATION) continue;
            AccessibilityNodeInfo root = w.getRoot();
            if (root == null) continue;
            CharSequence pkg = root.getPackageName();
            if (pkg != null && self.contentEquals(pkg)) continue;      // his own menu
            boolean full = r.width() >= sw - 4 * sc && r.height() >= sh * 0.8;
            if (!full && r.width() >= 100 * sc && r.height() >= 60 * sc) {
                wins.add(Ledge.window(id(1, w.getId(), 0), r.left, r.top, r.right, r.bottom, false));
            }
            boolean launcher = home != null && pkg != null && home.contentEquals(pkg);
            walk(root, w.getId(), launcher, pkg, sc, svc, btns, icons, found, budget);
        }

        synchronized (nodes) { nodes.clear(); nodes.putAll(found); }
        List<Ledge> all = new ArrayList<>(wins.size() + btns.size() + icons.size());
        all.addAll(wins); all.addAll(btns); all.addAll(icons);
        return all.toArray(new Ledge[0]);
    }

    // the same thing seen twice gets the same id, so he can ride it as it scrolls
    private static long id(int kind, int window, int node) {
        return ((long) kind << 56) | ((long) (window & 0xFFFFFF) << 32) | (node & 0xFFFFFFFFL);
    }

    private void walk(AccessibilityNodeInfo root, int win, boolean launcher, CharSequence pkg, float sc,
                      StickService svc, List<Ledge> btns, List<Ledge> icons,
                      Map<Long, AccessibilityNodeInfo> found, int[] budget) {
        int minW = (int) (26 * sc), minH = (int) (14 * sc), maxW = (int) (420 * sc), maxH = (int) (80 * sc);
        boolean system = pkg != null && "com.android.systemui".contentEquals(pkg);
        Rect b = new Rect();
        ArrayDeque<AccessibilityNodeInfo> todo = new ArrayDeque<>();
        todo.add(root);
        while (!todo.isEmpty() && budget[0]-- > 0) {
            AccessibilityNodeInfo n = todo.poll();
            if (!n.isVisibleToUser()) continue;
            n.getBoundsInScreen(b);

            if (launcher && n.isClickable()) {
                // an app icon: the picture is the square at the top of its cell
                CharSequence t = n.getText();
                if (t == null || t.length() == 0) t = n.getContentDescription();
                if (t != null && svc.isApp(t.toString())) {
                    int side = (int) (Math.min(b.width(), b.height()) * 0.8f);
                    int cx = b.centerX();
                    icons.add(Ledge.appIcon(id(3, win, n.hashCode()), cx - side / 2, b.top, cx + side / 2,
                                            b.top + side, t.toString()));
                    continue;
                }
            }

            if (btns.size() < BTN_CAP && !system && n.isEnabled() && (n.isClickable() || isButton(n))) {
                int w = b.width(), h = b.height();
                if (w >= minW && h >= minH && w <= maxW && h <= maxH) {
                    long k = id(2, win, n.hashCode());
                    btns.add(Ledge.button(k, b.left, b.top, b.right, b.bottom));
                    found.put(k, n);
                }
            }

            for (int i = 0; i < n.getChildCount(); i++) {
                AccessibilityNodeInfo c = n.getChild(i);
                if (c != null) todo.add(c);
            }
        }
    }

    // push-buttons, check boxes, radio buttons, switches: whatever the app says
    // is a button, Compose and web pages included. On a phone almost anything
    // you can tap counts too (a row in a list, a tab, a card), so he gets about
    // the way he does among the buttons of a Windows dialog, and rides a list
    // as you scroll it.
    private static boolean isButton(AccessibilityNodeInfo n) {
        CharSequence c = n.getClassName();
        if (c == null) return false;
        String s = c.toString();
        return s.endsWith("Button") || s.endsWith("CheckBox") || s.endsWith("Switch") || n.isCheckable();
    }

    // he stamped on a button and you have let him really press it: only if it
    // is still there, just where he stood on it
    void press(Ledge l) {
        Handler b = bg;
        if (b == null) return;
        b.post(() -> {
            AccessibilityNodeInfo n;
            synchronized (nodes) { n = nodes.get(l.h); }
            if (n == null || !n.refresh() || !n.isEnabled() || !n.isVisibleToUser()) return;
            Rect r = new Rect();
            n.getBoundsInScreen(r);
            if (Math.abs(r.left - l.l) < 3 && Math.abs(r.top - l.t) < 3 && Math.abs(r.right - l.r) < 3) {
                n.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
        });
    }
}
