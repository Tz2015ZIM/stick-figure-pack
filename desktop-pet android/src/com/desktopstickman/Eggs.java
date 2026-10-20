package com.desktopstickman;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeSet;

// Hidden names. Call the symbol after one of Alan Becker's stick figures and he
// becomes it: he takes its colour and does the thing that figure is known for.
final class Eggs {
    static final int INK = 0xFF18181C;     // his own ink

    static final class Egg {
        final String name, act;
        final int ink;
        Egg(String name, int r, int g, int b, String act) {
            this.name = name; this.act = act; this.ink = 0xFF000000 | (r << 16) | (g << 8) | b;
        }
    }

    static final Map<String, Egg> EGGS = new LinkedHashMap<>();
    static {
        Egg victim = new Egg("The Victim", 20, 20, 26, "launch");
        Egg tco = new Egg("The Chosen One", 40, 46, 64, "launch");
        Egg dark = new Egg("The Dark Lord", 58, 30, 74, "chase");
        Egg tsc = new Egg("The Second Coming", 247, 148, 29, "cheer");
        Egg alan = new Egg("Alan Becker", 60, 60, 66, "wave");
        EGGS.put("victim", victim);
        EGGS.put("chosenone", tco); EGGS.put("tco", tco); EGGS.put("chosen", tco);
        EGGS.put("darklord", dark); EGGS.put("dark", dark);
        EGGS.put("secondcoming", tsc); EGGS.put("tsc", tsc); EGGS.put("orange", tsc);
        EGGS.put("red", new Egg("Red", 224, 49, 49, "launch"));
        EGGS.put("green", new Egg("Green", 47, 158, 68, "wave"));
        EGGS.put("blue", new Egg("Blue", 28, 126, 214, "chase"));
        EGGS.put("yellow", new Egg("Yellow", 240, 180, 20, "cheer"));
        EGGS.put("purple", new Egg("Purple", 146, 58, 190, "wave"));
        EGGS.put("alanbecker", alan); EGGS.put("alan", alan); EGGS.put("becker", alan);
        EGGS.put("animator", alan); EGGS.put("noogai", alan);
    }

    // the names offered in the dialog as you type, so you do not have to guess
    static String[] names() {
        TreeSet<String> set = new TreeSet<>();
        for (Egg e : EGGS.values()) set.add(e.name);
        return set.toArray(new String[0]);
    }

    // 'The Second Coming', 'second coming' and 'TSC' all have to land on one key.
    // Case, spaces, punctuation and a leading 'the' are thrown away first, and if
    // that still misses, a name with the character buried in it counts too, so
    // 'red guy', 'chosen one 2' and 'blue stickman' all find their figure.
    static Egg find(String name) {
        String k = (name == null ? "" : name).toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
        if (k.isEmpty()) return null;
        k = k.replaceFirst("^the", "");
        Egg e = EGGS.get(k);
        if (e != null) return e;
        List<String> keys = new ArrayList<>(EGGS.keySet());
        keys.sort(new Comparator<String>() {
            public int compare(String a, String b) { return b.length() - a.length(); }
        });
        for (String key : keys) if (k.contains(key)) return EGGS.get(key);
        return null;
    }

    private Eggs() { }
}
