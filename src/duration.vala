namespace Glance.Duration {
    public const int64 SECOND = 1000000;
    public const int64 MINUTE = 60 * SECOND;
    public const int64 HOUR = 60 * MINUTE;
    public const int64 MAX = 23 * HOUR + 59 * MINUTE + 59 * SECOND;

    // MM:SS below one hour, HH:MM:SS from one hour. Rounds up so a running timer never reads 00:00.
    public string format (int64 us) {
        var total = (int64.max (us, 0) + SECOND - 1) / SECOND;
        var h = total / 3600;
        var m = total / 60 % 60;
        var s = total % 60;
        if (h > 0) return "%02lld:%02lld:%02lld".printf (h, m, s);
        return "%02lld:%02lld".printf (m, s);
    }
}
