/************************************************************************
 * HotGestures-Continued — an AutoHotkey v2 library for custom mouse gestures.
 *
 * Fork and continuation of HotGestures by Tebayaki (2023), which appears
 * to be unmaintained. Upstream: https://github.com/Tebayaki/HotGestures
 *
 * Copyright (c) 2023 Tebayaki            (original work)
 * Copyright (c) 2026 Christian Berthold  (modifications)
 *
 * Licensed under the MIT License. See LICENSE for the full text.
 *
 * Provided "AS IS", without warranty of any kind. This library installs a
 * system-wide low-level mouse hook. Use at your own risk.
 *
 * Changes against upstream are listed in CHANGELOG.md.
 ***********************************************************************/

class HotGestures {
    __matchInfos := Map()

    /**
     * @param maxDistance  match tolerance, 0..2 — lower is stricter
     * @param minTrackLen  minimum track length in logical px
     * @param penColor     COLORREF (0x00BBGGRR), NOT RGB — see README
     */
    __New(maxDistance := 0.1, minTrackLen := 100, penColor := 0xE8EEF7) {
        this.MaxDistance    := maxDistance
        this.MinTrackLength := minTrackLen

        ; Exponential smoothing of the pointer position. 0 disables.
        ; Clamped to 0..0.95 at Start(); at 1 no movement would ever register.
        ; Note it is applied BEFORE the MinStep test, so the effective step is
        ; roughly MinStep / (1 - Smoothing).
        this.Smoothing := 0.3

        ; Minimum movement in px before a vector is recorded. 0 records every move.
        this.MinStep := 4

        ; Safety net: cancel a gesture that is never finished. 0 disables.
        this.GestureTimeout := 2000

        ; Hard upper bound on recorded vectors. Protects against an unbounded
        ; matrix when the button is held and the mouse keeps moving. 0 disables,
        ; which is NOT recommended — cost per move grows with the vector count.
        this.MaxVectors := 1500

        this.__hDesktop     := DllCall("GetDesktopWindow", "ptr")
        this.__drawingBoard := HotGestures.DrawingBoard(penColor)
        this.__cancelFn     := ""
        this.__cancelled    := false
        this.__running      := false
        this.__shown        := false
        this.__match        := ""
        this.__vectors      := []
    }

    __Delete() => this.Destroy()

    /**
     * Releases the overlay windows and GDI objects.
     *
     * Note: an instance passed to Hotkey() is referenced by AHK's global
     * hotkey table and is therefore never collected, so __Delete will not
     * run on its own. Call Destroy() explicitly if you discard an instance.
     */
    Destroy() {
        try this.Stop()
        if this.__drawingBoard {
            this.__drawingBoard.Destroy()
            this.__drawingBoard := ""
        }
    }

    Register(gesture, comment, callback := "") {
        if !(gesture is HotGestures.Gesture)
            throw TypeError("Register expects a HotGestures.Gesture", , Type(gesture))

        matchInfo := {
            Gesture:  gesture,
            Comment:  comment,
            Callback: callback,
            Matrix:   HotGestures.DistanceMatrix(gesture),
            Excluded: false,
            Distance: ""
        }
        this.__matchInfos.Set(gesture, matchInfo)
    }

    Unregister(gesture) => this.__matchInfos.Delete(gesture)

    Clear() => this.__matchInfos.Clear()

    Hotkey(keyName, options := "") {
        keyName := GetKeyName(keyName)
        if keyName == ""
            throw Error("invalid key name")

        sendIfNoMoved := !(keyName ~= "i)Control|Shift|Alt|Win")
        Hotkey("$" keyName, OnHotkey, options)

        OnHotkey(_) {
            this.Start()
            KeyWait(keyName)
            this.Stop()

            if this.Result.Valid {
                if this.__match && this.__match.Callback is Func
                    this.__match.Callback.Call(this.Result)
            }
            else if sendIfNoMoved {
                Send("{" keyName "}")
            }
        }
    }

    StartAndWait(keyName, &result) {
        if GetKeyName(keyName) == ""
            throw Error("invalid key name", , keyName)

        this.Start()
        KeyWait(keyName)
        this.Stop()
        result := this.Result
        return this.Result.Valid
    }

    Start() {
        ; A second Start() without Stop() would orphan the running timer and
        ; the installed hook, so wind the previous gesture down first.
        if this.__running
            this.Stop()

        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)

        this.__lastX := x
        this.__lastY := y
        this.__startX := x
        this.__startY := y
        this.__scaledMinTrackLen := this.MinTrackLength * this.__GetMonitorScale(x, y)

        ; Normalise the user-settable knobs once per gesture instead of
        ; re-validating them inside the hook callback.
        s := this.Smoothing
        this.__smoothing  := s < 0 ? 0 : (s > 0.95 ? 0.95 : s)
        step              := this.MinStep < 0 ? 0 : this.MinStep
        this.__minStepSq  := step * step
        this.__maxVectors := this.MaxVectors < 0 ? 0 : this.MaxVectors

        this.__trackLen  := 0
        this.__match     := ""
        this.__vectors   := []
        this.__cancelled := false
        this.__shown     := false

        for , mi in this.__matchInfos {
            mi.Excluded := false
            mi.Distance := ""
            mi.Matrix.Clear()
        }

        this.Result := {
            Valid:          false,
            Vectors:        this.__vectors,
            MatchedGesture: "",
            Distance:       "",
            Comment:        ""
        }

        ; Rebuild the overlays here, in a normal thread. Doing this inside the
        ; mouse hook risks exceeding LowLevelHooksTimeout, after which Windows
        ; silently removes the hook.
        this.__drawingBoard.EnsurePanels()

        ; Install the hook first: if it fails, nothing is left half-armed.
        this.__mouseHook := HotGestures.MouseHook(this.__OnMouseMove.Bind(this))

        ; One bound function per gesture, cleared in Stop(). Reusing it for both
        ; the timeout and the vector-cap abort keeps SetTimer unambiguous.
        this.__cancelFn := ObjBindMethod(this, "Cancel")
        this.__running := true

        if this.GestureTimeout > 0
            SetTimer(this.__cancelFn, -(this.GestureTimeout))
    }

    Cancel() {
        if !this.__running
            return
        this.__cancelled := true
        this.Stop()
    }

    Stop() {
        if !this.__running
            return
        this.__running := false

        if this.__cancelFn {
            SetTimer(this.__cancelFn, 0)
            this.__cancelFn := ""
        }

        this.__mouseHook := ""

        if this.__cancelled {
            this.Result.Valid          := false
            this.Result.MatchedGesture := ""
            this.Result.Distance       := ""
            this.Result.Comment        := "Cancelled"
        }
        else if this.__trackLen >= this.__scaledMinTrackLen {
            this.Result.Valid := true
            if this.__match {
                this.Result.MatchedGesture := this.__match.Gesture
                this.Result.Distance       := this.__match.Distance
                this.Result.Comment        := this.__match.Comment
            }
        }

        this.__HideBoard()
    }

    __HideBoard() {
        if this.__shown {
            this.__drawingBoard.Hide()
            this.__shown := false
        }
    }

    __OnMouseMove(*) {
        if this.__cancelled
            return

        ; The hook is only a trigger. The hook's own coordinates are physical
        ; pixels, while the rest of AHK v2 works in logical ones.
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)

        if this.__smoothing > 0 {
            x := Round(x * (1 - this.__smoothing) + this.__lastX * this.__smoothing)
            y := Round(y * (1 - this.__smoothing) + this.__lastY * this.__smoothing)
        }

        dx := x - this.__lastX
        dy := y - this.__lastY
        if (dx * dx + dy * dy < this.__minStepSq)
            return

        ; Hard cap. Abort rather than let the matrices grow without bound.
        ; The actual teardown runs on a normal thread, because releasing the
        ; hook object from inside its own callback frees a callback that is
        ; still executing.
        if (this.__maxVectors > 0 && this.__vectors.Length >= this.__maxVectors) {
            this.__cancelled := true
            if this.__cancelFn
                SetTimer(this.__cancelFn, -1)
            return
        }

        if !this.__shown {
            this.__drawingBoard.Show()
            this.__drawingBoard.MoveTo(this.__startX, this.__startY)
            this.__shown := true
        }

        this.__drawingBoard.DrawLineTo(x, y)

        newVector := [dx, dy]
        this.__vectors.Push(newVector)
        this.__BuildMatrixes(newVector)

        if this.__trackLen < this.__scaledMinTrackLen
            this.__trackLen += Sqrt(dx * dx + dy * dy)
        else
            this.__UpdateMatch()

        this.__lastX := x
        this.__lastY := y
    }

    __BuildMatrixes(newVector) {
        for , mi in this.__matchInfos
            if !mi.Excluded
                mi.Matrix.Append(newVector)
    }

    __UpdateMatch() {
        match := ""
        minDist := this.MaxDistance

        for , mi in this.__matchInfos {
            ; An excluded matrix is frozen, so its TraceBack is constant and
            ; already above the threshold. Re-running it costs O(rows).
            if mi.Excluded
                continue

            distance := mi.Matrix.TraceBack()
            if distance <= minDist {
                mi.Distance := minDist := distance
                match := mi
            }
            else if distance > 1 {
                mi.Excluded := true
            }
        }

        if this.__match == match
            return false

        this.__match := match
        return true
    }

    __GetMonitorScale(x, y) {
        ; Only used to scale MinTrackLength. Any failure falls back to 1.0
        ; rather than feeding a broken value into the threshold.
        pt := Buffer(8, 0)
        NumPut("int", x, pt, 0)
        NumPut("int", y, pt, 4)

        try ok := DllCall("LogicalToPhysicalPointForPerMonitorDPI", "ptr", this.__hDesktop, "ptr", pt, "int")
        catch
            return 1.0

        if !ok
            return 1.0

        px := NumGet(pt, 0, "int")
        py := NumGet(pt, 4, "int")

        ; px must be masked: a negative x is sign-extended across all 64 bits,
        ; and the OR would then overwrite the packed y with -1. Monitors left
        ; of the primary one have negative coordinates.
        pack := (px & 0xFFFFFFFF) | (py << 32)

        hMon := DllCall("MonitorFromPoint", "int64", pack, "uint", 2, "ptr")
        if !hMon
            return 1.0

        try hr := DllCall("Shcore.dll\GetDpiForMonitor", "ptr", hMon, "uint", 0, "uint*", &dpiX := 0, "uint*", &dpiY := 0, "int")
        catch
            return 1.0

        if (hr != 0 || dpiX = 0)
            return 1.0

        return dpiX / 96
    }

    class MouseHook {
        __New(function) {
            this.__proc := CallbackCreate(LowLevelMouseHookProc, "F")
            this.__hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", this.__proc, "ptr", 0, "uint", 0, "ptr")

            if !this.__hook {
                CallbackFree(this.__proc)
                this.__proc := 0
                throw Error("SetWindowsHookEx failed")
            }

            LowLevelMouseHookProc(nCode, wParam, lParam) {
                if nCode == 0 && wParam == 0x0200
                    function()
                return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
            }
        }

        __Delete() {
            if this.__hook
                DllCall("UnhookWindowsHookEx", "ptr", this.__hook)
            if this.__proc
                CallbackFree(this.__proc)
        }
    }

    class DrawingBoard {
        __New(penColor) {
            this.__penColor := penColor
            this.__panels   := Map()
            this.__lastX    := 0
            this.__lastY    := 0
            this.__lastHash := ""
            this.__lastPanel := ""
            this.__BuildPanels()
            this.__lastHash := this.__GetMonitorHash()
        }

        __Delete() => this.Destroy()

        Destroy() {
            for , p in this.__panels {
                if p.HasOwnProp("oldPen") && p.oldPen
                    DllCall("SelectObject", "ptr", p.dc, "ptr", p.oldPen)

                if p.pen
                    DllCall("DeleteObject", "ptr", p.pen)

                if p.dc && p.hwnd
                    DllCall("ReleaseDC", "ptr", p.hwnd, "ptr", p.dc)

                try p.gui.Destroy()
            }
            this.__panels := Map()
            this.__lastPanel := ""
            this.__lastHash  := ""
        }

        /**
         * Rebuilds the overlays if the monitor layout changed. Call this from
         * a normal thread, never from the hook callback.
         */
        EnsurePanels() {
            hash := this.__GetMonitorHash()
            if (hash != this.__lastHash || this.__panels.Count = 0) {
                this.__BuildPanels()
                this.__lastHash := hash
            }
        }

        __BuildPanels() {
            this.Destroy()

            loop MonitorGetCount() {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                w := right - left
                h := bottom - top

                g := Gui("+LastFound +AlwaysOnTop +ToolWindow +E0x00000020 -Caption -DPIScale")
                g.BackColor := 0
                WinSetTransColor(0, g)

                hwnd := g.Hwnd
                dc := DllCall("GetDC", "ptr", hwnd, "ptr")
                if !dc {
                    try g.Destroy()
                    continue
                }

                pen := DllCall("CreatePen", "int", 0, "int", 1, "int", this.__penColor, "ptr")
                if !pen {
                    DllCall("ReleaseDC", "ptr", hwnd, "ptr", dc)
                    try g.Destroy()
                    continue
                }

                oldPen := DllCall("SelectObject", "ptr", dc, "ptr", pen, "ptr")
                if !oldPen {
                    DllCall("DeleteObject", "ptr", pen)
                    DllCall("ReleaseDC", "ptr", hwnd, "ptr", dc)
                    try g.Destroy()
                    continue
                }

                this.__panels[A_Index] := {
                    gui:    g,
                    hwnd:   hwnd,
                    dc:     dc,
                    pen:    pen,
                    oldPen: oldPen,
                    left:   left,
                    top:    top,
                    right:  right,
                    bottom: bottom,
                    w:      w,
                    h:      h
                }
            }
        }

        __GetPanel(x, y) {
            best := ""
            bestDist := ""

            for , p in this.__panels {
                if (x >= p.left && x < p.right && y >= p.top && y < p.bottom)
                    return p

                d := Abs(x - (p.left + p.w // 2)) + Abs(y - (p.top + p.h // 2))
                if (bestDist = "" || d < bestDist) {
                    bestDist := d
                    best := p
                }
            }

            return best
        }

        __GetMonitorHash() {
            h := ""
            loop MonitorGetCount() {
                MonitorGet(A_Index, &L, &T, &R, &B)
                h .= L "," T "," R "," B "|"
            }
            return h
        }

        Show() {
            for , p in this.__panels
                p.gui.Show("NoActivate x" p.left " y" p.top " w" p.w " h" (p.h - 1))
        }

        Hide() {
            for , p in this.__panels {
                DllCall("RedrawWindow", "ptr", p.hwnd, "ptr", 0, "ptr", 0, "uint", 0x105)
                p.gui.Hide()
            }
        }

        MoveTo(x, y) {
            this.__lastX := x
            this.__lastY := y
            p := this.__GetPanel(x, y)
            this.__lastPanel := p
            if (p = "" || !p.dc)
                return
            DllCall("MoveToEx", "ptr", p.dc, "int", x - p.left, "int", y - p.top, "ptr", 0)
        }

        DrawLineTo(x, y) {
            p := this.__GetPanel(x, y)
            if (p = "" || !p.dc)
                return

            lp := this.__lastPanel
            if (lp = "" || p.left != lp.left || p.top != lp.top)
                DllCall("MoveToEx", "ptr", p.dc, "int", x - p.left, "int", y - p.top, "ptr", 0)

            DllCall("LineTo", "ptr", p.dc, "int", x - p.left, "int", y - p.top)

            this.__lastPanel := p
            this.__lastX := x
            this.__lastY := y
        }
    }

    class Gesture extends Array {
        __New(name, vectors?) {
            valid := false
            if IsSet(vectors) {
                if vectors is String
                    valid := HotGestures.Gesture.VerifyVectorsString(vectors, , &vectorsArr)
                else if vectors is Array
                    valid := HotGestures.Gesture.VerifyVectorsArray(vectors, &vectorsArr)
            }
            else {
                valid := HotGestures.Gesture.VerifyVectorsString(name, &name, &vectorsArr)
            }

            if !valid
                throw ValueError("invalid gesture vectors — expected `"[name:]x,y[|x,y]...`" with at least one non-zero vector")

            this.Name := name
            super.__New(vectorsArr*)

            ; Precomputed so the matcher does not call Sqrt per comparison.
            this.Magnitudes := []
            for v in this
                this.Magnitudes.Push(Sqrt(v[1]**2 + v[2]**2))
        }

        ToString() {
            vectorsStr := ""
            for v in this
                vectorsStr .= (A_Index == 1 ? "" : "|") v[1] "," v[2]
            return vectorsStr
        }

        Compare(vectors) {
            matrix := HotGestures.DistanceMatrix(this)
            for v in vectors
                matrix.Append(v)
            return matrix.TraceBack()
        }

        static VerifyVectorsArray(vectorsArr, &copy) {
            copy := []
            if !(vectorsArr is Array)
                return false

            for v in vectorsArr {
                if !(v is Array) || v.Length != 2
                    return false
                if !(v[1] is Integer) || !(v[2] is Integer)
                    return false
                ; A zero-length vector has no direction. It would divide by zero
                ; in the matcher, so it is rejected at construction time.
                if (v[1] = 0 && v[2] = 0)
                    return false
                copy.Push([v[1], v[2]])
            }
            return copy.Length > 0
        }

        static VerifyVectorsString(vectorsStr, &name?, &vectorsArr?) {
            if !(vectorsStr is String)
                return false

            ; Digits are bounded so Integer() cannot be fed an overflowing literal.
            if !RegExMatch(vectorsStr, "^(?:(.*):)?((?:-?\d{1,9},-?\d{1,9})(?:\|-?\d{1,9},-?\d{1,9})*)$", &m)
                return false

            arr := []
            loop parse m[2], "|" {
                v := StrSplit(A_LoopField, ",", , 2)
                a := Integer(v[1])
                b := Integer(v[2])
                if (a = 0 && b = 0)
                    return false
                arr.Push([a, b])
            }

            ; Only write the byref outputs once the input is known good.
            name := m[1]
            vectorsArr := arr
            return true
        }
    }

    class DistanceMatrix extends Array {
        ; Not an actual infinity. The previous version read the raw bytes of a
        ; VarRef to synthesise one, which depends on AHK's internal memory
        ; layout and would break silently on a layout change. Real DTW costs
        ; stay well below 1e5 (max 2 per step), so this sentinel is equivalent
        ; and survives any AHK version.
        static INF := 1.0e15

        __New(standard) {
            if !len := standard.Length
                throw ValueError("DistanceMatrix needs a gesture with at least one vector")
            if !(standard.HasOwnProp("Magnitudes") && standard.Magnitudes.Length = len)
                throw ValueError("DistanceMatrix expects a HotGestures.Gesture")

            INF := HotGestures.DistanceMatrix.INF

            this.Standard := standard
            this.Capacity := len + 1

            this.RowTemplate := []
            this.RowTemplate.Capacity := len + 1
            this.RowTemplate.Push(INF)

            this.Push(firstRow := this.RowTemplate.Clone())
            firstRow[1] := 0
            loop len
                firstRow.Push(INF)
        }

        Append(newVector) {
            magNew := Sqrt(newVector[1]**2 + newVector[2]**2)
            if (magNew = 0)
                return

            standard := this.Standard
            mags := standard.Magnitudes
            lastRow := this[-1]

            this.Push(newRow := this.RowTemplate.Clone())
            loop standard.Length {
                denom := magNew * mags[A_Index]
                if (denom = 0) {
                    ; Defence in depth — zero vectors are rejected at
                    ; construction, so this should be unreachable. 2 is the
                    ; maximum possible cosine distance.
                    dist := 2.0
                }
                else {
                    dot := newVector[1] * standard[A_Index][1] + newVector[2] * standard[A_Index][2]
                    dist := 1 - (dot / denom)
                }
                newRow.Push(dist + Min(newRow[A_Index], lastRow[A_Index], lastRow[A_Index + 1]))
            }
        }

        TraceBack() {
            i := this.Length - 1, j := this[1].Length - 1, count := 1
            while i > 1 && j > 1 {
                switch min(a := this[i][j], b := this[i][j + 1], this[i + 1][j]) {
                    case a: i--, j--
                    case b: i--
                    default: j--
                }
                count++
            }

            denom := count + i + j - 2
            if (denom <= 0)
                return 2.0      ; nothing to compare against — maximum distance

            return this[-1][-1] / denom
        }

        Clear() => this.Length := 1
    }
}
