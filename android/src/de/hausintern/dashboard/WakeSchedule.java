package de.hausintern.dashboard;

import java.util.Calendar;
import java.util.TimeZone;

/** Local calendar dates deliberately avoid fixed 24-hour steps across DST. */
public final class WakeSchedule {
    private WakeSchedule() { }

    public static boolean valid(int startHour, int endHour) {
        return startHour >= 0 && startHour < 24 && endHour > startHour && endHour <= 24;
    }

    public static boolean active(long now, TimeZone zone, int startHour, int endHour) {
        if (!valid(startHour, endHour)) return false;
        Calendar c = Calendar.getInstance(zone);
        c.setTimeInMillis(now);
        int day = c.get(Calendar.DAY_OF_WEEK);
        int hour = c.get(Calendar.HOUR_OF_DAY);
        return day != Calendar.SATURDAY && day != Calendar.SUNDAY
                && hour >= startHour && hour < endHour;
    }

    public static long nextStart(long now, TimeZone zone, int startHour, int endHour) {
        if (!valid(startHour, endHour)) return 0;
        Calendar c = Calendar.getInstance(zone);
        c.setTimeInMillis(now);
        c.set(Calendar.HOUR_OF_DAY, startHour);
        c.set(Calendar.MINUTE, 0);
        c.set(Calendar.SECOND, 0);
        c.set(Calendar.MILLISECOND, 0);
        while (c.getTimeInMillis() <= now || c.get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY
                || c.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) {
            c.add(Calendar.DATE, 1);
        }
        return c.getTimeInMillis();
    }
}
