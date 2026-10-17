;==========================================================
;  Demo — five gestures, scoped to Notepad.
;
;  Start it, Notepad opens, hold the RIGHT mouse button and
;  draw. Outside Notepad the right button behaves normally.
;
;  The five gesture templates below are Tebayaki's, taken
;  from the upstream demo. Everything else was rewritten.
;
;  Part of HotGestures-Continued. MIT licensed, see LICENSE.
;  Provided "AS IS", without warranty of any kind.
;==========================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include HotGestures.ahk

;----------------------------------------------------------
;  Gestures
;
;  Names are plain ASCII on purpose. A gesture name is just a
;  label, but it ends up in generated code and in file paths,
;  and an .ahk file without a byte order mark is not read as
;  UTF-8 everywhere.
;----------------------------------------------------------
leftSlide  := HotGestures.Gesture("Left:-1,0")
rightSlide := HotGestures.Gesture("Right:1,0")
circle     := HotGestures.Gesture("O:-20,0|-20,3|-19,5|-19,7|-18,10|-16,12|-15,14|-13,15|-11,17|-9,18|-6,19|-4,20|-1,20|1,20|4,20|6,19|9,18|11,17|13,15|15,14|16,12|18,10|19,7|19,5|20,3|20,0|20,-3|19,-5|19,-7|18,-10|16,-12|15,-14|13,-15|11,-17|9,-18|6,-19|4,-20|1,-20|-1,-20|-4,-20|-6,-19|-9,-18|-11,-17|-13,-15|-15,-14|-16,-12|-18,-10|-19,-7|-19,-5|-20,-3")
z          := HotGestures.Gesture("Z:2,0|4,-1|8,0|10,0|14,0|17,-1|18,-2|18,-1|19,-1|17,-1|16,0|15,0|12,-1|11,-1|12,0|13,0|12,0|13,0|10,0|6,0|4,0|1,0|-1,1|-3,2|-5,2|-5,4|-7,5|-8,6|-10,6|-12,7|-13,9|-15,8|-14,8|-14,9|-13,7|-12,7|-12,7|-11,6|-12,7|-13,7|-13,7|-12,5|-11,5|-9,4|-8,4|-6,3|-4,2|-1,1|2,0|5,0|9,0|12,0|16,0|19,0|23,0|27,0|34,0|35,1|33,1|31,0|25,0|19,0|13,0|8,0")
s          := HotGestures.Gesture("S:0,-1|0,-1|-1,-1|-1,-1|-2,-1|-1,-1|-1,-1|-1,0|-2,-1|-2,-2|-3,-1|-4,-2|-5,-1|-7,-1|-7,0|-9,0|-8,0|-9,0|-8,0|-6,0|-4,2|-4,1|-4,2|-4,3|-4,3|-5,3|-5,3|-4,3|-4,4|-4,4|-5,5|-4,5|-3,6|-1,7|-1,7|0,8|0,9|2,8|2,7|3,5|3,4|5,4|7,4|9,4|11,5|13,6|14,5|13,5|15,5|14,5|11,5|10,4|7,3|5,2|3,2|2,2|1,2|1,1|1,1|0,2|0,2|0,3|0,4|0,3|-2,4|-2,5|-3,4|-5,5|-6,6|-7,5|-8,6|-10,6|-11,6|-12,5|-11,4|-12,4|-10,4|-7,2|-9,1|-8,1|-8,1|-6,1|-5,0|-3,0|-2,0")

;----------------------------------------------------------
;  Instance
;
;  The defaults are fine; they are spelled out here because
;  this is the demo and these are the knobs worth knowing.
;----------------------------------------------------------
hgs := HotGestures(maxDistance := 0.1, minTrackLen := 100)

hgs.MinStep        := 4      ; no vector below 4 px of movement
hgs.Smoothing      := 0.3    ; 0 disables; effective step is MinStep / (1 - Smoothing)
hgs.GestureTimeout := 2000   ; ms; a gesture that never ends cancels itself
hgs.MaxVectors     := 1500   ; and so does one that gets absurdly long

hgs.Register(leftSlide,  "Backspace",  _ => Send("{BackSpace}"))
hgs.Register(rightSlide, "New line",   _ => Send("{Enter}"))
hgs.Register(circle,     "Select all", _ => Send("^a"))
hgs.Register(z,          "Undo",       _ => Send("^z"))
hgs.Register(s,          "Save",       _ => Send("^s"))

; Built-in criterion: the hook can evaluate this itself. A #HotIf
; expression could not, and would cost a round trip to the script's
; main thread on every single right-click. See examples/.
HotIfWinActive("ahk_class Notepad")
hgs.Hotkey("RButton")
HotIfWinActive()

;----------------------------------------------------------
;  Legend
;
;  Upstream wrote the instructions into Notepad's edit control
;  via ControlSetText, guessing the control's class name. That
;  class changed with the Windows 11 Notepad, so it silently
;  stopped working. A small window of our own does not care
;  which Notepad is installed.
;----------------------------------------------------------
Run("Notepad.exe")
if !WinWaitActive("ahk_class Notepad", , 10) {
    MsgBox("Notepad did not come up within 10 seconds.`n`n"
         . "The gestures are registered for ahk_class Notepad only, so "
         . "there is nothing to try until it is open.", "HotGestures demo", 0x30)
    ExitApp()
}

legend := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox", "HotGestures demo")
legend.SetFont("s10", "Segoe UI")
legend.AddText("", "Hold the RIGHT mouse button in Notepad and draw:")
legend.SetFont("s10 bold")
legend.AddText("xm y+10",
    "slide left" "`n"
  . "slide right" "`n"
  . "a circle" "`n"
  . "the letter Z" "`n"
  . "the letter S")
legend.SetFont("s10 norm")
legend.AddText("x+16 yp",
    "backspace" "`n"
  . "new line" "`n"
  . "select all" "`n"
  . "undo" "`n"
  . "save")
legend.SetFont("s9")
legend.AddText("xm y+14 cGray",
    "A plain right-click still opens the context menu.`n"
  . "Esc or closing this window ends the demo.")
legend.OnEvent("Close",  (*) => ExitApp())
legend.OnEvent("Escape", (*) => ExitApp())
legend.Show("NoActivate")
