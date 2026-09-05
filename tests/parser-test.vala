using Glance;

const int64 S = Duration.SECOND;
const int64 M = Duration.MINUTE;
const int64 H = Duration.HOUR;

// Types `keys` into a fresh entry and returns it.
DigitEntry typed (string keys) {
    var e = new DigitEntry ();
    for (int i = 0; i < keys.length; i++) e.push (keys[i]);
    return e;
}

string shown (string keys) {
    int h, m, s;
    typed (keys).fields (out h, out m, out s);
    return "%02d:%02d:%02d".printf (h, m, s);
}

void add_entry_tests () {
    Test.add_func ("/entry/right-aligned", () => {
        assert_cmpstr (shown ("5"), CompareOperator.EQ, "00:00:05");
        assert_cmpstr (shown ("50"), CompareOperator.EQ, "00:00:50");
        assert_cmpstr (shown ("500"), CompareOperator.EQ, "00:05:00");
        assert_cmpstr (shown ("5000"), CompareOperator.EQ, "00:50:00");
        assert_cmpstr (shown ("12345"), CompareOperator.EQ, "01:23:45");
        assert_cmpstr (shown ("123456"), CompareOperator.EQ, "12:34:56");
        assert_true (typed ("12345").value () == H + 23 * M + 45 * S);
    });

    Test.add_func ("/entry/dot-shifting", () => {
        assert_cmpstr (shown ("50."), CompareOperator.EQ, "00:50:00");
        assert_cmpstr (shown ("1.."), CompareOperator.EQ, "01:00:00");
        assert_cmpstr (shown ("1.30"), CompareOperator.EQ, "00:01:30");
        assert_cmpstr (shown ("1.3"), CompareOperator.EQ, "00:01:03");
        assert_cmpstr (shown ("1.2.3"), CompareOperator.EQ, "01:02:03");
        assert_cmpstr (shown ("130."), CompareOperator.EQ, "01:30:00");
        assert_cmpstr (shown ("1.30."), CompareOperator.EQ, "01:30:00");
        assert_cmpstr (shown ("."), CompareOperator.EQ, "00:00:00");
        assert_true (typed ("50.").value () == 50 * M);
        assert_true (typed ("1..").value () == H);
    });

    Test.add_func ("/entry/ignored-keys", () => {
        // Seventh digit, third dot, a dot that would push digits past hours, digits past a full group.
        assert_cmpstr (typed ("1234567").text, CompareOperator.EQ, "123456");
        assert_cmpstr (typed ("1...").text, CompareOperator.EQ, "1..");
        assert_cmpstr (typed ("12345.").text, CompareOperator.EQ, "12345");
        assert_cmpstr (typed ("123.4.").text, CompareOperator.EQ, "123.4");
        assert_cmpstr (typed ("1.305").text, CompareOperator.EQ, "1.30");
        assert_cmpstr (typed ("1a:b-2 ").text, CompareOperator.EQ, "12");
        var e = new DigitEntry ();
        assert_false (e.push ('x'));
        assert_false (e.push ('٥'));  // ARABIC-INDIC DIGIT FIVE
        assert_true (e.push ('7'));
    });

    Test.add_func ("/entry/overflow-normalises-on-commit", () => {
        // Shown as typed, committed as h*3600 + m*60 + s.
        assert_cmpstr (shown ("75"), CompareOperator.EQ, "00:00:75");
        assert_true (typed ("75").value () == 75 * S);
        assert_true (typed ("90.").value () == 90 * M);
        assert_true (typed ("995999").value () > Duration.MAX);
        assert_true (typed ("235959").value () == Duration.MAX);
    });

    Test.add_func ("/entry/backspace", () => {
        var e = typed ("1.30");
        assert_true (e.backspace ());
        assert_cmpstr (e.text, CompareOperator.EQ, "1.3");
        e.backspace ();
        e.backspace ();
        assert_cmpstr (e.text, CompareOperator.EQ, "1");
        // Removing a dot re-opens the previous group.
        assert_true (e.push ('2'));
        assert_true (e.value () == 12 * S);
        e.backspace ();
        e.backspace ();
        assert_false (e.backspace ());
        assert_true (e.value () == 0);
    });

    Test.add_func ("/entry/empty-and-clear", () => {
        var e = typed ("");
        assert_true (e.value () == 0);
        e = typed ("12.");
        e.clear ();
        assert_cmpstr (e.text, CompareOperator.EQ, "");
        assert_true (e.value () == 0);
        assert_true (typed ("000").value () == 0);
    });
}

void add_cli_tests () {
    Test.add_func ("/cli/units", () => {
        assert_true (Duration.parse ("45s") == 45 * S);
        assert_true (Duration.parse ("25m") == 25 * M);
        assert_true (Duration.parse ("1h") == H);
        assert_true (Duration.parse ("1h30m") == H + 30 * M);
        assert_true (Duration.parse ("1h2m3s") == H + 2 * M + 3 * S);
        assert_true (Duration.parse ("1h3s") == H + 3 * S);
        assert_true (Duration.parse (" 25M ") == 25 * M);
        assert_true (Duration.parse ("1h 25m") == H + 25 * M);
        assert_true (Duration.parse ("1h  2m 3s") == H + 2 * M + 3 * S);
    });

    Test.add_func ("/cli/normalises", () => {
        assert_true (Duration.parse ("90m") == 90 * M);
        assert_true (Duration.parse ("90s") == 90 * S);
        assert_true (Duration.parse ("23h59m59s") == Duration.MAX);
    });

    Test.add_func ("/cli/zero-and-overflow-left-to-caller", () => {
        assert_true (Duration.parse ("0s") == 0);
        assert_true (Duration.parse ("0h0m") == 0);
        assert_true (Duration.parse ("24h") > Duration.MAX);
        assert_true (Duration.parse ("999999h") > Duration.MAX);
    });

    Test.add_func ("/cli/malformed", () => {
        string[] bad = {
            "", " ", "25", "m", "h30", "5x", "5m5", "1m1h", "1h1h", "1s1m",
            "1.5h", "-5m", "+5m", "1 h", "25 m", "1h 30", "1h 1h", "1:30", "1234567s", "5mm", "five",
        };
        foreach (var text in bad) {
            if (Duration.parse (text) != -1) Test.message ("accepted: '%s'", text);
            assert_true (Duration.parse (text) == -1);
        }
    });
}

int main (string[] args) {
    Test.init (ref args);
    add_entry_tests ();
    add_cli_tests ();
    return Test.run ();
}
