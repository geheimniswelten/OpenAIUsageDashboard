import de.hausintern.dashboard.WakeSchedule;
import java.time.ZonedDateTime;
import java.util.TimeZone;

public final class WakeScheduleTest {
    private static final TimeZone BERLIN = TimeZone.getTimeZone("Europe/Berlin");
    private static int checks;
    private static long time(String text) { return ZonedDateTime.parse(text).toInstant().toEpochMilli(); }
    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }
    private static void next(String now, String expected) {
        check(WakeSchedule.nextStart(time(now), BERLIN, 10, 18) == time(expected), "next: " + now);
    }
    public static void main(String[] args) {
        next("2026-10-30T09:59:59+01:00", "2026-10-30T10:00:00+01:00");
        next("2026-10-30T10:00:00+01:00", "2026-11-02T10:00:00+01:00");
        next("2026-10-31T08:00:00+01:00", "2026-11-02T10:00:00+01:00");
        next("2026-11-01T23:59:59+01:00", "2026-11-02T10:00:00+01:00");
        next("2026-11-02T18:00:00+01:00", "2026-11-03T10:00:00+01:00");
        next("2026-10-23T18:00:00+02:00", "2026-10-26T10:00:00+01:00");
        next("2026-03-27T18:00:00+01:00", "2026-03-30T10:00:00+02:00");
        next("2026-12-31T18:00:00+01:00", "2027-01-01T10:00:00+01:00");
        check(WakeSchedule.active(time("2026-10-30T10:00:00+01:00"), BERLIN, 10, 18), "start inclusive");
        check(!WakeSchedule.active(time("2026-10-30T18:00:00+01:00"), BERLIN, 10, 18), "end exclusive");
        check(!WakeSchedule.active(time("2026-10-31T12:00:00+01:00"), BERLIN, 10, 18), "no weekend wake");
        check(WakeSchedule.active(time("2026-10-30T23:59:59+01:00"), BERLIN, 0, 24), "whole weekday");
        check(WakeSchedule.nextStart(0, BERLIN, 18, 10) == 0, "invalid interval disabled");
        check(WakeSchedule.nextStart(0, BERLIN, 10, 10) == 0, "empty interval disabled");
        System.out.println("WAKE_SCHEDULE_OK " + checks + " checks");
    }
}
