;==========================================================
;  Self-test for the parts of HotGestures that can be
;  verified without a mouse, a hook or a GUI.
;
;  Run it: double-click, or  AutoHotkey.exe tests\selftest.ahk
;  It prints a report and exits with code 0 (pass) or 1 (fail).
;
;  Part of HotGestures-Continued. MIT licensed, see ../LICENSE.
;==========================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

#Include ..\HotGestures.ahk

global TESTS_RUN := 0, TESTS_FAILED := 0, REPORT := ""

RunAll()
Report()

RunAll() {
    ; ---------- VerifyVectorsString: valid input ----------
    Ok("plain vectors",
        HotGestures.Gesture.VerifyVectorsString("1,0", , &a) && a.Length = 1 && a[1][1] = 1 && a[1][2] = 0)

    Ok("multiple vectors",
        HotGestures.Gesture.VerifyVectorsString("1,0|0,-2|-3,4", , &a) && a.Length = 3 && a[3][1] = -3 && a[3][2] = 4)

    Ok("named",
        HotGestures.Gesture.VerifyVectorsString("Left:-1,0", &n, &a) && n = "Left" && a.Length = 1)

    Ok("name containing a colon",
        HotGestures.Gesture.VerifyVectorsString("a:b:1,0", &n, &a) && n = "a:b")

    Ok("empty name",
        HotGestures.Gesture.VerifyVectorsString(":1,0", &n, &a) && n = "")

    ; ---------- VerifyVectorsString: rejected input ----------
    Fails("empty string",        () => HotGestures.Gesture.VerifyVectorsString("", , &a))
    Fails("letters",             () => HotGestures.Gesture.VerifyVectorsString("a,b", , &a))
    Fails("trailing separator",  () => HotGestures.Gesture.VerifyVectorsString("1,0|", , &a))
    Fails("missing component",   () => HotGestures.Gesture.VerifyVectorsString("1,", , &a))
    Fails("float values",        () => HotGestures.Gesture.VerifyVectorsString("1.5,0", , &a))

    ; A zero vector has no direction and used to divide by zero in the matcher.
    Fails("zero vector alone",   () => HotGestures.Gesture.VerifyVectorsString("0,0", , &a))
    Fails("zero vector in list", () => HotGestures.Gesture.VerifyVectorsString("1,0|0,0|1,0", , &a))

    ; Bounded digits keep Integer() away from an overflowing literal.
    Fails("overlong number",     () => HotGestures.Gesture.VerifyVectorsString("99999999999999999999,0", , &a))

    ; ---------- VerifyVectorsArray ----------
    Ok("array form",
        HotGestures.Gesture.VerifyVectorsArray([[1, 0], [0, 2]], &c) && c.Length = 2)

    Fails("array, wrong arity",  () => HotGestures.Gesture.VerifyVectorsArray([[1, 0, 3]], &c))
    Fails("array, non-integer",  () => HotGestures.Gesture.VerifyVectorsArray([[1.5, 0]], &c))
    Fails("array, zero vector",  () => HotGestures.Gesture.VerifyVectorsArray([[1, 0], [0, 0]], &c))
    Fails("array, empty",        () => HotGestures.Gesture.VerifyVectorsArray([], &c))

    ; ---------- Gesture ----------
    g := HotGestures.Gesture("Right:10,0|10,0")
    Ok("gesture name",      g.Name = "Right")
    Ok("gesture length",    g.Length = 2)
    Ok("round trip",        g.ToString() = "10,0|10,0")
    Ok("magnitudes",        Near(g.Magnitudes[1], 10) && Near(g.Magnitudes[2], 10))

    g2 := HotGestures.Gesture("Diag:3,4")
    Ok("magnitude 3-4-5",   Near(g2.Magnitudes[1], 5))

    Throws("zero-vector gesture throws", () => HotGestures.Gesture("Bad:0,0"))
    Throws("garbage gesture throws",     () => HotGestures.Gesture("not a gesture"))

    ; ---------- DistanceMatrix ----------
    Throws("matrix needs a Gesture", () => HotGestures.DistanceMatrix([[1, 0]]))

    Ok("INF sentinel is finite and large",
        HotGestures.DistanceMatrix.INF > 1.0e12 && HotGestures.DistanceMatrix.INF < 1.0e18)

    ; Same direction -> distance at the bottom of the range.
    right := HotGestures.Gesture("R:10,0|10,0|10,0")
    dSame := right.Compare([[10, 0], [10, 0], [10, 0]])
    Ok("identical track matches", dSame < 0.01, "distance=" dSame)

    ; Opposite direction -> near the top of the range (cosine distance 2).
    dOpp := right.Compare([[-10, 0], [-10, 0], [-10, 0]])
    Ok("opposite track does not match", dOpp > 1.5, "distance=" dOpp)

    ; Perpendicular -> cosine distance 1.
    dPerp := right.Compare([[0, 10], [0, 10], [0, 10]])
    Ok("perpendicular track ~1", Near(dPerp, 1, 0.05), "distance=" dPerp)

    ; Scale invariance: direction matters, length does not.
    dScaled := right.Compare([[1, 0], [1, 0], [1, 0]])
    Ok("scale invariant", Near(dScaled, dSame, 0.01), "distance=" dScaled)

    ; An empty track used to divide by zero in TraceBack.
    dEmpty := right.Compare([])
    Ok("empty track returns max distance, no crash", dEmpty = 2.0, "distance=" dEmpty)

    one := HotGestures.Gesture("One:1,0")
    Ok("single-vector gesture, empty track", one.Compare([]) = 2.0)
    Ok("single-vector gesture, one step",    one.Compare([[1, 0]]) < 0.01)

    ; ---------- POINT packing for MonitorFromPoint ----------
    ; A negative x is sign-extended over all 64 bits. Without the mask the OR
    ; overwrites the packed y with -1, so the DPI of the wrong monitor is read.
    Ok("packing, positive coordinates", PackRoundTrip(100, 200))
    Ok("packing, negative x",           PackRoundTrip(-8640, 0))
    Ok("packing, negative x and y",     PackRoundTrip(-5760, -1080))
    Ok("packing, negative y only",      PackRoundTrip(1920, -1080))
    Ok("unmasked packing is broken",    !PackRoundTripUnmasked(-8640, 500))
}

;----------------------------------------------------------
;  Helpers
;----------------------------------------------------------

PackRoundTrip(px, py) {
    v := (px & 0xFFFFFFFF) | (py << 32)
    return UnpackX(v) = px && UnpackY(v) = py
}

PackRoundTripUnmasked(px, py) {
    v := px | (py << 32)
    return UnpackX(v) = px && UnpackY(v) = py
}

UnpackX(v) {
    lo := v & 0xFFFFFFFF
    return lo >= 0x80000000 ? lo - 0x100000000 : lo
}

UnpackY(v) {
    hi := (v >> 32) & 0xFFFFFFFF
    return hi >= 0x80000000 ? hi - 0x100000000 : hi
}

Near(a, b, tol := 0.0001) => Abs(a - b) <= tol

Ok(label, condition, extra := "") {
    global TESTS_RUN, TESTS_FAILED, REPORT
    TESTS_RUN++
    if condition {
        REPORT .= "  PASS  " label (extra ? "   (" extra ")" : "") "`n"
    }
    else {
        TESTS_FAILED++
        REPORT .= "> FAIL  " label (extra ? "   (" extra ")" : "") "`n"
    }
}

/** Expects fn() to return a falsy value (validation rejects the input). */
Fails(label, fn) {
    local result := true
    try
        result := fn()
    catch as err
        result := "threw: " err.Message
    Ok(label, result = false || result = 0, result = false || result = 0 ? "" : "returned " result)
}

/** Expects fn() to throw. */
Throws(label, fn) {
    local threw := false
    try
        fn()
    catch
        threw := true
    Ok(label, threw)
}

Report() {
    global TESTS_RUN, TESTS_FAILED, REPORT
    head := TESTS_FAILED = 0
        ? "All " TESTS_RUN " checks passed."
        : TESTS_FAILED " of " TESTS_RUN " checks FAILED."

    MsgBox(head "`n`n" REPORT, "HotGestures self-test", TESTS_FAILED = 0 ? "Iconi" : "Icon!")
    ExitApp(TESTS_FAILED = 0 ? 0 : 1)
}
