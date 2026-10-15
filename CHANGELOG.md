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

### Removed

- **`ShowTip` and `DrawTip`.** `DrawTip` was an empty method, so the property had
  no effect. Removed rather than shipped as a promise the library does not keep.

### Hardening (review pass before first release)

- **Infinity sentinel.** The matrix used
  `NumGet(ObjPtr(&_ := 0x7F800000) + A_PtrSize * 2, "float")` to synthesise
  `+inf` by reading the raw bytes of a VarRef. That depends on AHK's internal
  memory layout and would have broken *silently* on a layout change — the
  sentinel would become an ordinary number and `Min()` comparisons would be
  wrong without any error. Replaced with `1.0e15`. Real DTW costs stay below
  `1e5` (at most 2 per step), so it is equivalent and version-proof. Relevant
  because v2.1-alpha already changes DPI defaults.
- **Zero vectors are rejected** in `VerifyVectorsString` and
  `VerifyVectorsArray`. `0,0` passed validation, then divided by zero in
  `Append` — inside the hook callback. Reachable from the recorder's *Add*
  dialog by pasting a gesture list. `Append` and `TraceBack` also guard against
  a zero denominator now.
- **Digit count is bounded** in the vector pattern, so `Integer()` can no longer
  be handed an overflowing literal.
- **Overlay rebuilds moved out of the hook callback.** `Show()` used to check the
  monitor hash and could rebuild every overlay window — creating GUIs, DCs and
  pens — from inside the low-level hook. Exceeding `LowLevelHooksTimeout`
  (300 ms by default) makes Windows remove the hook without a word. The rebuild
  now happens in `Start()`, on a normal thread, via `DrawingBoard.EnsurePanels()`.
  Only the cheap `Gui.Show()` stays in the hook.
- **POINT packing fixed** in `__GetMonitorScale`. `px | (py << 32)` sign-extends a
  negative x across all 64 bits, so the packed y was read as `-1` and
  `MonitorFromPoint` was asked about the wrong location. Monitors to the left of
  the primary have negative coordinates. Masked with `px & 0xFFFFFFFF`. Latent
  on layouts where every monitor has `top = 0`; wrong on vertical stacks.
- **A second `Start()` without `Stop()`** orphaned the timeout timer, which then
  fired into the following gesture and cancelled it. `Start()` now winds the
  previous gesture down first, and the bound function is created once per
  gesture and cleared in `Stop()`.
- **`Stop()` is idempotent** and no longer throws when called without a preceding
  `Start()`.
- **`MaxVectors`** (default `1500`) caps the recorded vectors. Without it, holding
  the button and moving kept appending rows to every matrix while `TraceBack`
  walks them — cost per move grows with the count, so a long gesture degraded
  into a stuttering pointer. The abort is dispatched to a normal thread with
  `SetTimer(..., -1)`, because releasing the hook object from inside its own
  callback frees a callback that is still running.
- **Excluded candidates are skipped in `__UpdateMatch`.** Their matrix is frozen,
  so `TraceBack` returned a constant — `O(rows)` of pure waste per move, exactly
  in the hottest loop.
- **`Smoothing` is clamped** to `0..0.95` and `MinStep` to `>= 0`, both
  normalised once per gesture instead of being re-read inside the hook. At
  `Smoothing := 1` no movement would ever have registered.
- **`Register` rejects anything that is not a `HotGestures.Gesture`**, and
  `DistanceMatrix` checks for usable `Magnitudes`, instead of failing later with
  an unhelpful error.
- **`Destroy()`** added. An instance handed to `Hotkey()` is referenced by AHK's
  global hotkey table and is never collected, so `__Delete` does not run on its
  own.

### Gesture Recorder

- **Code injection in *Generate Code* closed.** Gesture names come from an
  editable ListView and were interpolated raw into a quoted string literal and
  into a `;` comment. A crafted name could close the literal and append
  arbitrary code to a snippet the user copies in order to run it. Names are
  escaped now and comments collapsed to one line. The template is assembled by
  substitution instead of `Format()`, which would otherwise read the literal
  braces of the generated code as fields.
- **`ReleaseDC` was called with one argument instead of two**, so it failed and
  leaked a device context on every call — including `InitDrawingBoard`, which
  runs on each click and selection. A long session walked towards the 10,000
  GDI object limit. Pen and font are restored as well.
- **Division by zero on straight gestures.** A purely vertical or horizontal
  gesture has zero extent on one axis; the preview scaling divided by it. The
  axis comparison was also checking width against the board's *height*.
- **Invalid rows no longer crash the recorder.** The ListView is editable, so a
  row can stop parsing at any time. Selecting, testing or exporting such a row
  threw. Rows are parsed defensively and reported instead.
- **The similarity check uses the Max Distance field** rather than a hard-coded
  `0.1` that ignored it.
- Message hooks are released when the window closes, `"Warming"` is spelled
  `"Warning"`, and a misspelled variable was fixed.

### Tests

- `tests/selftest.ahk` — validation, gesture round trip, DTW distances for
  identical, opposite and perpendicular tracks, the empty-track edge case and
  the coordinate packing. No mouse, no hook, no GUI.

### Notes for consumers

- `__OnMouseMove` now takes `*` instead of `(x, y)`. This is internal, but
  anyone who subclassed `HotGestures` should be aware.
- `ShowTip` no longer exists. Setting it is now a no-op property assignment
  rather than a setting that silently did nothing.
- Gestures containing `0,0` are rejected at construction instead of failing
  later inside the hook.
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
