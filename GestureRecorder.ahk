;==========================================================
;  Gesture Recorder — draw gestures, name them, export code.
;
;  Part of HotGestures-Continued. MIT licensed, see LICENSE.
;  Provided "AS IS", without warranty of any kind.
;==========================================================

#Include HotGestures.ahk
GestureRecorder()

; Pen color for the live track, as a COLORREF (0x00BBGGRR, not RGB).
; Deliberately loud: the recorder draws on a white board, and the library's
; default is a pale grey that is nearly invisible there. Keep it different
; from whatever you use in your own script, so you can tell the recorder's
; overlay apart from your everyday one.
global RECORDER_PEN := 0xFE4F7F

; Delimiters for the block written into an existing script. Everything between
; them is replaced on the next export, so hand-written code must stay outside.
global MARKER_BEGIN := "; === HOTGESTURES-CONTINUED: GESTURES BEGIN (generated, do not edit) ==="
global MARKER_END   := "; === HOTGESTURES-CONTINUED: GESTURES END ==="

GestureRecorder() {
    hgs := HotGestures(0.1, 100, RECORDER_PEN)
    testing := false
    animation := ""
    itemIndex := 1

    mainWindow := Gui(, "Gesture Recorder")
    mainWindow.SetFont(, "Cascadia Code")
    mainWindow.AddText(, "Right button: draw | F2: edit name | Ctrl+C: copy vectors")
    addBtn := mainWindow.AddButton("Section w120", "Add")
    deleteBtn := mainWindow.AddButton("x+M wp", "Delete")
    genCodeBtn := mainWindow.AddButton("x+M wp", "Generate Code")
    testBtn := mainWindow.AddButton("x+M wp", "Test")
    mainWindow.AddText("x+M wp hp-5 Center 0x200", "Max Distance:")
    distanceEdit := mainWindow.AddEdit("x+M w100", "0.1")
    listview := mainWindow.AddListView("-ReadOnly Center Grid xs w500 h500", ["Name", "Vectors"])
    drawingBoard := mainWindow.AddText("BackgroundWhite Center w500 h500 x+M")
    statusBar := mainWindow.AddStatusBar()

    listview.ModifyCol(1, 100)
    mainWindow.OnEvent("Close", MainWindow_Close)
    addBtn.OnEvent("Click", AddButton_Click)
    deleteBtn.OnEvent("Click", DeleteBtn_Click)
    genCodeBtn.OnEvent("Click", GenCodeBtn_Click)
    testBtn.OnEvent("Click", TestBtn_Click)
    listview.OnEvent("ItemFocus", ListView_ItemFocus)
    OnMessage(0x0100, ListView_DeleteKeyDown)
    OnMessage(0x0102, ListView_CtrlC)

    ; Drawing is bound to the RIGHT button, for two reasons. It is the button
    ; gestures are actually triggered with in practice, and a Text control's
    ; Click event only arrives once the button is released — too late to record
    ; anything. HotIfWinActive is a built-in criterion, so the hook can evaluate
    ; it without asking the script's main thread on every click.
    HotIfWinActive("ahk_id " mainWindow.Hwnd)
    Hotkey("$RButton", DrawingBoard_RButton)
    HotIf()

    mainWindow.Show()

    InitDrawingBoard()
    listview.Add(, "↑", "0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10|0,-10")
    listview.Add(, "↓", "0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10|0,10")
    listview.Add(, "←", "-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0|-10,0")
    listview.Add(, "→", "10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0|10,0")
    listview.Add(, "circle", "-20,0|-20,3|-19,5|-19,7|-18,10|-16,12|-15,14|-13,15|-11,17|-9,18|-6,19|-4,20|-1,20|1,20|4,20|6,19|9,18|11,17|13,15|15,14|16,12|18,10|19,7|19,5|20,3|20,0|20,-3|19,-5|19,-7|18,-10|16,-12|15,-14|13,-15|11,-17|9,-18|6,-19|4,-20|1,-20|-1,-20|-4,-20|-6,-19|-9,-18|-11,-17|-13,-15|-15,-14|-16,-12|-18,-10|-19,-7|-19,-5|-20,-3")
    ControlFocus(listview)

    MainWindow_Close(mainWindow) {
        animation := ""
        ; These are global message hooks, so they must be released explicitly.
        ; Otherwise they survive the window inside a larger host script.
        OnMessage(0x0100, ListView_DeleteKeyDown, 0)
        OnMessage(0x0102, ListView_CtrlC, 0)
        HotIfWinActive("ahk_id " mainWindow.Hwnd)
        Hotkey("$RButton", "Off")
        HotIf()
        hgs.Destroy()
        mainWindow.Destroy()
    }

    AddButton_Click(ctrl, info) {
        dialog := Gui("Owner" mainWindow.Hwnd, "Add a gesture")
        dialog.SetFont(, "Cascadia Code")
        dialog.AddText(, "Vectors:")
        vectorsEdit := dialog.AddEdit("w400 r8")
        okBtn := dialog.AddButton("w190", "OK")
        cancelBtn := dialog.AddButton("wp x+M", "Cancel")
        dialog.Show()
        okBtn.OnEvent("Click", OkButton_Click)
        cancelBtn.OnEvent("Click", (ctrl, info) => dialog.Destroy())

        OkButton_Click(ctrl, info) {
            try
                gesture := HotGestures.Gesture(Trim(vectorsEdit.Text, " `r`n`t"))
            catch as err {
                dialog.Opt("OwnDialogs")
                MsgBox("Invalid vectors.`n`n" err.Message, "Warning", "Icon!")
                return
            }
            if AddGesture(gesture)
                dialog.Destroy()
        }
    }

    DeleteBtn_Click(ctrl, info) => DeleteSelections()

    GenCodeBtn_Click(ctrl, info) {
        if !CheckDistance(&distance)
            return
        if !listview.GetCount() {
            statusBar.Text := "nothing to export"
            return
        }
        ShowCodeWindow(distance)
    }

    /**
     * Gesture definitions on their own, wrapped in markers so they can be
     * replaced in place on the next export. For a script that already has its
     * own trigger and its own HotGestures instance.
     */
    BuildGestureBlock(hgsVarName := "hgs") {
        out := MARKER_BEGIN "`n"
        out .= "; Generated by GestureRecorder, " FormatTime(, "yyyy-MM-dd HH:mm") ".`n"
        out .= "; Everything between the markers is overwritten on the next export.`n"
        out .= "; Assumes an existing HotGestures instance named '" hgsVarName "'.`n"

        loop listview.GetCount() {
            literal := EscapeAhkString(listview.GetText(A_Index, 1) ":" listview.GetText(A_Index, 2))
            out .= "gesture" A_Index ' := HotGestures.Gesture("' literal '")' "`n"
        }
        loop listview.GetCount() {
            comment := EscapeAhkString(SingleLine(listview.GetText(A_Index, 1)))
            out .= hgsVarName '.Register(gesture' A_Index ', "' comment '")' "`n"
        }

        return out MARKER_END
    }

    /** A standalone script with its own RButton trigger. */
    BuildFullScript(distance, hgsVarName := "hgs") {
        part1 := part2 := part3 := ""
        loop listview.GetCount() {
            name := listview.GetText(A_Index, 1)
            varName := "gesture" A_Index
            literal := EscapeAhkString(name ":" listview.GetText(A_Index, 2))
            comment := SingleLine(name)
            part1 .= varName ' := HotGestures.Gesture("' literal '")' "`n"
            part2 .= hgsVarName '.Register(' varName ', "' EscapeAhkString(comment) '")' "`n"
            part3 .= "case " varName ": `; " comment "`n            "
        }
        part3 .= "default: return"

        ; Assembled by substitution rather than Format(), because the template
        ; contains literal braces that Format would read as fields.
        template := "
        (
            #Requires AutoHotkey v2.0
            #SingleInstance Force
            #Include HotGestures.ahk

            %%PART1%%
            %%HGS%% := HotGestures(%%DISTANCE%%)
            %%PART2%%
            $RButton::{
                %%HGS%%.Start()
                KeyWait("RButton")
                %%HGS%%.Stop()
                if %%HGS%%.Result.Valid {
                    switch %%HGS%%.Result.MatchedGesture {
                        %%PART3%%
                    }
                }
                else {
                    Send("{RButton}")
                }
            }
        )"

        code := StrReplace(template, "%%PART1%%", part1)
        code := StrReplace(code, "%%PART2%%", part2)
        code := StrReplace(code, "%%PART3%%", part3)
        code := StrReplace(code, "%%DISTANCE%%", Format("{:g}", distance))
        return StrReplace(code, "%%HGS%%", hgsVarName)
    }

    ShowCodeWindow(distance) {
        codeUi := Gui("+Resize +Owner" mainWindow.Hwnd, "Gesture code")
        codeUi.SetFont(, "Cascadia Code")
        fullRadio  := codeUi.AddRadio("Checked", "Complete script")
        blockRadio := codeUi.AddRadio("x+M", "Gesture definitions only")
        codeEdit := codeUi.AddEdit("xm Multi HScroll ReadOnly w820 h440")
        hint := codeUi.AddText("xm w820 h34", " ")
        copyBtn := codeUi.AddButton("xm w200", "Copy to clipboard")
        saveBtn := codeUi.AddButton("x+M w200", "Save as new file...")
        insertBtn := codeUi.AddButton("x+M w260", "Insert into existing script...")

        fullRadio.OnEvent("Click", (*) => Refresh())
        blockRadio.OnEvent("Click", (*) => Refresh())
        copyBtn.OnEvent("Click", (*) => CopyCode())
        saveBtn.OnEvent("Click", (*) => SaveCode())
        insertBtn.OnEvent("Click", (*) => InsertCode())

        Refresh()
        codeUi.Show()

        Refresh() {
            if fullRadio.Value {
                codeEdit.Value := BuildFullScript(distance)
                hint.Text := "Runs on its own. Save it next to HotGestures.ahk."
            }
            else {
                codeEdit.Value := BuildGestureBlock()
                hint.Text := "Paste into a script that already has a HotGestures instance named 'hgs' and its own trigger."
            }
        }

        CopyCode() {
            A_Clipboard := codeEdit.Value
            hint.Text := "Copied to the clipboard."
        }

        SaveCode() {
            codeUi.Opt("OwnDialogs")
            path := FileSelect("S", A_ScriptDir "\Gestures.ahk", "Save the generated code", "AutoHotkey (*.ahk)")
            if (path = "")
                return
            if !RegExMatch(path, "i)\.ahk$")
                path .= ".ahk"
            if FileExist(path) {
                if ("Yes" != MsgBox("Overwrite`n`n" path "?", "Save", 0x4))
                    return
                try FileDelete(path)
            }
            try {
                f := FileOpen(path, "w", "UTF-8-RAW")
                f.Write(codeEdit.Value)
                f.Close()
            }
            catch as err {
                MsgBox("Could not write the file.`n`n" err.Message, "Save", "Icon!")
                return
            }
            hint.Text := "Written to " path
        }

        InsertCode() {
            codeUi.Opt("OwnDialogs")
            ; Inserting the complete script would give the target a second
            ; $RButton:: hotkey, which AHK rejects as a duplicate.
            if fullRadio.Value {
                msg := "The complete script brings its own $RButton:: trigger."
                    . "`nInserting it into a script that already has one is a duplicate hotkey."
                    . "`n`nInsert the gesture definitions only instead?"
                if ("Yes" != MsgBox(msg, "Insert", 0x4))
                    return
            }
            InsertIntoScript(BuildGestureBlock())
        }
    }

    /**
     * Writes the generated block into a script the user maintains by hand.
     * Replaces an existing marked block, or appends one after confirmation.
     * Always takes a timestamped backup first, and writes through a temporary
     * file so a failure cannot leave a half-written script behind.
     */
    InsertIntoScript(block) {
        path := FileSelect(3, A_ScriptDir, "Choose the script to insert the gestures into", "AutoHotkey (*.ahk)")
        if (path = "")
            return

        try
            content := FileRead(path, "UTF-8")
        catch as err {
            MsgBox("Could not read that file.`n`n" err.Message, "Insert", "Icon!")
            return
        }

        ; Match the file's own line endings and byte order mark instead of
        ; silently converting the user's script.
        eol := InStr(content, "`r`n") ? "`r`n" : "`n"
        blockOut := StrReplace(StrReplace(block, "`r`n", "`n"), "`n", eol)
        encoding := HasUtf8Bom(path) ? "UTF-8" : "UTF-8-RAW"

        b := InStr(content, MARKER_BEGIN)
        e := InStr(content, MARKER_END)

        if (b && e && e > b) {
            newContent := SubStr(content, 1, b - 1) blockOut SubStr(content, e + StrLen(MARKER_END))
            what := "replaced the existing generated block"
        }
        else if (b || e) {
            MsgBox("That file has only one of the two markers.`n`nFix it by hand first — I will not guess where the block is meant to end.", "Insert", "Icon!")
            return
        }
        else {
            if ("Yes" != MsgBox("No generated block found in`n`n" path "`n`nAppend the gestures at the end?", "Insert", 0x4))
                return
            newContent := RTrim(content, "`r`n") eol eol blockOut eol
            what := "appended at the end"
        }

        backup := path "." FormatTime(, "yyyy-MM-dd_HHmmss") ".bak"
        try
            FileCopy(path, backup)
        catch as err {
            MsgBox("Could not create a backup, so nothing was written.`n`n" err.Message, "Insert", "Icon!")
            return
        }

        tmp := path ".tmp"
        try {
            if FileExist(tmp)
                FileDelete(tmp)
            f := FileOpen(tmp, "w", encoding)
            f.Write(newContent)
            f.Close()
            FileMove(tmp, path, 1)
        }
        catch as err {
            try FileDelete(tmp)
            MsgBox("Writing failed. The original is untouched.`n`nBackup: " backup "`n`n" err.Message, "Insert", "Icon!")
            return
        }

        MsgBox("Done — " what ".`n`nFile:    " path "`nBackup: " backup "`n`nReload that script to pick the gestures up.", "Insert", "Iconi")
    }

    HasUtf8Bom(path) {
        try {
            f := FileOpen(path, "r")
            if !f
                return false
            buf := Buffer(3, 0)
            n := f.RawRead(buf, 3)
            f.Close()
            return n = 3
                && NumGet(buf, 0, "UChar") = 0xEF
                && NumGet(buf, 1, "UChar") = 0xBB
                && NumGet(buf, 2, "UChar") = 0xBF
        }
        catch
            return false
    }

    TestBtn_Click(ctrl, info) {
        if testing {
            hgs.Clear()
            testBtn.Text := "Test"
            statusBar.Text := ""
            addBtn.Opt("-Disabled")
            deleteBtn.Opt("-Disabled")
            genCodeBtn.Opt("-Disabled")
            distanceEdit.Opt("-Disabled")
            testing := false
        }
        else {
            if !CheckDistance(&distance)
                return

            hgs.Clear()
            hgs.MaxDistance := distance

            bad := 0
            loop listview.GetCount() {
                gesture := RowGesture(A_Index)
                if !gesture {
                    bad++
                    continue
                }
                hgs.Register(gesture, "")
            }
            if bad {
                mainWindow.Opt("OwnDialogs")
                MsgBox(bad " row(s) contain invalid vectors and were skipped.", "Warning", "Icon!")
            }

            animation := ""
            InitDrawingBoard()
            testBtn.Text := "Stop Test"
            statusBar.Text := "Testing"
            addBtn.Opt("Disabled")
            deleteBtn.Opt("Disabled")
            genCodeBtn.Opt("Disabled")
            distanceEdit.Opt("Disabled")
            testing := true
        }
    }

    DrawingBoard_RButton(*) {
        ; Outside the board the right button keeps doing what it normally does.
        MouseGetPos(, , , &ctrlHwnd, 2)
        if (ctrlHwnd != drawingBoard.Hwnd) {
            Send("{RButton}")
            return
        }

        animation := ""
        InitDrawingBoard("")
        if hgs.StartAndWait("RButton", &result) {
            if testing {
                if result.MatchedGesture
                    statusBar.Text := result.MatchedGesture.Name " matched, distance: " result.Distance
                else
                    statusBar.Text := "no match"
            }
            else {
                try
                    newGesture := HotGestures.Gesture("Unnamed" itemIndex++, result.Vectors)
                catch as err {
                    statusBar.Text := "could not record: " err.Message
                    InitDrawingBoard()
                    return
                }
                AddGesture(newGesture)
            }
        }
        else {
            ; Cancelled, too short, or over the vector cap.
            if (result.Comment = "Cancelled")
                statusBar.Text := "gesture cancelled (timeout or too long)"
            InitDrawingBoard()
        }
    }

    ListView_CtrlC(wp, lp, msg, hwnd) {
        if hwnd == listview.Hwnd && wp == 3 {
            row := 0
            str := ""
            while row := listview.GetNext(row)
                str .= listview.GetText(row, 1) ":" listview.GetText(row, 2) "`n"
            if str != "" {
                A_Clipboard := Trim(str)
                statusBar.Text := "Copied!"
            }
        }
    }

    ListView_DeleteKeyDown(wp, lp, msg, hwnd) {
        if hwnd == listview.Hwnd && wp == 0x2E
            DeleteSelections()
    }

    ListView_ItemFocus(ctrl, item) {
        ; if focus changed because of deleting an item, the item index passed in is incorrect.
        if item := listview.GetNext(0, "Focused") {
            gesture := RowGesture(item)
            if !gesture {
                statusBar.Text := "invalid vectors in this row"
                InitDrawingBoard("")
                return
            }
            animation := CreateAnimation(gesture)
        }
    }

    /**
     * Builds a Gesture from a ListView row. Returns "" if the row does not
     * parse — the cells are user-editable, so this is a normal outcome, not
     * an exception.
     */
    RowGesture(row) {
        name := listview.GetText(row, 1)
        vectors := listview.GetText(row, 2)
        try
            return HotGestures.Gesture(name, vectors)
        catch
            return ""
    }

    AddGesture(newGesture) {
        if !CheckDistance(&threshold)
            threshold := 0.1

        prompt := ""
        loop listview.GetCount() {
            other := RowGesture(A_Index)
            if !other
                continue
            d := newGesture.Compare(other)
            if d <= threshold
                prompt .= "`n    Name: " listview.GetText(A_Index, 1) "`tDistance: " d
        }

        if prompt != "" {
            mainWindow.Opt("OwnDialogs")
            prompt := "This gesture is too similar to the following:" prompt "`n`nAre you sure you want to add it?"
            if "No" = MsgBox(prompt, "Warning", 0x4)
                return false
        }

        listview.Add("Vis Focus", newGesture.Name, newGesture.ToString())
        animation := CreateAnimation(newGesture)
        return true
    }

    CreateAnimation(gesture, interval := 20, repeatInterval := 1000) {
        InitDrawingBoard("")
        points := []
        points.Capacity := gesture.Length
        x := y := left := top := right := bottom := 0
        for v in gesture {
            points.Push([x += v[1], y += v[2]])
            left := Min(x, left)
            top := Min(y, top)
            right := Max(x, right)
            bottom := Max(y, bottom)
        }
        w := right - left
        h := bottom - top

        dc := DllCall("GetDC", "ptr", drawingBoard.Hwnd, "ptr")
        if !dc
            return ""

        drawingBoard.GetPos(, , &boardW, &boardH)
        boardW *= A_ScreenDPI / 96
        boardH *= A_ScreenDPI / 96

        xform := Buffer(24)
        scale := 1
        ; A straight gesture has zero extent on one axis. Dividing by it was a
        ; crash; scale only by the axis that actually has a size.
        if (w > boardW - 5 || h > boardH - 5) {
            sx := w > 0 ? (boardW - 10) / w : ""
            sy := h > 0 ? (boardH - 10) / h : ""
            if (sx != "" && sy != "")
                scale := Min(sx, sy)
            else if (sx != "")
                scale := sx
            else if (sy != "")
                scale := sy
            if (scale <= 0)
                scale := 1
            w *= scale, h *= scale, left *= scale, top *= scale
        }
        NumPut("float", scale, "float", 0, "float", 0, "float", scale, "float", (boardW - w) / 2 - left, "float", (boardH - h) / 2 - top, xform)
        DllCall("SetGraphicsMode", "ptr", dc, "int", 2)
        DllCall("SetWorldTransform", "ptr", dc, "ptr", xform)

        pen := DllCall("CreatePen", "int", 0, "int", 5, "uint", 0xFE4F7F, "ptr")
        oldPen := pen ? DllCall("SelectObject", "ptr", dc, "ptr", pen, "ptr") : 0

        index := 1
        SetTimer(LineToNextPoint, interval)
        return { __Delete: __Delete }

        LineToNextPoint() {
            if index == 0 {
                InitDrawingBoard("")
                DllCall("MoveToEx", "ptr", dc, "int", 0, "int", 0, "ptr", 0)
                SetTimer(LineToNextPoint, interval)
                index++
            }
            if index <= points.Length {
                DllCall("LineTo", "ptr", dc, "int", points[index][1], "int", points[index][2])
                index++
            }
            else {
                SetTimer(LineToNextPoint, -repeatInterval)
                index := 0
            }
        }

        __Delete(_) {
            SetTimer(LineToNextPoint, 0)
            if oldPen
                DllCall("SelectObject", "ptr", dc, "ptr", oldPen)
            if pen
                DllCall("DeleteObject", "ptr", pen)
            ; ReleaseDC takes the window handle as well — passing only the DC
            ; makes the call fail silently and leaks the device context.
            DllCall("ReleaseDC", "ptr", drawingBoard.Hwnd, "ptr", dc)
        }
    }

    InitDrawingBoard(text?) {
        text := text ?? "Hold the RIGHT mouse button and draw here"
        dc := DllCall("GetDC", "ptr", drawingBoard.Hwnd, "ptr")
        if !dc
            return

        drawingBoard.GetPos(, , &boardW, &boardH)
        boardW *= A_ScreenDPI / 96
        boardH *= A_ScreenDPI / 96
        DllCall("Rectangle", "ptr", dc, "int", 0, "int", 0, "int", boardW, "int", boardH)

        oldFont := 0
        if text {
            rect := Buffer(16)
            NumPut("int64", 0, "int", boardW, "int", boardH, rect)
            font := SendMessage(0x0031, 0, 0, drawingBoard)
            oldFont := DllCall("SelectObject", "ptr", dc, "ptr", font, "ptr")
            DllCall("DrawTextW", "ptr", dc, "str", text, "int", StrLen(text), "ptr", rect, "uint", 0x125)
        }

        if oldFont
            DllCall("SelectObject", "ptr", dc, "ptr", oldFont)
        DllCall("ReleaseDC", "ptr", drawingBoard.Hwnd, "ptr", dc)
    }

    DeleteSelections() {
        if testing {
            statusBar.Text := "Please stop test"
        }
        else {
            row := 0
            arr := []
            while row := listview.GetNext(row)
                arr.InsertAt(1, row)
            else
                return
            animation := ""
            for r in arr
                listview.Delete(r)
            statusBar.Text := arr.Length " items deleted"
        }
        if !listview.GetNext(0, "Focused") {
            InitDrawingBoard()
        }
    }

    CheckDistance(&distance) {
        distanceStr := distanceEdit.Text
        if IsNumber(distanceStr) {
            distance := Number(distanceStr)
            if distance >= 0 && distance <= 2
                return true
        }
        statusBar.Text := "invalid distance"
        return false
    }

    /** Escapes a string for use inside an AHK v2 double-quoted literal. */
    EscapeAhkString(s) {
        s := StrReplace(s, "``", "````")
        s := StrReplace(s, '"', '`"')
        s := StrReplace(s, "`r", "``r")
        s := StrReplace(s, "`n", "``n")
        return s
    }

    /** Collapses line breaks so a name cannot escape a `; comment. */
    SingleLine(s) {
        s := StrReplace(s, "`r", " ")
        s := StrReplace(s, "`n", " ")
        return s
    }
}
