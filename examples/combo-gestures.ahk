;==========================================================
;  Combo gestures: RButton alone vs. RButton + LButton
;
;  Shows the pattern for suppressing the left button *only*
;  while a gesture is running, without paying for it on every
;  ordinary click.
;
;  Part of HotGestures-Continued. MIT licensed, see ../LICENSE.
;  Provided "AS IS", without warranty of any kind.
;==========================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\HotGestures.ahk

hgs := HotGestures(maxDistance := 0.18, minTrackLen := 40)
hgs.Smoothing      := 0.3
hgs.GestureTimeout := 2000
hgs.MaxVectors     := 1500

;----------------------------------------------------------
;  Why not #HotIf
;
;  The obvious way to suppress LButton during a gesture is:
;
;      #HotIf blocking
;      *LButton::return
;      *LButton Up::return
;      #HotIf
;
;  Don't. A #HotIf condition cannot be evaluated inside the
;  hook thread, so for EVERY left click the hook has to ask
;  the script's main thread and wait for the answer — up to
;  #HotIfTimeout (1 s) if the main thread happens to be busy.
;  That shows up as a system-wide click lag.
;
;  Instead: register the hotkeys switched OFF, and turn them
;  on only for the duration of a gesture. A disabled hotkey
;  costs the hook nothing.
;----------------------------------------------------------
Hotkey("*LButton",    (*) => 0, "Off")
Hotkey("*LButton Up", (*) => 0, "Off")

SetLButtonBlock(on) {
    Hotkey("*LButton",    on ? "On" : "Off")
    Hotkey("*LButton Up", on ? "On" : "Off")
}

;----------------------------------------------------------
;  Gestures
;----------------------------------------------------------
gUp    := HotGestures.Gesture("Up:0,-20|0,-20|0,-20|0,-20|0,-20")
gDown  := HotGestures.Gesture("Down:0,20|0,20|0,20|0,20|0,20")
gLeft  := HotGestures.Gesture("Left:-20,0|-20,0|-20,0|-20,0|-20,0")
gRight := HotGestures.Gesture("Right:20,0|20,0|20,0|20,0|20,0")

hgs.Register(gUp,    "Copy / Select all")
hgs.Register(gDown,  "Paste / Clipboard history")
hgs.Register(gLeft,  "Back / Previous tab")
hgs.Register(gRight, "Forward / Next tab")

; RButton only
Actions := Map(
    "Up",    () => Send("^c"),
    "Down",  () => Send("^v"),
    "Left",  () => Send("{Browser_Back}"),
    "Right", () => Send("{Browser_Forward}")
)

; RButton + LButton held together
ComboActions := Map(
    "Up",    () => Send("^a"),
    "Down",  () => Send("#v"),
    "Left",  () => Send("^+{Tab}"),
    "Right", () => Send("^{Tab}")
)

;----------------------------------------------------------
;  Trigger
;----------------------------------------------------------
$RButton:: {
    hasLButton := false

    try {
        SetLButtonBlock(true)
        hgs.Start()
        hasLButton := WaitForLButton()
        if hasLButton
            KeyWait("LButton")
    }
    finally {
        ; always runs, so the block can never stay stuck on
        try hgs.Stop()
        SetLButtonBlock(false)
    }

    r := hgs.Result
    name := IsObject(r.MatchedGesture) ? r.MatchedGesture.Name : ""

    ; no gesture -> let the right click through
    if !r.Valid {
        if !hasLButton
            Send("{RButton}")
        return
    }

    set := hasLButton ? ComboActions : Actions
    if (name != "" && set.Has(name))
        set[name].Call()
}

; Physical key state, so the suppression above does not hide it from us
WaitForLButton() {
    while GetKeyState("RButton", "P") {
        if GetKeyState("LButton", "P")
            return true
        Sleep 10
    }
    return false
}
