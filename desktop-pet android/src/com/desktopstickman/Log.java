package com.desktopstickman;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

// He runs with no console, so he leaves a trail when something goes wrong:
// stickman-error.log in the app's files folder (stdout on a plain JVM).
final class Log {
    static volatile File file;

    static synchronized void trail(String what, Throwable e) {
        String stamp = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(new Date());
        StackTraceElement at = e.getStackTrace().length > 0 ? e.getStackTrace()[0] : null;
        String line = stamp + "  " + what + ": " + e + (at != null ? "  @ " + at : "");
        File f = file;
        if (f == null) { System.out.println(line); return; }
        try (PrintWriter w = new PrintWriter(new FileWriter(f, true))) {
            w.println(line);
        } catch (Exception ignored) { }
    }
}
