# Cursor/Herdr Calm Mode Spec

Status: draft  
Owner: firstmate runtime  
Audience: maintainers of `bin/`, `docs/`, and runtime adapters

## Goal

Deliver a Calm-like experience for Cursor + Herdr:

- suppress routine operational noise
- keep actionable signals visible
- show a lightweight animated ship while work is active

This is a presentation/runtime feature. It must not alter task semantics, delivery rules, or decision handling.

## Non-goals

- No transcript-row hiding inside Cursor's native message renderer (not currently hookable in the same way as Pi/Claude mods).
- No change to model prompts, task state transitions, wake durability, or backlog semantics.
- No implicit merge/approval behavior changes.

## User outcomes

When enabled, the captain should see:

1. Fewer non-actionable lines during steady supervision.
2. A persistent visual "work in progress" indicator (ship) while at least one task is actively running.
3. Immediate visibility for blockers, decisions, failures, and review-ready outputs.

## Constraints

- Primary runtime: Cursor agent + Herdr backend (Wex terminal usage pattern).
- Existing supervision contract remains authoritative.
- Quiet mode and away posture remain separate controls; Calm complements them.
- ASCII-safe fallback required for terminals without reliable Unicode rendering.

## Architecture

Implement Calm-for-Cursor/Herdr as two coordinated layers:

1. **Output classification layer** (what to suppress)
2. **Statusline/overlay layer** (what to show instead)

### 1) Output classification layer

Introduce a Calm presentation filter at firstmate output boundaries (not by rewriting durable logs):

- classify each candidate line as:
  - actionable
  - milestone
  - routine
  - debug/internal
- with Calm on:
  - hide or coalesce routine lines
  - keep actionable + milestone lines verbatim
  - optionally summarize suppressed counts periodically (e.g., "calm: suppressed 18 routine updates")

Suggested actionable allowlist:

- decision requests/resolutions
- blocked/failure states
- CI red/green milestone transitions
- PR ready/review-needed outputs
- explicit captain-directed command outcomes

Suggested routine suppress list:

- repeated healthy watcher/attach notices
- duplicate "still running/no change" lines
- routine heartbeat with no state delta

### 2) Statusline/overlay layer

Render a ship animation in a runtime-controlled statusline area:

- visible only while any tracked task is in active running states
- hidden on idle/parked-without-active-work
- move on timer tick independent of model output
- preserve low redraw overhead

Reuse existing calm ship geometry primitives where possible, but render via Cursor/Herdr-compatible terminal status output instead of transcript hooks.

Fallback strategy:

- Unicode mode (default): compact sailboat + wave
- ASCII fallback: `>===>` with moving water markers

## Configuration

Add/extend one per-home preference source:

- `config/calm` continues to store on/off
- optional knobs (future-safe, all optional):
  - `style=unicode|ascii|auto`
  - `summary_interval_sec=<int>`
  - `show_ship=true|false`

Defaults:

- Calm off by default
- `style=auto`, `show_ship=true`

## Command surface

Keep operator surface minimal:

- `/calm` toggle on/off (existing behavior parity target)
- optional explicit variants (future): `/calm on`, `/calm off`, `/calm status`

Command must return short, non-noisy confirmation.

## Event model

Ship active condition should derive from existing authoritative task state reads, not ad-hoc pane peeks:

- active when at least one task is in running/working/validating/fixing-type states
- inactive when all tasks are terminal or truly idle

Noise suppression must read presentation events only; durable state files stay unchanged.

## Safety rules

- Never suppress lines that imply captain action is needed.
- Never suppress first-seen error for a task.
- Never suppress transitions into or out of blocked/failed/needs-decision.
- If classifier confidence is low, show line (fail-open presentation policy).

## Rollout plan

### Phase 0: design + guardrails

- add classifier rules table and fixtures
- document exact "never suppress" classes

### Phase 1: passive mode

- compute suppression decisions but do not hide output
- emit debug counters only under explicit diagnostics toggle

### Phase 2: active suppression + ship

- enable suppression and coalescing
- enable ship rendering for active work windows

### Phase 3: tuning

- measure false suppressions and captain-facing clarity
- tune allowlist/suppress rules

## Test plan

Add targeted tests for:

1. **Classification correctness**
   - actionable lines always pass
   - duplicate routine lines suppress/coalesce
2. **State transitions**
   - first failure for task is always visible
   - needs-decision always visible
3. **Ship lifecycle**
   - appears when work starts
   - disappears when fleet goes idle
   - stable under resize/repaint
4. **Fallback rendering**
   - ASCII mode renders deterministically
5. **No semantic drift**
   - durable logs/backlog/state files unchanged by Calm presentation mode

## Observability

Expose minimal counters for troubleshooting:

- suppressed line count by class
- last visible actionable timestamp
- ship render active/inactive transitions

Counters should be optional and off in normal mode.

## Open questions

1. Preferred status surface in your Wex/Herdr setup:
   - bottom statusline
   - top transient line
   - sidecar pane
2. Desired suppression aggressiveness:
   - conservative (hide only known-routine duplicates)
   - moderate (coalesce most routine progress)
3. Ship styling preference:
   - keep current calm sprite feel
   - ultra-minimal ASCII indicator

## Acceptance criteria

Feature is done when:

- captain can toggle Calm in Cursor/Herdr sessions
- routine noise is materially reduced without hiding required decisions/failures
- ship indicator is visible during active work and absent when idle
- no changes to task semantics, decision durability, or merge/delivery authority

