/************************************************************************
 * HotGestures-NG — an AutoHotkey v2 library for custom mouse gestures.
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

__New(maxDistance := 0.1, minTrackLen := 100, penColor := 0xE8EEF7) {
        this.MaxDistance := maxDistance
        this.MinTrackLength := minTrackLen
        this.ShowTip := false
        this.Smoothing := 0.3 ;0 = aus, 0.5 = stark (war früher fest 0.5)
        this.GestureTimeout := 2000  ; ms, 0 = kein Timeout
        this.__hDesktop := DllCall("GetDesktopWindow", "ptr")
        this.__drawingBoard := HotGestures.DrawingBoard(penColor)
        this.__timeout := ""
        this.__cancelled := false
		this.MinStep := 4 ; Mindestbewegung in px pro Vektor (siehe Punkt 2)
        this.__shown := false
    }

    __Delete() => this.__drawingBoard.Destroy()

    Register(gesture, comment, callback := "") {
        matchInfo := {
            Gesture: gesture,
            Comment: comment,
            Callback: callback,
            Matrix: HotGestures.DistanceMatrix(gesture),
            Excluded: false
        }
        this.__matchInfos.Set(gesture, matchInfo)
    }

    Unregister(gesture) => this.__matchInfos.Delete(gesture)

    Clear() => this.__matchInfos.Clear()

    Hotkey(keyName, options := "") {
        keyName := GetKeyName(keyName)
        if keyName == ""
            throw Error("invalid key name")

        sendIfNoMoved := !(keyName ~= "Control|Shift|Alt|Win")
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
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)

        this.__lastX := x
        this.__lastY := y
        this.__scaledMinTrackLen := this.MinTrackLength * this.__GetMonitorScale(x, y)

        ; Overlay erst bei der ersten echten Bewegung anzeigen
        this.__startX := x
        this.__startY := y
        this.__shown := false

        this.__trackLen := 0
        this.__match := ""
        this.__vectors := []
        this.__cancelled := false
		
        for , mi in this.__matchInfos {
            mi.Excluded := false
            mi.Matrix.Clear()
        }

        this.Result := {
            Valid: false,
            Vectors: this.__vectors,
            MatchedGesture: "",
            Distance: "",
            Comment: ""
        }

        this.__mouseHook := HotGestures.MouseHook(this.__OnMouseMove.Bind(this))

        ;Sicherheits-Timeout: Geste nach 2 Sekunden automatisch abbrechen
        this.__timeout := ObjBindMethod(this, "Cancel")
        if this.GestureTimeout > 0
            SetTimer(this.__timeout, -(this.GestureTimeout))
    }

    Cancel() {
        this.__cancelled := true
        this.Stop()
    }

    Stop() {
        ; Timeout stoppen
        if this.__timeout {
            SetTimer(this.__timeout, 0)
            this.__timeout := ""
        }

        this.__mouseHook := ""

        if this.__cancelled {
            this.Result.Valid := false
            this.Result.MatchedGesture := ""
            this.Result.Distance := ""
            this.Result.Comment := "Cancelled"
            if this.__shown {
				this.__drawingBoard.Hide()
				this.__shown := false
        }
            return
        }

        if this.__trackLen >= this.__scaledMinTrackLen {
            this.Result.Valid := true
            if this.__match {
                this.Result.MatchedGesture := this.__match.Gesture
                this.Result.Distance := this.__match.Distance
                this.Result.Comment := this.__match.Comment
            }
        }

            if this.__shown {
				this.__drawingBoard.Hide()
				this.__shown := false
        }
    }

    __OnMouseMove(*) {
        ; Hook nur als Trigger, Position über MouseGetPos im logischen AHK-Koordinatensystem
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)

        ; Glättung – reduziert Zittern ohne Richtung zu verfälschen
        if this.Smoothing > 0 {
            x := Round(x * (1 - this.Smoothing) + this.__lastX * this.Smoothing)
            y := Round(y * (1 - this.Smoothing) + this.__lastY * this.Smoothing)
        }

        dx := x - this.__lastX
        dy := y - this.__lastY
        if (dx * dx + dy * dy < this.MinStep * this.MinStep)
            return

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
			
        else if this.__UpdateMatch() && this.ShowTip {
            tip := ""
            if this.__match {
                name := this.__match.Gesture.Name
                comment := this.__match.Comment
                if name != "" && comment != ""
                    tip := name ": " comment
                else if name == ""
                    tip := comment
                else if comment == ""
                    tip := name
            }
            this.__drawingBoard.DrawTip(tip)
        }

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
        ; Für die Mindestlänge reicht hier ein pragmatischer Weg.
        ; Wenn etwas fehlschlägt, fallback auf 1.0 statt kaputten Werten.
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

        hMon := DllCall("MonitorFromPoint", "int64", px | (py << 32), "uint", 2, "ptr")
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
            this.__panels := Map()
            this.__lastX := 0
            this.__lastY := 0
            this.__lastHash := ""
            this.__lastPanel := ""
            this.__BuildPanels()
            this.__lastHash := this.__GetMonitorHash()
        }

        __Delete() => this.Destroy()

        Destroy() {
            for , p in this.__panels {
                ; alten Pen wieder zurücksetzen
                if p.HasOwnProp("oldPen") && p.oldPen
                    DllCall("SelectObject", "ptr", p.dc, "ptr", p.oldPen)

                if p.pen
                    DllCall("DeleteObject", "ptr", p.pen)

                if p.dc && p.hwnd
                    DllCall("ReleaseDC", "ptr", p.hwnd, "ptr", p.dc)

                try p.gui.Destroy()
            }
            this.__panels := Map()
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
                    ; Wenn SelectObject fehlschlägt, räumen wir sauber auf.
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
            bestDist := 999999

            for , p in this.__panels {
                if (x >= p.left && x < p.right && y >= p.top && y < p.bottom)
                    return p

                d := Abs(x - (p.left + p.w // 2)) + Abs(y - (p.top + p.h // 2))
                if (d < bestDist) {
                    bestDist := d
                    best := p
                }
            }

            return best
        }

        Show() {
            hash := this.__GetMonitorHash()
            if (hash != this.__lastHash) {
                this.__BuildPanels()
                this.__lastHash := hash
            }

            for , p in this.__panels
                p.gui.Show("NoActivate x" p.left " y" p.top " w" p.w " h" (p.h - 1))
        }

        __GetMonitorHash() {
            h := ""
            loop MonitorGetCount() {
                MonitorGet(A_Index, &L, &T, &R, &B)
                h .= L "," T "," R "," B "|"
            }
            return h
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

        ; absichtlich leer – Codepfad bleibt erhalten
        DrawTip(text) {
						  
						 
				
							 
        }
    }

    class Gesture extends Array {
        __New(name, vectors?) {
            valid := false
            if IsSet(vectors) {
                if vectors is String {
                    valid := HotGestures.Gesture.VerifyVectorsString(vectors, , &vectorsArr)
                }
                else if vectors is Array {
                    valid := HotGestures.Gesture.VerifyVectorsArray(vectors, &vectorsArr)
                }
            }
            else {
                valid := HotGestures.Gesture.VerifyVectorsString(name, &name, &vectorsArr)
            }

            if !valid
                throw Error("invalid parameter(s)")

            this.Name := name
            super.__New(vectorsArr*)

            ; Vektor-Längen vorab berechnen
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
            for v in vectorsArr {
                if v.Length != 2
                    return false
                if !(v[1] is Integer) || !(v[2] is Integer)
                    return false
                copy.Push([v[1], v[2]])
            }
            return true
        }

        static VerifyVectorsString(vectorsStr, &name?, &vectorsArr?) {
            if res := RegExMatch(vectorsStr, "^(?:(.*):)?((?:-?\d+,-?\d+)(?:\|-?\d+,-?\d+)*)$", &m) {
                name := m[1]
                vectorsArr := []
                loop parse m[2], "|" {
                    v := StrSplit(A_LoopField, ",", , 2)
                    vectorsArr.Push([Integer(v[1]), Integer(v[2])])
                }
            }
            return !!res
        }
    }

    class DistanceMatrix extends Array {
        __New(standard) {
            static INF := NumGet(ObjPtr(&_ := 0x7F800000) + A_PtrSize * 2, "float")

            if !len := standard.Length
                throw Error("invalid parameter")

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
            if (magNew == 0)
                return

            standard := this.Standard
            mags := standard.Magnitudes
            lastRow := this[-1]

            this.Push(newRow := this.RowTemplate.Clone())
            loop standard.Length {
                dot := newVector[1] * standard[A_Index][1] + newVector[2] * standard[A_Index][2]
                dist := 1 - (dot / (magNew * mags[A_Index]))
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
            return this[-1][-1] / (count + i + j - 2)
        }

        Clear() => this.Length := 1
    }
}
