package com.desktopstickman;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.os.Bundle;
import android.text.InputFilter;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.ArrayAdapter;
import android.widget.AutoCompleteTextView;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

// A small stand-in for Flash's F8 dialog: a name, a symbol type and the 3x3
// registration grid, plus fight mode. Name him after one of Alan Becker's
// figures and he becomes it (see Eggs).
public final class SymbolActivity extends Activity {
    static final String[] TYPES = { "Movie Clip", "Button", "Graphic" };

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        StickService svc = StickService.me;
        final Stick s = svc == null ? null : svc.room.bySlot(getIntent().getIntExtra("slot", 0));
        if (s == null) { finish(); return; }
        setTitle("Convert to Symbol");
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE);
        float dp = getResources().getDisplayMetrics().density;
        int pad = Math.round(16 * dp);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(pad, pad / 2, pad, pad);

        col.addView(label("Name:"));
        final AutoCompleteTextView name = new AutoCompleteTextView(this);
        name.setSingleLine(true);
        name.setFilters(new InputFilter[] { new InputFilter.LengthFilter(24) });
        name.setText("Symbol " + s.symNum);
        name.setSelectAllOnFocus(true);
        // start typing a figure's name and the rest of it is offered
        name.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_dropdown_item_1line, Eggs.names()));
        name.setThreshold(1);
        col.addView(name);

        col.addView(label("Type:"));
        final Spinner type = new Spinner(this);
        type.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, TYPES));
        for (int i = 0; i < TYPES.length; i++) if (TYPES[i].equals(s.symType)) type.setSelection(i);
        col.addView(type);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.addView(label("Registration:"));
        final RegGrid reg = new RegGrid(this, s.symReg);
        int g = Math.round(56 * dp);
        left.addView(reg, new LinearLayout.LayoutParams(g, g));
        row.addView(left);

        LinearLayout right = new LinearLayout(this);
        right.setOrientation(LinearLayout.VERTICAL);
        right.setPadding(pad, 0, 0, 0);
        // Animator vs. Animation, with your pointer as the animator (see Stick.startFight)
        final CheckBox fight = new CheckBox(this);
        fight.setText("Fight mode");
        fight.setChecked(s.f.on);
        // the same fight, far harder (see Stick.HARD)
        final CheckBox hard = new CheckBox(this);
        hard.setText("Hard mode");
        hard.setChecked(s.hard);
        hard.setEnabled(fight.isChecked());
        fight.setOnCheckedChangeListener((v, on) -> hard.setEnabled(on));
        TextView about = new TextView(this);
        about.setText("He fights your pointer: an arrow you drag about. He teleports to it, punches it, grabs it, " +
                      "drags it off and throws Flash panels at it. Tap him to hit back.");
        about.setTextSize(12);
        about.setAlpha(0.6f);
        right.addView(fight);
        right.addView(hard);
        right.addView(about);
        row.addView(right, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        col.addView(row);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setGravity(Gravity.END);
        Button ok = new Button(this);
        ok.setText("OK");
        Button cancel = new Button(this);
        cancel.setText("Cancel");
        buttons.addView(ok);
        buttons.addView(cancel);
        col.addView(buttons);

        ok.setOnClickListener(v -> {
            StickService now = StickService.me;
            if (now != null && now.room.sticks.contains(s)) {
                // where you tapped OK is where "the pointer" is, for the figures that run at it
                int[] at = new int[2];
                v.getLocationOnScreen(at);
                now.room.tapX = at[0] + v.getWidth() / 2f;
                now.room.tapY = at[1] + v.getHeight() / 2f;
                s.convertSymbol(name.getText().toString().trim(), TYPES[type.getSelectedItemPosition()],
                                reg.sel, fight.isChecked(), hard.isChecked());
            }
            finish();
        });
        cancel.setOnClickListener(v -> finish());

        ScrollView sv = new ScrollView(this);
        sv.addView(col);
        setContentView(sv);
        name.requestFocus();
    }

    private TextView label(String t) {
        TextView v = new TextView(this);
        v.setText(t);
        v.setPadding(0, Math.round(8 * getResources().getDisplayMetrics().density), 0, 0);
        return v;
    }

    // the nine registration points, one of them picked
    static final class RegGrid extends View {
        int sel;
        private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG), dot = new Paint(Paint.ANTI_ALIAS_FLAG);

        RegGrid(Context c, int sel) {
            super(c);
            this.sel = Math.max(0, Math.min(8, sel));
            line.setStyle(Paint.Style.STROKE);
            line.setStrokeWidth(c.getResources().getDisplayMetrics().density);
            line.setColor(0xFF555555);
            dot.setColor(0xFF000000);
        }

        @Override protected void onDraw(Canvas c) {
            float w = getWidth() / 3f, h = getHeight() / 3f, m = w * 0.08f;
            for (int i = 0; i < 9; i++) {
                float x = (i % 3) * w, y = (i / 3) * h;
                c.drawRect(x + m, y + m, x + w - m, y + h - m, line);
                if (i == sel) c.drawRect(x + 3 * m, y + 3 * m, x + w - 3 * m, y + h - 3 * m, dot);
            }
        }

        @Override public boolean onTouchEvent(MotionEvent e) {
            if (e.getActionMasked() == MotionEvent.ACTION_UP) {
                int cx = (int) Math.max(0, Math.min(2, e.getX() / (getWidth() / 3f)));
                int cy = (int) Math.max(0, Math.min(2, e.getY() / (getHeight() / 3f)));
                sel = cy * 3 + cx;
                invalidate();
                performClick();
            }
            return true;
        }

        @Override public boolean performClick() { return super.performClick(); }
    }
}
