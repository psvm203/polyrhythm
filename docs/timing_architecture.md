# PolyRhythm timing architecture

## Problem and decision

Previously, input used a microsecond clock while polygon motion integrated frame
`delta`. The conductor rebuilt a judgment center from the current input time plus
remaining visual travel, then replaced it with a frame-observed contact. Identical
input could consequently receive Perfect, Fast, or Too Fast depending on rendering.
A long frame could also move an expired note into the future. Negative calibration
could snap a polygon to its target before contact.

Gameplay now uses one monotonic `RhythmClock` and fixed contact times from
`NoteTimeline`. A note's center is always `contact + judgment_offset_sec`.
Observation, FPS, and audio playback samples cannot change a note's schedule.
Changing the user's offset affects only unresolved judgments; queued results retain
their original timing delta. Stage YAML, BPM duration rules, scores, and saves keep
their existing formats.

## Ownership and update order

- `NoteTimeline` builds cumulative contact times from polygon sides and BPM.
- `RhythmClock` measures elapsed microseconds, excluding paused intervals.
- `Conductor._next_note_index` owns the first note still eligible for input.
- `Conductor._resolved_notes` retains accepted hits and misses until presentation.
- `Rotator.current_index` owns the polygon currently shown. It may lag the input
  cursor when early offset-adjusted hits are waiting for contact.
- `Rotator.sample_timeline` derives progress from absolute game time and the note's
  fixed start/contact interval. Gameplay never integrates visual frame deltas.
  Standalone previews retain delta-driven animation.

Each frame and each recognized input samples the clock, updates polygon geometry,
flushes arrived queued judgments, and expires overdue notes in order. Input is then
assigned to the first unexpired unresolved note. Too Fast does not consume a note.
An accepted input reserves its note immediately, allowing another input to target
the following note even before the previous polygon is presented.

A queued judgment is displayed only at or after its visual contact. Results emit in
note order, once per resolved note. A synchronous result callback can end or pause
the run; catch-up stops immediately. An emitted result is marked before callbacks
so resuming cannot emit it again. There is no 32-note catch-up limit: each iteration
consumes a note, and the finite timeline bounds the work.

Presentation can hold a landed polygon through the late window. On advancing, the
next polygon samples its original absolute interval rather than restarting a new
full-duration animation. Landing glow and spawn fade use that same sampled elapsed
time, so pause cannot desynchronize visual cues.

## Pause and audio policy

Conductor tracks pause reasons (`manual` and `boss_time_stop`) as a set. The first
reason freezes the clock and geometry; removing a reason resumes them only when
none remain. Level keeps audio paused while any reason remains. Boss time-stop
starts synchronously on polygon advancement, preventing catch-up from skipping the
event. Its timer can finish while the pause menu is open without resuming gameplay.

Audio starts with gameplay using the clamped stage music offset. Playback position
is diagnostic telemetry only: per-frame audio correction was removed because it
made the game clock depend on rendering frequency and could move time backwards.
The displayed audio drift is raw playback position minus start offset and game time;
it is not an estimate of speaker/output latency. Long-term audio hardware drift is
not automatically corrected by this design. User timing calibration remains the
explicit input-center adjustment.

## Units and diagnostics

- Absolute clock: integer microseconds; public gameplay time: seconds.
- Delta: `input_time - (contact + offset)`; negative means early.
- Input traces distinguish the input note from the visual polygon index.
- `contact_observed` says whether `observed_contact_sec` is an observation or the
  scheduled fallback. Observations never control gameplay.
- Deferred result logs retain the accepted input delta, not the later display time.

## Verification

`tests/conductor_runtime_test.gd` uses real Conductor/Rotator instances with an
injected clock. It covers render phases at 30/60/120/144 FPS, stale frames, offsets,
window edges, multi-note catch-up, between-frame input, dense early inputs, nested
pause, signal reentrancy, and visual clock ownership. `gameplay_runtime_test.gd`
checks the actual level/result/trace flow with a deadline derived from stage data.
`level_pause_test.gd` exercises overlapping menu and boss pauses in the real scene.
The suite runner also rejects GDScript parse/runtime errors even when Godot returns
exit code zero.

Run all checks with `bash tests/run_all.sh`.
