package com.desktopstickman;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

// The app's own screen: the permissions he needs, a button to let him out,
// and how to play with him. He lives on in the background once he is out.
public final class MainActivity extends Activity {
    private float dp;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        dp = getResources().getDisplayMetrics().density;
    }

    @Override protected void onResume() {
        super.onResume();
        StickService s = StickService.me;
        if (s != null) s.uiShown(true);         // the fight arena steps aside
        build();
    }

    @Override protected void onPause() {
        StickService s = StickService.me;
        if (s != null) s.uiShown(false);
        super.onPause();
    }

    private void build() {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        int pad = Math.round(20 * dp);
        col.setPadding(pad, pad, pad, pad);

        text(col, "A stick figure that lives on top of your apps. He walks along the bottom of the screen, " +
                  "climbs and stands on whatever he can see, meets up with other stickmen, and fights you " +
                  "Animator vs. Animation style if you let him.", 15, 1f);

        boolean overlay = Settings.canDrawOverlays(this);
        heading(col, "1. Display over other apps");
        if (overlay) text(col, "Allowed.", 14, 0.7f);
        else {
            text(col, "He needs this to be on screen at all.", 14, 0.7f);
            button(col, "Allow", v -> startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName()))));
        }

        if (Build.VERSION.SDK_INT >= 33) {
            heading(col, "2. Notifications");
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                text(col, "Allowed. His notification is his tray icon: tap it for his menu.", 14, 0.7f);
            } else {
                text(col, "Optional: his notification works like his tray icon on Windows.", 14, 0.7f);
                button(col, "Allow", v -> requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS }, 1));
            }
        }

        heading(col, Build.VERSION.SDK_INT >= 33 ? "3. Let him out" : "2. Let him out");
        boolean running = StickService.me != null;
        Button go = button(col, running ? "Add another stickman" : "Start the stickman", v -> {
            Intent i = new Intent(this, StickService.class);
            if (StickService.me != null) i.setAction(StickService.ADD);
            startForegroundService(i);
            v.postDelayed(this::build, 300);
        });
        go.setEnabled(overlay);
        if (running) {
            button(col, "Quit all stickmen", v -> {
                startService(new Intent(this, StickService.class).setAction(StickService.QUIT_ALL));
                v.postDelayed(this::build, 300);
            });
        }

        heading(col, "Optional: let him see the screen");
        boolean eyes = Eyes.me != null;
        text(col, (eyes ? "On. " : "Off. ") +
            "With this on he can stand on dialogs, the keyboard, either half of a split screen, the buttons " +
            "in the app you are using and the icons on your home screen, runs over to whatever you tap, and " +
            "stamping on an app icon opens it now and then. It only looks; it never presses anything unless " +
            "you tick \"Let him really press buttons\" in his menu.", 14, 0.7f);
        if (!eyes) {
            text(col, "Turn on Desktop Stickman under Accessibility. If the switch is greyed out, go to " +
                "Settings > Apps > Desktop Stickman, tap the three dots at the top and choose " +
                "\"Allow restricted settings\", then try again.", 13, 0.6f);
        }
        button(col, "Open Accessibility settings", v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));

        heading(col, "Playing with him");
        text(col,
            "• Drag him about and let go to throw him; tap him and he jumps.\n" +
            "• Hold him down for his menu (or tap his notification).\n" +
            "• Add more than one and they meet up: they wave, high-five, chat, dance and play tag.\n" +
            "• Menu > Convert to Symbol wraps him in a Flash symbol box. Name him after an Alan Becker " +
            "figure (The Chosen One, The Dark Lord, The Second Coming, Red, Green, Blue, Yellow, Purple, " +
            "The Victim, Alan Becker) and he becomes it.\n" +
            "• Tick Fight mode there and he takes on your pointer: an arrow that jumps to wherever you " +
            "touch and follows your finger, or with a mouse, touchpad or pen, goes wherever the cursor goes. " +
            "Tap him to hit back. Break its health bar and he smashes it; knock him out and \"K.O.!\" is " +
            "typed above him as he fades away. While you fight, the whole screen is the arena, so taps do " +
            "not reach your apps: stop the fight from his menu or his notification.\n" +
            "• Every time you come back to your phone, they wave at you.", 14, 0.85f);

        ScrollView sv = new ScrollView(this);
        sv.addView(col);
        setContentView(sv);
    }

    private void heading(LinearLayout col, String t) {
        TextView v = text(col, t, 17, 1f);
        v.setTypeface(v.getTypeface(), android.graphics.Typeface.BOLD);
        v.setPadding(0, Math.round(18 * dp), 0, Math.round(4 * dp));
    }

    private TextView text(LinearLayout col, String t, float size, float alpha) {
        TextView v = new TextView(this);
        v.setText(t);
        v.setTextSize(size);
        v.setAlpha(alpha);
        col.addView(v);
        return v;
    }

    private Button button(LinearLayout col, String t, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(t);
        b.setAllCaps(false);
        b.setOnClickListener(l);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = Math.round(4 * dp);
        col.addView(b, lp);
        return b;
    }
}
