namespace Glance {
    public enum TimerState { IDLE, RUNNING, PAUSED, FINISHED }

    public delegate int64 Clock ();

    [CCode (cname = "CLOCK_BOOTTIME", cheader_filename = "time.h")]
    extern const Posix.clockid_t CLOCK_BOOTTIME;

    // Monotonic microseconds that keep counting through suspend.
    public int64 boottime () {
        Posix.timespec ts;
        Posix.clock_gettime (CLOCK_BOOTTIME, out ts);
        return (int64) ts.tv_sec * Duration.SECOND + ts.tv_nsec / 1000;
    }

    // One countdown. Duration timers run on `now`, Until timers on `real_now`.
    public class Timer : Object {
        public TimerState state { get; private set; default = TimerState.IDLE; }
        public bool is_until { get; private set; }
        // Full length in microseconds, raised by add(); used for progress.
        public int64 total { get; private set; }

        public Clock now = boottime;
        public Clock real_now = get_real_time;

        // Emitted whenever the displayed time may have changed.
        public signal void tick ();
        // Emitted once when a running timer reaches zero.
        public signal void finished ();

        int64 deadline;
        int64 paused_remaining;
        uint tick_source;

        public int64 remaining {
            get {
                switch (state) {
                case TimerState.RUNNING: return int64.max (deadline - clock (), 0);
                case TimerState.PAUSED: return paused_remaining;
                default: return 0;
                }
            }
        }

        // Elapsed fraction, 0 at start and 1 when finished.
        public double progress {
            get {
                if (state == TimerState.FINISHED) return 1.0;
                if (total <= 0) return 0.0;
                return 1.0 - (double) remaining / total;
            }
        }

        // Starts or replaces the timer. Rejects zero and anything above 23:59:59.
        public bool start (int64 duration) {
            if (duration <= 0 || duration > Duration.MAX) return false;
            is_until = false;
            run (duration);
            return true;
        }

        // Counts down to a wall-clock instant in Unix microseconds.
        public bool start_until (int64 target) {
            var duration = target - real_now ();
            if (duration <= 0) return false;
            is_until = true;
            run (duration);
            return true;
        }

        public bool pause () {
            if (state != TimerState.RUNNING || is_until) return false;
            paused_remaining = remaining;
            cancel_tick ();
            state = TimerState.PAUSED;
            tick ();
            return true;
        }

        public bool resume () {
            if (state != TimerState.PAUSED) return false;
            deadline = clock () + paused_remaining;
            state = TimerState.RUNNING;
            schedule_tick ();
            tick ();
            return true;
        }

        // Stop, reset and dismiss all return to IDLE.
        public void stop () {
            cancel_tick ();
            total = 0;
            is_until = false;
            state = TimerState.IDLE;
            tick ();
        }

        // Extends a running or paused timer; the remaining time is capped at 23:59:59.
        public bool add (int64 amount) {
            if (amount <= 0 || (state != TimerState.RUNNING && state != TimerState.PAUSED)) return false;
            var before = remaining;
            var after = int64.min (before + amount, Duration.MAX);
            total += after - before;
            if (state == TimerState.PAUSED) {
                paused_remaining = after;
            } else {
                deadline = clock () + after;
                schedule_tick ();
            }
            tick ();
            return true;
        }

        // Moves a running timer to FINISHED once its time is up. Called by the tick and by tests.
        public void check () {
            if (state != TimerState.RUNNING || remaining > 0) return;
            cancel_tick ();
            state = TimerState.FINISHED;
            tick ();
            finished ();
        }

        // Milliseconds until the displayed whole second changes, which also lands on the deadline.
        public static uint tick_interval (int64 remaining) {
            if (remaining <= 0) return 1;
            var until_change = (remaining - 1) % Duration.SECOND + 1;
            return (uint) ((until_change + 999) / 1000) + 1;
        }

        int64 clock () {
            return is_until ? real_now () : now ();
        }

        void run (int64 duration) {
            deadline = clock () + duration;
            total = duration;
            state = TimerState.RUNNING;
            schedule_tick ();
            tick ();
        }

        void schedule_tick () {
            cancel_tick ();
            tick_source = Timeout.add (tick_interval (remaining), on_tick);
        }

        void cancel_tick () {
            if (tick_source != 0) {
                Source.remove (tick_source);
                tick_source = 0;
            }
        }

        bool on_tick () {
            tick_source = 0;
            check ();
            if (state == TimerState.RUNNING) {
                tick ();
                schedule_tick ();
            }
            return Source.REMOVE;
        }
    }
}
