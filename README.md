# HotGestures-NG

A light AutoHotkey **v2** library for creating and recognizing custom one-stroke
mouse gestures. Define any pattern — lines, arcs, polylines, L, O, M, U, Z, even
a star — and bind it to a function.

![demo](./pic/demo.gif)

> **Status: v0.9, looking for feedback.** It has been in daily use on one
> multi-monitor, mixed-DPI Windows 11 machine for months, but it has had exactly
> one tester. Issues and pull requests are very welcome.

---

## Where this comes from

This is a continuation of [**Tebayaki/HotGestures**](https://github.com/Tebayaki/HotGestures)
(MIT, 2023). All of the clever parts — the DTW matching, the vector format, the
gesture recorder — are Tebayaki's work.

The upstream repository has seen no activity for a long time and the author did
not respond to contact, so this fork carries the fixes forward instead. It is
**not** an official successor, and Tebayaki is not involved in it.

The MIT license permits this; the original copyright notice is retained in
[`LICENSE`](./LICENSE) alongside my own.

---

## What is different

Short version: it no longer costs anything when you are not gesturing, it
behaves on mixed-DPI multi-monitor setups, and it stops leaking GDI handles.

| Area | Change |
|---|---|
| Idle cost | Overlay is created on first movement, not on every right-click |
| CPU | `MinStep` — no vector, and no DTW pass, below 4 px of movement |
| Multi-monitor | One overlay per monitor, pen carried across boundaries |
| Mixed DPI | Coordinates from `MouseGetPos`, the hook is only a trigger |
| Robustness | `GestureTimeout`, `Cancel()`, monitor-layout change detection |
| Leaks | Pen, DC and timer are released on teardown |
| Tuning | `Smoothing` and `ShowTip` are properties now, not hard-coded |

Full list with rationale: [`CHANGELOG.md`](./CHANGELOG.md).

Drop-in replacement — the public API is unchanged, so existing scripts keep
working.

---

## Install

Copy `HotGestures.ahk` next to your script, or into your AHK `Lib` folder, then:

```autohotkey
#Include HotGestures.ahk
```

Requires AutoHotkey v2.0 or later. Windows only.

---

## Quick start

```autohotkey
#Include HotGestures.ahk

leftSlide  := HotGestures.Gesture("Left:-1,0")
rightSlide := HotGestures.Gesture("Right:1,0")

hgs := HotGestures()
hgs.Register(leftSlide,  "Back",    _ => Send("!{Left}"))
hgs.Register(rightSlide, "Forward", _ => Send("!{Right}"))

hgs.Hotkey("RButton")   ; right button starts a gesture, a plain click still works
```

### Recording your own gestures

Writing vector strings by hand is no fun. Run `GestureRecorder.ahk`, draw on the
whiteboard with the left button, select the result in the list and copy it with
`Ctrl+C`. *Generate Code* gives you a ready-made template.

![Gesture Recorder](./pic/recorder.jpg)

---

## Parameters

```autohotkey
hgs := HotGestures(maxDistance := 0.1, minTrackLen := 100, penColor := 0xE8EEF7)
```

| Parameter | Meaning |
|---|---|
| `maxDistance` | Match tolerance, `0`–`2`. Lower is stricter |
| `minTrackLen` | Minimum track length in pixels; shorter tracks are not a gesture |
| `penColor` | Color of the drawn track |

Properties that can be set after construction:

| Property | Default | Meaning |
|---|---|---|
| `MinStep` | `4` | Minimum movement in px before a vector is recorded |
| `Smoothing` | `0.3` | Exponential smoothing, `0` disables |
| `GestureTimeout` | `2000` | Auto-cancel after this many ms, `0` disables |
| `ShowTip` | `false` | Show a tooltip with the matched gesture name |

If recognition feels worse after upgrading, try `hgs.MinStep := 2`. To push CPU
down further on a high-polling-rate mouse, `6` still works here.

---

## How it works

Gestures are matched with **Dynamic Time Warping** over sets of direction
vectors. You supply one or more vector sets as templates; while you draw, the
current track is compared against every template that has not already been ruled
out, and the closest match within `maxDistance` wins.

A gesture is a string in the format `[NAME:]X1,Y1[|X2,Y2]...`:

```
Right-slide:10,0|10,0|10,0
Left-slide:-10,0|-10,0|-10,0
```

---

## Known issues / looking for feedback on

- `MinStep` is a fixed pixel value and is **not** DPI-scaled. On a 4K display at
  200 % it is effectively half as coarse. Should it scale with the monitor?
- `GestureTimeout` runs on a wall clock, not on idle time. A slow, deliberate
  gesture longer than 2 s gets cancelled.
- Only tested on Windows 11 with two monitors at 100 % and 150 %. Reports from
  three or more monitors, or from unusual arrangements, would be useful.
- The overlay uses GDI on layered windows. On machines without hardware
  acceleration this may still be the slowest part.
- `Smoothing` at `0.3` is a value that works for me. No idea whether it suits
  trackballs, pen tablets or high-DPI gaming mice.

---

## License

MIT. See [`LICENSE`](./LICENSE).

Original work © 2023 Tebayaki · Modifications © 2026 Christian Berthold

---

## Disclaimer

**This software is provided "AS IS", without warranty of any kind, express or
implied. Use at your own risk.**

Be aware of what it does before you run it: this library installs a
**system-wide low-level mouse hook**, draws always-on-top overlay windows, and —
depending on your own script — may suppress mouse buttons. A faulty gesture
script can make the mouse appear unresponsive until the script is reloaded.

If you plan to run this on a managed or work machine, clear it with whoever
administers that machine first.
