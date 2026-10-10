# Changelog

All notable changes against the upstream project
[Tebayaki/HotGestures](https://github.com/Tebayaki/HotGestures) (v1.0, 2023-09-30).

## [0.9.0] — unreleased

Everything below is new in HotGestures-Continued. Upstream is unchanged since 2023 and
appears to be unmaintained.

### Added

- **`MinStep`** (default `4` px) — a mouse move shorter than this does not
  produce a vector. Upstream built one vector per pixel of movement and ran the
  full DTW matrix against every registered gesture for each one. On a 1000 Hz
  mouse that is up to 1000 matrix passes per second, inside the low-level hook,
  while Windows waits for it to return. Gesture templates work in 20 px steps, so
  1 px vectors carried no information anyway.
- **`GestureTimeout`** (default `2000` ms, `0` disables) — a gesture that is
  never finished cancels itself instead of leaving the hook and the overlay in
  place.
- **`Cancel()`** — ends recording and marks the result invalid.
- **`Smoothing`** (default `0.3`, `0` disables) — exponential smoothing of the
  pointer position. Upstream smoothed with a hard-coded `0.5`.
- **`ShowTip`** (default `false`) — the tooltip code path is kept but off by
  default.
- Precomputed vector magnitudes on `Gesture` (`Magnitudes`) instead of
  recomputing `Sqrt()` for every template vector on every comparison.

### Changed

- **Deferred overlay.** The drawing overlay is now shown on the first real
  movement, not on key-down. Upstream created and destroyed a full-screen
  layered window on every single right-click, including the thousands that are
  just context menus. This was the most visible cost of the library when idle.
- **Per-monitor drawing board.** One overlay window per monitor instead of one
  window spanning the virtual desktop, with the pen position carried across
  monitor boundaries (`__lastPanel`). Fixes drawing on mixed-DPI setups where the
  track was offset or clipped.
- **Monitor layout change detection** (`__GetMonitorHash`) — overlays are rebuilt
  when monitors are added, removed, or rearranged, instead of silently drawing
  to stale coordinates.
- **Coordinates from `MouseGetPos`** instead of the hook's raw `lParam`. The hook
  is now only a trigger. The hook reports *physical* pixels while the rest of
  AHK v2 works in *logical* coordinates; on a monitor whose scaling differs from
  the primary, the track was drawn on the wrong screen. An intermediate version
  converted with `PhysicalToLogicalPointForPerMonitorDPI`; taking the position
  from `MouseGetPos` avoids the conversion entirely.
  Background: [forum thread](https://www.autohotkey.com/boards/viewtopic.php?f=82&t=140331),
  [DPI scaling docs](https://www.autohotkey.com/docs/v2/misc/DPIScaling.htm).
- **`__GetMonitorScale`** replaces `__GetMonitorDPI`, with `try`/`catch` around
  `LogicalToPhysicalPointForPerMonitorDPI`, `MonitorFromPoint` and
  `GetDpiForMonitor`, falling back to `1.0` rather than propagating a broken
  value into the minimum track length.

### Fixed

- **GDI resource leaks.** `SelectObject` is now paired with a restore of the old
  pen, `DeleteObject` and `ReleaseDC` run on teardown, and a failed
  `CreatePen`/`GetDC`/`SelectObject` cleans up what it already allocated instead
  of leaking it. Upstream leaked a pen and a device context per monitor on every
  rebuild.
- **Timer leak** — the timeout timer is cleared in `Stop()`, including on the
  cancelled path.

### Notes for consumers

- `__OnMouseMove` now takes `*` instead of `(x, y)`. This is internal, but
  anyone who subclassed `HotGestures` should be aware.
- Default pen color is `0xE8EEF7` (upstream: `0xFE4F7F`) and pen width is 1.
  Both are cosmetic; pass `penColor` to `__New` to override.

### Not part of the library, but worth knowing

If you drive the library from a hotkey that also has to suppress the **left**
button during a gesture, do not use a `#HotIf` context for that. A `#HotIf`
condition cannot be evaluated in the hook thread, so the hook asks the script's
main thread on **every** click and waits for the answer — up to
`#HotIfTimeout` (1 s) if the main thread is busy. Register the blocking hotkeys
with `Hotkey()` in the off state and switch them on only while a gesture is
running. See `examples/` for a working pattern.
