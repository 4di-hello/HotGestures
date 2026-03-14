;HotGestures_optimiert.ahk

/************************************************************************
 * @description An Autohotkey library for creating and recognizing any custom mouse gestures.
 * @author Tebayaki
 * @date 2023/9/30
 * @version 1.0
 * github Tebayaki HotGestures
 * Multi-monitor / mixed DPI fix by 4di-hello, 2026
 ***********************************************************************/
; Farbe angepasst auf 0xE8EEF7 bei "penColor :=" | 0xE8EEF7  ; "pale steel blue"
; Stiftdicke "1" angepasst bei DllCall("CreatePen", "int", 0, "int", 1, "int", penColor, "ptr")
; Tooltip auskommentiert: "this.__drawingBoard.DrawTip(tip)"

class HotGestures {
    __matchInfos := Map()

    __New(maxDistance := 0.1, minTrackLen := 100, penColor := 0xE8EEF7) {
        this.MaxDistance := maxDistance
        this.MinTrackLength := minTrackLen
        this.__drawingBoard := HotGestures.DrawingBoard(penColor)
    }

    __Delete() => this.__drawingBoard.Destroy()

    Register(gesture, comment, callback := "") {
        matchInfo := { Gesture: gesture, Comment: comment, Callback: callback, Matrix: HotGestures.DistanceMatrix(gesture), Excluded: false }
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
        this.__scaledMinTrackLen := this.MinTrackLength * this.__GetMonitorDPI(x, y)
        this.__drawingBoard.MoveTo(x, y)
        this.__trackLen := 0
        this.__match := ""
        this.__vectors := []
        for , mi in this.__matchInfos {
            mi.Excluded := false
            mi.Matrix.Clear()
        }
        this.Result := { Valid: false, Vectors: this.__vectors, MatchedGesture: "", Distance: "", Comment: "" }
        this.__mouseHook := HotGestures.MouseHook(this.__OnMouseMove.Bind(this))
        this.__drawingBoard.Show()
    }

    Stop() {
        this.__mouseHook := ""
        if this.__trackLen >= this.__scaledMinTrackLen {
            this.Result.Valid := true
            if this.__match {
                this.Result.MatchedGesture := this.__match.Gesture
                this.Result.Distance := this.__match.Distance
                this.Result.Comment := this.__match.Comment
            }
        }
        this.__drawingBoard.Hide()
    }

    __OnMouseMove(x, y) {
        ; Physische Hook-Koordinaten → Logische Koordinaten
        pt := Buffer(8, 0)
        NumPut("int", x, pt, 0)
        NumPut("int", y, pt, 4)
        DllCall("PhysicalToLogicalPointForPerMonitorDPI", "ptr", 0, "ptr", pt)
        x := NumGet(pt, 0, "int")
        y := NumGet(pt, 4, "int")
        ; anti-shake
        x := (x + this.__lastX) // 2
        y := (y + this.__lastY) // 2
        if x == this.__lastX && y == this.__lastY
            return
        this.__drawingBoard.DrawLineTo(x, y)

        vx := x - this.__lastX
        vy := y - this.__lastY
        newVector := [vx, vy]
        this.__vectors.Push(newVector)
        this.__BuildMatrixes(newVector)

        if this.__trackLen < this.__scaledMinTrackLen
            this.__trackLen += Sqrt(vx * vx + vy * vy)
        else if this.__UpdateMatch() {
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
            ;this.__drawingBoard.DrawTip(tip)
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

    class MouseHook {
        __New(function) {
            this.__proc := CallbackCreate(LowLevelMouseHookProc, "F")
            this.__hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", this.__proc, "ptr", 0, "uint", 0, "ptr")

            LowLevelMouseHookProc(nCode, wParam, lParam) {
                if nCode == 0 && wParam == 0x0200
                    function(NumGet(lParam, "int"), NumGet(lParam, 4, "int"))
                return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
            }
        }

        __Delete() {
            DllCall("UnhookWindowsHookEx", "ptr", this.__hook)
            CallbackFree(this.__proc)
        }
    }

    class DrawingBoard {
        __New(penColor) {
            this.__penColor := penColor
            this.__panels   := Map()
            this.__lastX    := 0
            this.__lastY    := 0
            this.__BuildPanels()
        }

        __Delete() => this.Destroy()

        Destroy() {
            for , p in this.__panels {
                DllCall("DeleteObject", "ptr", p.pen)
                DllCall("ReleaseDC",   "ptr", p.hwnd, "ptr", p.dc)
                try p.gui.Destroy()
            }
            this.__panels := Map()
        }

        __BuildPanels() {
            this.Destroy()
            loop MonitorGetCount() {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                w := right  - left
                h := bottom - top

                g := Gui("+LastFound +AlwaysOnTop +ToolWindow +E0x00000020 -Caption -DPIScale")
                g.BackColor := 0
                WinSetTransColor(0, g)

                hwnd := g.Hwnd
                dc   := DllCall("GetDC",     "ptr", hwnd, "ptr")
                pen  := DllCall("CreatePen", "int", 0, "int", 1, "int", this.__penColor, "ptr")
                DllCall("SelectObject", "ptr", dc, "ptr", pen)

                this.__panels[A_Index] := {
                    gui:    g,
                    hwnd:   hwnd,
                    dc:     dc,
                    pen:    pen,
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
            for , p in this.__panels
                if (x >= p.left && x < p.right && y >= p.top && y < p.bottom)
                    return p
            ; Fallback: Panel mit kleinstem Abstand zur Mitte
            best := ""
            bestDist := 999999
            for , p in this.__panels {
                cx := p.left + p.w // 2
                cy := p.top  + p.h // 2
                d  := Abs(x - cx) + Abs(y - cy)
                if (d < bestDist) {
                    bestDist := d
                    best := p
                }
            }
            return best
        }

        Show() {
            this.__BuildPanels()
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
            if (p = "")
                return
	   
            DllCall("MoveToEx", "ptr", p.dc, "int", x - p.left, "int", y - p.top, "ptr", 0)
        }

        DrawLineTo(x, y) {
            p  := this.__GetPanel(x, y)
            if (p = "")
                return
            lp := this.__GetPanel(this.__lastX, this.__lastY)
            if (lp = "" || p.left != lp.left || p.top != lp.top)
                DllCall("MoveToEx", "ptr", p.dc, "int", x - p.left, "int", y - p.top, "ptr", 0)
            DllCall("LineTo", "ptr", p.dc, "int", x - p.left, "int", y - p.top)
            this.__lastX := x
            this.__lastY := y
        }

        ; DrawTip absichtlich leer – Tooltip deaktiviert
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
            if !valid {
                throw Error("invalid parameter(s)")
            }
            this.Name := name
            super.__New(vectorsArr*)
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
            static Distance(a, b) => 1 - (a[1] * b[1] + a[2] * b[2]) / (Sqrt(a[1] ** 2 + a[2] ** 2) * Sqrt(b[1] ** 2 + b[2] ** 2))

            standard := this.Standard
            lastRow := this[-1]

            this.Push(newRow := this.RowTemplate.Clone())
            loop standard.Length
                newRow.Push(Distance(newVector, standard[A_Index]) + Min(newRow[A_Index], lastRow[A_Index], lastRow[A_Index + 1]))
        }

        TraceBack() {
            i := this.Length - 1 , j := this[1].Length - 1 , count := 1
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

    __GetMonitorDPI(x, y) {
        hMon := DllCall("MonitorFromPoint", "int64", x | (y << 32), "uint", 2, "ptr")
        DllCall("Shcore.dll\GetDpiForMonitor", "ptr", hMon, "uint", 0, "uint*", &dpiX := 0, "uint*", &dpiY := 0)
        return dpiX / 96
    }
}
