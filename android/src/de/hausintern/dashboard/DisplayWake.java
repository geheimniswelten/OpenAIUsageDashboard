package de.hausintern.dashboard;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.Application;
import android.app.KeyguardManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.util.Log;
import android.view.WindowManager;
import java.lang.ref.WeakReference;
import java.text.DateFormat;
import java.util.Date;
import java.util.TimeZone;

/** A persisted system alarm, independent of Delphi's suspended UI timer. */
public final class DisplayWake extends BroadcastReceiver {
    private static final String TAG = "DashboardWake";
    private static final String PREFS = "dashboard_display_wake";
    private static final String WAKE = "de.hausintern.dashboard.DISPLAY_WAKE";
    private static final String TEST = "de.hausintern.dashboard.DISPLAY_WAKE_TEST";
    private static WeakReference<Activity> current = new WeakReference<>(null);
    private static boolean attached;
    private static boolean wakePending;
    private static String lastError = "";

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static AlarmManager alarms(Context c) {
        return (AlarmManager)c.getSystemService(Context.ALARM_SERVICE);
    }

    private static PendingIntent operation(Context c, boolean test) {
        return PendingIntent.getBroadcast(c, test ? 2 : 1,
                new Intent(c, DisplayWake.class).setAction(test ? TEST : WAKE),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    public static boolean exactAllowed(Context c) {
        return Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms();
    }

    private static void setAlarm(Context c, long when, boolean test) {
        AlarmManager a = alarms(c);
        PendingIntent p = operation(c, test);
        // Replacing this PendingIntent also replaces an earlier exact/inexact alarm.
        try {
            if (exactAllowed(c)) {
                a.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, p);
            } else {
                a.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, p);
            }
            lastError = "";
            Log.i(TAG, "Scheduled " + (test ? "test" : "weekday") + " at " + when
                    + ", exact=" + exactAllowed(c));
        } catch (SecurityException e) {
            // The special access may be revoked between checking and scheduling.
            a.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, p);
            lastError = "Pünktliche Wecktermine sind nicht freigegeben.";
            Log.w(TAG, lastError, e);
        }
    }

    private static void schedule(Context c) {
        SharedPreferences p = prefs(c);
        if (!p.getBoolean("enabled", false)) return;
        long next = WakeSchedule.nextStart(System.currentTimeMillis(), TimeZone.getDefault(),
                p.getInt("start", 10), p.getInt("end", 18));
        if (next == 0) {
            alarms(c).cancel(operation(c, false));
        } else {
            setAlarm(c, next, false);
        }
        p.edit().putLong("next", next).apply();
    }

    public static void configure(Activity activity, int startHour, int endHour) {
        current = new WeakReference<>(activity);
        SharedPreferences p = prefs(activity);
        boolean changed = !p.getBoolean("enabled", false)
                || p.getInt("start", -1) != startHour || p.getInt("end", -1) != endHour;
        if (changed) p.edit().putBoolean("enabled", true).putInt("start", startHour)
                .putInt("end", endHour).apply();
        if (!attached) {
            attached = true;
            activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
                public void onActivityResumed(Activity a) {
                    if (a == current.get()) {
                        schedule(a);
                        applyWakeWindow(a);
                    }
                }
                public void onActivityCreated(Activity a, Bundle b) { }
                public void onActivityStarted(Activity a) { }
                public void onActivityPaused(Activity a) { }
                public void onActivityStopped(Activity a) { }
                public void onActivitySaveInstanceState(Activity a, Bundle b) { }
                public void onActivityDestroyed(Activity a) {
                    if (a == current.get()) current.clear();
                }
            });
            changed = true;
        }
        if (changed) schedule(activity);
        if (wakePending) activity.runOnUiThread(() -> applyWakeWindow(activity));
    }

    private static void applyWakeWindow(Activity a) {
        if (!wakePending) return;
        wakePending = false;
        SharedPreferences p = prefs(a);
        if (WakeSchedule.active(System.currentTimeMillis(), TimeZone.getDefault(),
                p.getInt("start", 10), p.getInt("end", 18))) {
            a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
        if (Build.VERSION.SDK_INT >= 27) a.setTurnScreenOn(true);
        KeyguardManager k = (KeyguardManager)a.getSystemService(Context.KEYGUARD_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && !k.isDeviceSecure() && k.isKeyguardLocked()) {
            if (Build.VERSION.SDK_INT >= 27) a.setShowWhenLocked(true);
            k.requestDismissKeyguard(a, null);
        }
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (!a.isDestroyed() && Build.VERSION.SDK_INT >= 27) {
                a.setTurnScreenOn(false);
                a.setShowWhenLocked(false);
            }
        }, 5000);
    }

    @SuppressWarnings("deprecation")
    private static void wake(Context c) {
        PowerManager power = (PowerManager)c.getSystemService(Context.POWER_SERVICE);
        if (power.isInteractive()) {
            Log.i(TAG, "Display already on; no foreground change");
            return;
        }
        wakePending = true;
        // A short screen wake lock resumes the dashboard left on top overnight.
        // It is bounded and never holds the processor or screen throughout the night.
        // Android's newer permission checks still apply; this is not a device-policy bypass.
        PowerManager.WakeLock lock = power.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK
                | PowerManager.ACQUIRE_CAUSES_WAKEUP | PowerManager.ON_AFTER_RELEASE,
                "OpenAIUsageDashboard:MorningDisplay");
        lock.acquire(15000);
        Activity a = current.get();
        if (a != null) a.runOnUiThread(() -> applyWakeWindow(a));
        else {
            // Android may have reclaimed the process while asleep. A launch request
            // remains subject to the system's background-activity policy.
            Intent launch = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
            if (launch != null) c.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            boolean on = power.isInteractive();
            prefs(c).edit().putString("lastResult", on ? "Display eingeschaltet"
                    : "Android hat das Einschalten nicht zugelassen").apply();
            Log.i(TAG, "Wake result: interactive=" + on);
        }, 1500);
    }

    @Override public void onReceive(Context context, Intent intent) {
        Context c = context.getApplicationContext();
        if (!prefs(c).getBoolean("enabled", false)) return;
        String action = intent.getAction();
        if (WAKE.equals(action) || TEST.equals(action)) {
            SharedPreferences p = prefs(c);
            boolean active = WakeSchedule.active(System.currentTimeMillis(), TimeZone.getDefault(),
                    p.getInt("start", 10), p.getInt("end", 18));
            // A delayed delivery must not wake the display after the configured end.
            if (active || TEST.equals(action)) {
                try { wake(c); }
                catch (RuntimeException e) {
                    lastError = "Display konnte nicht eingeschaltet werden.";
                    p.edit().putString("lastResult", lastError).apply();
                    Log.e(TAG, lastError, e);
                }
            }
        }
        // Boot, clock/timezone changes, app updates and alarm-permission grants
        // all restore the next local weekday. A test never replaces this alarm.
        schedule(c);
    }

    public static void stop(Context c) {
        prefs(c).edit().putBoolean("enabled", false).remove("next").apply();
        alarms(c).cancel(operation(c, false));
        alarms(c).cancel(operation(c, true));
        wakePending = false;
    }

    public static void requestExactPermission(Activity a) {
        if (Build.VERSION.SDK_INT >= 31 && !exactAllowed(a)) {
            a.startActivity(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:" + a.getPackageName())));
        }
    }

    public static String test(Activity a) {
        if (!exactAllowed(a)) {
            requestExactPermission(a);
            return "Bitte Wecker & Erinnerungen erlauben und den Test danach erneut starten.";
        }
        setAlarm(a, System.currentTimeMillis() + 30000, true);
        return "Wecktest in 30 Sekunden: Display jetzt mit der Ein/Aus-Taste ausschalten.";
    }

    public static String status(Context c) {
        if (!lastError.isEmpty()) return lastError;
        SharedPreferences p = prefs(c);
        long next = p.getLong("next", 0);
        if (next == 0) return "Automatisches Aufwecken ist nicht geplant.";
        String text = "Nächstes Aufwecken: " + DateFormat.getDateTimeInstance(
                DateFormat.SHORT, DateFormat.SHORT).format(new Date(next)) + ".";
        if (!exactAllowed(c)) text += " Für pünktliches Aufwecken bitte Weckzeit erlauben.";
        String result = p.getString("lastResult", "");
        if (!result.isEmpty()) text += " Letzter Versuch: " + result + ".";
        return text;
    }
}
