package com.desktopstickman;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.pm.ServiceInfo;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.WindowMetrics;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

// Where they all live: a foreground service that holds the Room, runs the
// frame loop the Windows timer runs (every 30 ms), and keeps a floating window
// for each of them and for everything they make. Its notification stands in
// for the tray icon.
public final class StickService extends Service implements Room.Hands {
    static final String ADD = "add", WAVE = "wave", QUIT_ALL = "quitAll", STOP_FIGHTS = "stopFights";
    static final int FRAME_MS = 30;
    private static final String CHANNEL = "stickman";
    private static final int NOTE_ID = 1;

    static volatile StickService me;

    Room room;
    private Art art;
    private Context ui;                 // what his windows are made with
    private WindowManager wm;
    private boolean populated;          // he has been on screen: once they are all gone, so is this
    private final Handler h = new Handler(Looper.getMainLooper());
    private boolean running;
    private long next;
    private SharedPreferences prefs;
    private String note = "";

    // everything of his on screen
    private final class Body {
        final Stick s;
        final Win win;
        Win spark, ko;
        final Map<Panel, Win> panels = new IdentityHashMap<>();
        final Figure.Pose pose = new Figure.Pose();
        Body(Stick s) {
            this.s = s;
            win = new Win(ui, wm, s.BOXW, s.BOXH, true);
            win.painter = c -> art.figure(c, pose);
            win.touch = new Touchy(s);
            win.hover = StickService.this::arenaHover;     // the mouse over him still moves your pointer
        }
    }
    private final Map<Stick, Body> bodies = new IdentityHashMap<>();
    private Win ptrWin, ptrSpark, wreckWin;

    // The fight arena: an invisible window over the whole screen while anyone
    // is fighting, so your pointer can be wherever your finger comes down, or
    // wherever the mouse cursor is. A phone only tells an app where you touch
    // (or where the mouse is) over its own windows, so in a fight taps go to
    // the fight and not to your apps. It steps aside while his menu or one of
    // his dialogs is open (uiOpen), which it would otherwise cover.
    private Win arena;
    private Win.Touch arenaTarget;      // whoever the finger now on the arena belongs to
    private int uiOpen;

    // label of every app on the home screen -> how to open it
    private volatile Map<String, Intent> apps = new HashMap<>();
    volatile String homePackage;

    @Override public IBinder onBind(Intent i) { return null; }

    @Override public void onCreate() {
        super.onCreate();
        Log.file = new File(getFilesDir(), "stickman-error.log");
        ui = this;
        if (Build.VERSION.SDK_INT >= 30) {
            // a context made for overlay windows, so they follow the screen as it turns
            Display d = getSystemService(DisplayManager.class).getDisplay(Display.DEFAULT_DISPLAY);
            ui = createDisplayContext(d).createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null);
        }
        wm = ui.getSystemService(WindowManager.class);
        float sc = getResources().getDisplayMetrics().density;
        room = new Room(sc);
        room.hands = this;
        art = new Art(sc);
        measure();
        prefs = getSharedPreferences("stickman", MODE_PRIVATE);
        room.open    = prefs.getBoolean("open", true);
        room.click   = prefs.getBoolean("click", false);
        room.throwOk = prefs.getBoolean("throw", true);
        room.grabPtr = prefs.getBoolean("grab", true);
        room.killPtr = prefs.getBoolean("kill", true);

        NotificationManager nm = getSystemService(NotificationManager.class);
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Stickman", NotificationManager.IMPORTANCE_MIN);
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
        goForeground(3);

        IntentFilter f = new IntentFilter();
        f.addAction(Intent.ACTION_SCREEN_OFF);
        f.addAction(Intent.ACTION_SCREEN_ON);
        f.addAction(Intent.ACTION_USER_PRESENT);
        registerReceiver(screen, f);

        me = this;
        new Thread(this::findApps, "stickman-apps").start();
        start();
    }

    // A foreground service, so the phone leaves him running. When the phone
    // brings him back by itself after stopping him, Android 15 only allows it
    // once one of his windows is on screen, so then it waits for the first one.
    private boolean foreground() {
        try {
            Notification n = notification();
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTE_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            else startForeground(NOTE_ID, n);
            return true;
        } catch (RuntimeException e) {
            Log.trail("foreground", e);
            return false;
        }
    }

    private void goForeground(int tries) {
        if (foreground()) return;
        if (tries > 0) h.postDelayed(() -> goForeground(tries - 1), 500);
        else stopSelf();
    }

    @Override public int onStartCommand(Intent i, int flags, int id) {
        String a = i != null ? i.getAction() : null;
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return START_NOT_STICKY; }
        foreground();       // every start asks for it again; if it is refused now, goForeground is still trying
        if (QUIT_ALL.equals(a)) { quitAll(); return START_NOT_STICKY; }
        if (WAVE.equals(a)) { for (Stick s : room.sticks) s.waveAtYou(); }
        else if (STOP_FIGHTS.equals(a)) { for (Stick s : new ArrayList<>(room.sticks)) if (s.f.on) s.endFight(); }
        else if (ADD.equals(a) || room.sticks.isEmpty()) add();
        // if the phone runs short of memory and stops him, he comes back when it can
        return START_STICKY;
    }

    @Override public void onDestroy() {
        me = null;
        running = false;
        h.removeCallbacksAndMessages(null);
        try { unregisterReceiver(screen); } catch (RuntimeException ignored) { }
        for (Body b : bodies.values()) closeBody(b);
        bodies.clear();
        for (Win w : new Win[] { ptrWin, ptrSpark, wreckWin, arena }) if (w != null) w.close();
        super.onDestroy();
    }

    @Override public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        measure();      // turned on its side: the ground moves
    }

    // the screen, and the part of it inside the status and navigation bars
    private void measure() {
        Rect b;
        Rect in = new Rect();
        if (Build.VERSION.SDK_INT >= 30) {
            WindowMetrics m = wm.getMaximumWindowMetrics();
            b = m.getBounds();
            Insets i = m.getWindowInsets().getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            in.set(i.left, i.top, i.right, i.bottom);
        } else {
            DisplayMetrics dm = new DisplayMetrics();
            wm.getDefaultDisplay().getRealMetrics(dm);
            b = new Rect(0, 0, dm.widthPixels, dm.heightPixels);
            in.top = dimen("status_bar_height");
            if (dm.heightPixels > dm.widthPixels) in.bottom = dimen("navigation_bar_height");
            else in.right = dimen("navigation_bar_height_landscape");
        }
        room.setScreen(b.left, b.top, b.right, b.bottom,
                       b.left + in.left, b.top + in.top, b.right - in.right, b.bottom - in.bottom);
    }

    private int dimen(String name) {
        int id = getResources().getIdentifier(name, "dimen", "android");
        return id > 0 ? getResources().getDimensionPixelSize(id) : 0;
    }

    // ------------------------------------------------------------- the loop
    private final Runnable frame = new Runnable() {
        @Override public void run() {
            if (!running) return;
            long now = SystemClock.uptimeMillis();
            if (room.frame % 60 == 0) measure();       // the screen turned, or a bar came or went
            room.seen = Eyes.seen();
            room.step();
            try { draw(); } catch (RuntimeException e) { Log.trail("draw", e); }
            if (populated && room.sticks.isEmpty()) { stopSelf(); return; }
            next += FRAME_MS;
            if (next < now) next = now + FRAME_MS;      // fell behind: no catching up in a rush
            h.postAtTime(this, next);
        }
    };

    private void start() {
        if (running) return;
        running = true;
        next = SystemClock.uptimeMillis();
        h.post(frame);
    }

    private void pause() {
        running = false;
        h.removeCallbacks(frame);
    }

    // the screen going off stops him (and his battery use); coming back to
    // the phone, they all wave at you
    private final BroadcastReceiver screen = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            String a = i.getAction();
            if (Intent.ACTION_SCREEN_OFF.equals(a)) pause();
            else if (Intent.ACTION_SCREEN_ON.equals(a)) start();
            else if (Intent.ACTION_USER_PRESENT.equals(a)) { start(); for (Stick s : room.sticks) s.waveAtYou(); }
        }
    };

    // ----------------------------------------------------------- the windows
    private void draw() {
        Pointer p = room.ptr;
        for (Body b : new ArrayList<>(bodies.values())) {
            Stick s = b.s;
            if (!room.sticks.contains(s)) { closeBody(b); bodies.remove(s); continue; }
            Figure.pose(s, b.pose);
            b.win.setAlpha(s.alpha());
            b.win.hideCursor(p.up);
            b.win.place((int) Math.round(s.x - s.CX), (int) Math.round(s.y - s.FOOT));

            if (s.f.spark.on()) {
                if (b.spark == null) b.spark = sparkWin(s.f.spark);
                int fxw = art.sparkSize();
                b.spark.place((int) (s.f.spark.x - fxw / 2), (int) (s.f.spark.y - fxw / 2));
            } else if (b.spark != null) b.spark.hide();

            if (s.koT >= 0) {
                if (b.ko == null) {
                    b.ko = new Win(ui, wm, art.kow, art.koh, false);
                    b.ko.painter = c -> art.koText(c, s.koLetters(), s.koCaret(), s.koSelected());
                }
                int x = (int) Math.max(room.scrL, Math.min(room.scrR - art.kow, s.x - art.kow / 2.0));
                int y = (int) Math.max(room.scrT, s.y - s.FOOT + (Art.KO_ABOVE + Art.KO_M) * room.sc - art.koh);
                b.ko.setAlpha(s.gone > 0 ? s.gone / (float) Stick.GONE_LEN : 1f);
                b.ko.place(x, y);
            } else if (b.ko != null) b.ko.hide();

            // his panels: one window each, while they last
            for (Map.Entry<Panel, Win> e : new ArrayList<>(b.panels.entrySet())) {
                if (!s.props.contains(e.getKey())) { e.getValue().close(); b.panels.remove(e.getKey()); }
            }
            for (Panel pr : s.props) {
                Win w = b.panels.get(pr);
                if (w == null) {
                    w = new Win(ui, wm, (int) pr.w, (int) pr.h, false);
                    final Panel at = pr;
                    final Win self = w;
                    w.painter = c -> art.panel(c, at, self.getWidth(), self.getHeight());
                    b.panels.put(pr, w);
                }
                w.place((int) Math.round(pr.x), (int) Math.round(pr.y));
            }
        }

        // the arena, under the pointer, while there is a fight
        if (p.up && uiOpen == 0) {
            if (arena == null) {
                arena = new Win(ui, wm, room.scrR - room.scrL, room.scrB - room.scrT, true);
                arena.touch = this::arenaTouch;
                arena.hover = this::arenaHover;
                arena.hideCursor(true);
            }
            arena.resize(room.scrR - room.scrL, room.scrB - room.scrT);
            arena.place(room.scrL, room.scrT);
        } else if (arena != null) arena.hide();

        // your pointer, while somebody is fighting it and it is in one piece;
        // the arena takes the taps for it
        int box = Math.round(Art.PTR_BOX * room.sc);
        if (p.up && !p.dead) {
            if (ptrWin == null) {
                ptrWin = new Win(ui, wm, box, box, false);
                ptrWin.opaque();
                ptrWin.painter = c -> art.pointer(c, room.ptr);
            }
            ptrWin.place(Math.round(p.x - Art.TIP_X * room.sc), Math.round(p.y - Art.TIP_Y * room.sc));
        } else if (ptrWin != null) ptrWin.hide();

        if (p.spark.on()) {
            if (ptrSpark == null) ptrSpark = sparkWin(p.spark);
            int fxw = art.sparkSize();
            ptrSpark.place((int) (p.spark.x - fxw / 2), (int) (p.spark.y - fxw / 2));
        } else if (ptrSpark != null) ptrSpark.hide();

        // ...and the pieces of it. A tap on them mends it sooner.
        if (p.dead) {
            if (wreckWin == null) {
                wreckWin = new Win(ui, wm, (int) p.ww, (int) p.wh, true);
                wreckWin.painter = c -> art.wreck(c, room.ptr, room.rng);
                wreckWin.touch = e -> {
                    if (e.getActionMasked() == MotionEvent.ACTION_DOWN) room.ptr.hurry = true;
                    return true;
                };
                wreckWin.hover = this::arenaHover;
                wreckWin.hideCursor(true);
            }
            wreckWin.resize((int) p.ww, (int) p.wh);
            wreckWin.place(Math.round(p.wx), Math.round(p.wy));
        } else if (wreckWin != null) wreckWin.hide();

        updateNote();
    }

    private Win sparkWin(Spark sp) {
        int fxw = art.sparkSize();
        Win w = new Win(ui, wm, fxw, fxw, false);
        w.painter = c -> art.spark(c, sp);
        return w;
    }

    private void closeBody(Body b) {
        b.win.close();
        if (b.spark != null) b.spark.close();
        if (b.ko != null) b.ko.close();
        for (Win w : b.panels.values()) w.close();
        b.panels.clear();
    }

    // a finger on him: drag him about, tap him for a jump (a hit, in a fight),
    // or hold him for his menu
    private final class Touchy implements Win.Touch, Runnable {
        final Stick s;
        float downX, downY;
        boolean held;
        Touchy(Stick s) { this.s = s; }

        @Override public boolean touch(MotionEvent e) {
            float x = e.getRawX(), y = e.getRawY();
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = x; downY = y; held = false;
                    s.touchDown(x, y);
                    hover(true, x, y);
                    h.postDelayed(this, ViewConfiguration.getLongPressTimeout());
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (held) return true;
                    s.touchMove(x, y);
                    hover(true, x, y);
                    float slop = ViewConfiguration.get(StickService.this).getScaledTouchSlop();
                    if (Math.abs(x - downX) > slop || Math.abs(y - downY) > slop) h.removeCallbacks(this);
                    return true;
                case MotionEvent.ACTION_UP:
                    h.removeCallbacks(this);
                    hover(false, x, y);
                    if (!held) s.touchUp(x, y);
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    h.removeCallbacks(this);
                    hover(false, x, y);
                    s.touchCancel();
                    return true;
            }
            return false;
        }

        // held still long enough: his menu (right-click on Windows)
        @Override public void run() {
            held = true;
            s.touchCancel();
            openMenu(s.slot);
        }
    }

    // A finger (or a click) came down on the arena: on one of them, whose
    // window it may cover, it is his, to drag or hit; anywhere else it is your
    // pointer's. The rest of that touch goes the same way.
    private boolean arenaTouch(MotionEvent e) {
        if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
            float x = e.getRawX(), y = e.getRawY();
            arenaTarget = this::pointerTouch;
            for (int i = room.sticks.size() - 1; i >= 0; i--) {
                Stick s = room.sticks.get(i);
                double l = s.x - s.CX, t = s.y - s.FOOT;
                Body b = bodies.get(s);
                if (b != null && x >= l && x < l + s.BOXW && y >= t && y < t + s.BOXH) { arenaTarget = b.win.touch; break; }
            }
        }
        return arenaTarget != null && arenaTarget.touch(e);
    }

    // a mouse, touchpad or pen moving over the screen with nothing pressed:
    // in a fight, your pointer goes where its cursor goes
    private boolean arenaHover(MotionEvent e) {
        if (!room.ptr.up) return false;
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_HOVER_ENTER:
            case MotionEvent.ACTION_HOVER_MOVE:
                room.ptr.hover(e.getRawX(), e.getRawY());
                hover(true, e.getRawX(), e.getRawY());
                return true;
            case MotionEvent.ACTION_HOVER_EXIT:
                room.ptr.hoverGone();
                hover(false, e.getRawX(), e.getRawY());
                return true;
        }
        return false;
    }

    // his menu and dialogs are over his windows only while the arena is out of the way
    void uiShown(boolean on) {
        uiOpen = Math.max(0, uiOpen + (on ? 1 : -1));
        if (on && arena != null) arena.hide();
    }

    private boolean pointerTouch(MotionEvent e) {
        float x = e.getRawX(), y = e.getRawY();
        Pointer p = room.ptr;
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: p.fingerDown(x, y); hover(true, x, y); return true;
            case MotionEvent.ACTION_MOVE: p.fingerMove(x, y); hover(true, x, y); return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL: p.fingerUp(x, y); hover(false, x, y); return true;
        }
        return false;
    }

    private void hover(boolean on, float x, float y) {
        room.hover = on; room.hoverX = x; room.hoverY = y;
    }

    // ---------------------------------------------------------- his menu etc.
    void openMenu(int slot) {
        Intent i = new Intent(this, MenuActivity.class)
            .putExtra("slot", slot)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        try { startActivity(i); } catch (RuntimeException e) { Log.trail("menu", e); }
    }

    Stick add() {
        Stick s = room.add();
        if (s == null) return null;
        bodies.put(s, new Body(s));
        populated = true;
        start();
        return s;
    }

    void quit(Stick s) {
        room.remove(s);
        Body b = bodies.remove(s);
        if (b != null) closeBody(b);
        if (room.sticks.isEmpty()) stopSelf();
    }

    void quitAll() {
        for (Stick s : new ArrayList<>(room.sticks)) quit(s);
        stopSelf();
    }

    void setting(String key, boolean on) {
        switch (key) {
            case "open":  room.open = on; break;
            case "click": room.click = on; break;
            case "throw": room.throwOk = on; break;
            case "grab":  room.grabPtr = on; if (!on) for (Stick s : room.sticks) s.releasePointer(); break;
            case "kill":  room.killPtr = on; break;
        }
        prefs.edit().putBoolean(key, on).apply();
    }

    // the notification lists them by the names they go by, the way Task
    // Manager lists his processes on Windows
    private String names() {
        StringBuilder sb = new StringBuilder();
        for (Stick s : room.sticks) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(s.bodyName());
            if (s.f.on) sb.append(s.hard ? " (fighting, hard)" : " (fighting)");
        }
        return sb.length() > 0 ? sb.toString() : "Stick figure";
    }

    private void updateNote() {
        String text = names();
        if (text.equals(note)) return;
        note = text;
        getSystemService(NotificationManager.class).notify(NOTE_ID, notification());
    }

    private Notification notification() {
        boolean fighting = room.anyFighting();
        int first = !room.sticks.isEmpty() ? room.sticks.get(0).slot : 0;
        Intent menu = new Intent(this, MenuActivity.class).putExtra("slot", first);
        Notification.Builder b = new Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stick)
            .setContentTitle("Desktop Stickman")
            .setContentText(names())
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(PendingIntent.getActivity(this, 0, menu,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
            .addAction(new Notification.Action.Builder(null, fighting ? "Stop the fight" : "Wave at me",
                service(fighting ? STOP_FIGHTS : WAVE, 1)).build())
            .addAction(new Notification.Action.Builder(null, "Add another", service(ADD, 2)).build())
            .addAction(new Notification.Action.Builder(null, "Quit all", service(QUIT_ALL, 3)).build());
        return b.build();
    }

    private PendingIntent service(String action, int code) {
        Intent i = new Intent(this, StickService.class).setAction(action);
        return PendingIntent.getService(this, code, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    // ------------------------------------------------------------ Room.Hands
    // What each app on the home screen is called, so an icon he stamps on can
    // be opened. Only apps are listed, so folders and widgets match nothing.
    private void findApps() {
        try {
            PackageManager pm = getPackageManager();
            Map<String, Intent> m = new HashMap<>();
            Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
            for (ResolveInfo ri : pm.queryIntentActivities(main, 0)) {
                if (ri.activityInfo == null || getPackageName().equals(ri.activityInfo.packageName)) continue;
                String label = String.valueOf(ri.loadLabel(pm)).trim().toLowerCase(Locale.ROOT);
                if (label.isEmpty()) continue;
                m.put(label, new Intent(main).setComponent(
                    new ComponentName(ri.activityInfo.packageName, ri.activityInfo.name)));
            }
            apps = m;
            ResolveInfo home = pm.resolveActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                                                  PackageManager.MATCH_DEFAULT_ONLY);
            homePackage = home != null && home.activityInfo != null ? home.activityInfo.packageName : null;
        } catch (RuntimeException e) {
            Log.trail("apps", e);
        }
        // a new app could turn up on the home screen at any time
        h.postDelayed(() -> { if (me == this) new Thread(this::findApps, "stickman-apps").start(); }, 60_000);
    }

    boolean isApp(String label) {
        return label != null && apps.containsKey(label.trim().toLowerCase(Locale.ROOT));
    }

    @Override public boolean openApp(String label) {
        Intent i = label == null ? null : apps.get(label.trim().toLowerCase(Locale.ROOT));
        if (i == null) return false;
        try {
            startActivity(new Intent(i).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED));
            return true;
        } catch (RuntimeException e) {
            Log.trail("open " + label, e);
            return false;
        }
    }

    @Override public void press(Ledge b) {
        Eyes e = Eyes.me;
        if (e != null) e.press(b);
    }

    // you tapped something in another app (the accessibility service saw it)
    void tapped(float x, float y) {
        if (running) room.tapped(x, y);
    }
}
