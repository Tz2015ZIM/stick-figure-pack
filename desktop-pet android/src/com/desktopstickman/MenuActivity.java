package com.desktopstickman;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

// His menu: what the tray icon's right-click menu holds on Windows. Hold him
// down to open it (or tap the notification).
public final class MenuActivity extends Activity {
    private int slot;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        slot = getIntent().getIntExtra("slot", 0);
    }

    @Override protected void onResume() {
        super.onResume();
        build();
    }

    private Stick him() {
        StickService s = StickService.me;
        if (s == null) return null;
        Stick st = s.room.bySlot(slot);
        if (st == null && !s.room.sticks.isEmpty()) st = s.room.sticks.get(0);
        return st;
    }

    private void build() {
        final StickService svc = StickService.me;
        final Stick s = him();
        if (svc == null || s == null) { finish(); return; }
        setTitle(s.bodyName() + (s.f.on ? (s.hard ? " (fighting, hard)" : " (fighting)") : ""));

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        int pad = Math.round(16 * getResources().getDisplayMetrics().density);
        col.setPadding(pad, pad / 2, pad, pad);

        button(col, "Toss in the air", v -> { s.toss(); finish(); });
        button(col, "Wave at me", v -> { s.waveAtYou(); finish(); });

        boolean eyes = Eyes.me != null;
        check(col, "Let him open apps he stamps on", svc.room.open, eyes,
              "When he stamps on an app icon on the home screen it opens, at most once every 45 seconds.",
              on -> svc.setting("open", on));
        check(col, "Let him really press buttons", svc.room.click, eyes,
              "Off by default: when on, standing on a button actually presses it.",
              on -> svc.setting("click", on));
        check(col, "Let him throw things in a fight", svc.room.throwOk, true, null, on -> svc.setting("throw", on));
        check(col, "Let him grab the pointer in a fight", svc.room.grabPtr, true, null, on -> svc.setting("grab", on));
        check(col, "Let him break the pointer in a fight", svc.room.killPtr, true, null, on -> svc.setting("kill", on));
        check(col, "Hard mode", s.hard, true,
              "A much harder fight: he takes 20 hits instead of 8, blocks, gets back up once, attacks faster, " +
              "dodges more, throws more, and your pointer breaks after 6 hits.",
              on -> s.setHard(on));

        divider(col);
        button(col, "Convert to Symbol...", v -> {
            startActivity(new Intent(this, SymbolActivity.class).putExtra("slot", s.slot));
            finish();
        });
        Button brk = button(col, "Break apart", v -> { s.breakSymbol(); finish(); });
        brk.setEnabled(s.symbol);
        if (s.f.on) button(col, "Stop the fight", v -> { s.endFight(); finish(); });

        divider(col);
        button(col, "Add another stickman", v -> { svc.add(); finish(); });
        if (!eyes) {
            button(col, "Let him see the screen...", v -> {
                startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
                finish();
            });
        }
        divider(col);
        button(col, "Quit", v -> { svc.quit(s); finish(); });
        button(col, "Quit all stickmen", v -> { svc.quitAll(); finish(); });

        ScrollView sv = new ScrollView(this);
        sv.addView(col);
        setContentView(sv);
    }

    interface Toggle { void set(boolean on); }

    private Button button(LinearLayout col, String text, View.OnClickListener l) {
        Button b = new Button(this, null, android.R.attr.borderlessButtonStyle);
        b.setText(text);
        b.setAllCaps(false);
        b.setGravity(android.view.Gravity.START | android.view.Gravity.CENTER_VERTICAL);
        b.setOnClickListener(l);
        col.addView(b, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        return b;
    }

    private void check(LinearLayout col, String text, boolean on, boolean enabled, String hint, Toggle t) {
        CheckBox c = new CheckBox(this);
        c.setText(text);
        c.setChecked(on);
        c.setEnabled(enabled);
        c.setOnCheckedChangeListener((v, now) -> t.set(now));
        col.addView(c);
        if (hint != null) {
            TextView h = new TextView(this);
            h.setText(enabled ? hint : hint + " Needs \"Let him see the screen\".");
            h.setTextSize(12);
            h.setAlpha(0.6f);
            h.setPadding(Math.round(32 * getResources().getDisplayMetrics().density), 0, 0, 0);
            col.addView(h);
        }
    }

    private void divider(LinearLayout col) {
        View v = new View(this);
        v.setBackgroundColor(0x22000000);
        int m = Math.round(6 * getResources().getDisplayMetrics().density);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1);
        lp.setMargins(0, m, 0, m);
        col.addView(v, lp);
    }
}
