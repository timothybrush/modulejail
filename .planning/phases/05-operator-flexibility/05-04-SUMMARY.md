---
phase: 05-operator-flexibility
plan: "04"
subsystem: quiet-verbose-behavior
tags: [shell, posix, quiet, verbose, telemetry, awk]

dependency_graph:
  requires:
    - phase: 05-01
      provides: QUIET=0/VERBOSE=0 defaults, --quiet/--verbose case arms, mutex guard (EX_USAGE=64)
    - phase: 05-02
      provides: -p none info line at line 312 (Site B for QUIET guard)
    - phase: 05-03
      provides: DRY_RUN=1 render branch (Site C brace-group for QUIET guard) + stdout summary branch (Site E)
  provides:
    - QUIET=1 silences all five non-error emit sites (info/notice/header/summary)
    - VERBOSE=1 emits per-module decision lines via single-pass awk (O(n), one fork)
    - --quiet --dry-run produces zero output (both stdout and stderr empty)
    - --quiet error: lines still fire (OPS-02 / T-05-04-T mitigation preserved)
    - OPT-03 behavior fully wired
  affects: [05-05, 05-06]

tech-stack:
  added: []
  patterns:
    - outer-QUIET-guard ([ "$QUIET" -eq 0 ] wrapping non-error emit sites)
    - POSIX-awk-first-write-wins (src[] array with FILENAME pattern matching)
    - single-fork-verbose-emitter (one awk pass over four sorted files, O(n))

key-files:
  created: []
  modified:
    - modulejail

key-decisions:
  - "Site B: chained condition [ profile = none ] && [ QUIET -eq 0 ] rather than nested if"
  - "Site C: QUIET guard wraps entire brace-group inside DRY_RUN=1 arm; --quiet --dry-run produces zero output"
  - "VERBOSE block sits outside QUIET guard: mutex enforced by Plan 05-01 (QUIET=1 && VERBOSE=1 exits 64)"
  - "Option B awk chosen for verbose emitter (single fork, O(n)) per D-Phase5-07 / PATTERNS.md recommendation"
  - "Decision lines use no severity prefix (operator telemetry, not script-status diagnostics)"

requirements-completed: [OPT-03]

metrics:
  duration: "8m"
  completed: "2026-05-23T18:52:00Z"
  tasks_completed: 2
  files_changed: 1
---

# Phase 05 Plan 04: --quiet and --verbose Behavior Wiring Summary

**`--quiet` silences all five non-error emit sites; `--verbose` emits per-module decision lines via single-pass awk - OPT-03 fully operational**

## Performance

- **Duration:** ~8 min
- **Completed:** 2026-05-23T18:52:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

### Task 1: Five QUIET guards added (Sites A-E)

| Site | Line | What is guarded | Guard form |
|------|------|-----------------|------------|
| A - default-whitelist info: | 305 | `printf 'modulejail: info: using default whitelist file...'` | `if [ "$QUIET" -eq 0 ]; then` inside auto-detect block |
| B - -p none info: | 313 | `printf 'modulejail: info: -p none selected...'` | Chained `[ "$profile" = "none" ] && [ "$QUIET" -eq 0 ]` |
| C - dry-run header brace-group | 780 | Entire `{ printf ... emit_install_line } >&2` brace-group | `if [ "$QUIET" -eq 0 ]; then` inside `DRY_RUN=1` arm |
| D - update-check call | 960 | `check_for_updates` call | `if [ "$QUIET" -eq 0 ]; then` wrapper |
| E - stdout summary | 859 | `DRY-RUN: would blacklist` / `blacklisted` if/else | Outer `if [ "$QUIET" -eq 0 ]; then` wrapper |

**No `error:` printf is guarded.** Verified: `grep -B3 'modulejail: error:' modulejail | grep 'QUIET -eq 0'` returns empty.

### Task 2: VERBOSE awk emitter added (line 710)

Inserted between `comm -23` line (702) and `blacklist=` assignment (727).

```sh
if [ "$VERBOSE" -eq 1 ]; then
    awk '
        FILENAME ~ /loaded\.txt$/    { src[$1] = "loaded";    next }
        FILENAME ~ /whitelist\.txt$/ { if (!($1 in src)) src[$1] = "whitelist"; next }
        FILENAME ~ /baseline\.txt$/  { if (!($1 in src)) src[$1] = "baseline"; next }
        { if ($1 in src) printf "keep: %s (%s)\n", $1, src[$1]; else printf "blacklist: %s\n", $1 }
    ' "$workdir/loaded.txt" "$workdir/whitelist.txt" "$workdir/baseline.txt" \
      "$workdir/universe.txt" >&2
fi
```

Single awk pass, O(n), one fork. First-write-wins precedence: loaded > whitelist > baseline.

## Exact Line Numbers

| Change | File | Line |
|--------|------|------|
| QUIET guard Site A (default-whitelist info:) | modulejail | 305 |
| QUIET guard Site B (-p none info:, chained &&) | modulejail | 313 |
| VERBOSE awk emitter block (after comm -23) | modulejail | 710 |
| QUIET guard Site C (dry-run brace-group) | modulejail | 780 |
| QUIET guard Site E (stdout summary outer) | modulejail | 859 |
| QUIET guard Site D (check_for_updates call) | modulejail | 960 |

## Smoke Test Results on ubuntu-wifi (real Linux host)

### --quiet normal run
- Exit code: 0
- stdout bytes: 0 (empty)
- stderr info/notice/header lines: 0 (silent)
- Output file `/tmp/mj-quiet.conf`: 669671 bytes (written)

### --quiet --dry-run
- Exit code: 0
- stdout bytes: 0 (empty)
- stderr bytes: 0 (empty)
- Output file: not created (correct)

### --quiet -p bogus (error: NOT silenced)
- Exit code: 64 (EX_USAGE)
- stderr contains `modulejail: error: unknown profile: bogus`: YES (1 match)

### --verbose normal run
- Exit code: 0
- Output file: written (669671 bytes)
- stderr lines: 6474 (all modules)
- `keep: NAME (loaded)` lines: 88
- `keep: NAME (baseline)` lines: 23
- `blacklist: NAME` lines: 6363
- No `modulejail:` prefix on decision lines: confirmed (0 matches)
- Wall-clock: 0.2s (well under 5s threshold)

### --quiet --verbose mutex
- Exit code: 64 (Plan 05-01 mutex preserved)

## Task Commits

| Hash | Type | Description |
|------|------|-------------|
| 8734362 | feat | add QUIET guards around all five non-error emit sites (Task 1) |
| 904ddfd | feat | add single-pass awk verbose emitter between comm -23 and blacklist= assignment (Task 2) |

## Test Results

| Test | Host | Result |
|------|------|--------|
| `sh -n modulejail` (POSIX syntax) | macOS dev | PASS |
| host-local fixture cases | macOS dev | 18/18 PASS |
| v1.1.4-regression | macOS dev | 6363/6363 PASS |
| `--quiet` acceptance criteria | ubuntu-wifi | all green |
| `--verbose` acceptance criteria | ubuntu-wifi | all green |
| `--quiet --verbose` mutex | ubuntu-wifi | rc=64 PASS |

## Decisions Made

- **Site B chained condition:** Rather than adding a nested `if [ "$QUIET" -eq 0 ]` inside the existing `if [ "$profile" = "none" ]` block, extended the guard inline with `&&` to keep the change minimal and avoid adding nesting depth.
- **Site C wraps the entire brace-group:** Under `--quiet --dry-run`, the file is not written (dry-run) AND all output is silent (quiet); exit code 0 is the only signal. The entire `{ ... } >&2` block is inside the QUIET=0 arm so zero bytes reach stderr.
- **VERBOSE block outside QUIET guard:** The plan notes this explicitly: `--quiet` and `--verbose` are mutually exclusive (Plan 05-01 mutex exits 64 before we reach the pipeline). Wrapping with QUIET would be dead code.
- **Option B awk:** Single-pass O(n), one fork, POSIX-portable FILENAME pattern matching. Option A (~5000 grep forks) was explicitly rejected per PATTERNS.md and D-Phase5-07.

## Deviations from Plan

None - plan executed exactly as written. All five sites guarded; awk Option B used exactly as specified in PATTERNS.md.

## Known Stubs

None. `--quiet` silencing is fully wired with real runtime checks. `--verbose` awk emitter reads real sorted input files. No placeholder values.

## Threat Flags

None. The changes introduce no new network endpoints, no new file access patterns, no new auth paths, no schema changes.

- T-05-04-T (--quiet silencing critical errors): MITIGATED. No `error:` printf is inside a QUIET guard. Verified by grep + real-host test (`--quiet -p bogus` still emits error: line and exits 64).
- T-05-04-D (verbose emitter performance): MITIGATED. Single awk pass, 0.2s on a 6474-module host.
- T-05-04-I (verbose decision lines on stderr): ACCEPTED. Module names are public; no secrets in output.
- T-05-04-R (--quiet hides run from local logs): ACCEPTED. Only silences generation-time chatter; generated blacklist file still fires syslog on any modprobe attempt against blacklisted modules.

## Self-Check: PASSED

- modulejail file exists at worktree root with all five QUIET guards and the VERBOSE block
- `sh -n modulejail`: PASS
- `grep -c 'QUIET.*-eq 0' modulejail` = 5
- `grep -cE 'VERBOSE.*-eq 1' modulejail` = 2 (one for mutex check at line 280, one for awk emitter at line 710)
- `grep -cF 'keep: %s (%s)' modulejail` = 1
- `grep -cF 'blacklist: %s' modulejail` = 1
- Commits 8734362 and 904ddfd exist
- 18/18 host-local fixture tests PASS on macOS dev
- v1.1.4-regression: 6363/6363 PASS on macOS dev
- All --quiet/--verbose acceptance criteria green on ubuntu-wifi

## Next Phase Readiness

- OPT-03 (`--quiet` + `--verbose`) base behaviors are fully operational.
- Plan 05-05 can replace Site E (lines 859-867) with a three-way branch (OUTPUT_FORMAT first, then DRY-RUN, then normal) per D-Phase5-09 (JSON survives quiet). The existing QUIET guard becomes the outer `elif [ "$QUIET" -eq 0 ]` arm.
- The VERBOSE awk emitter is independent of OUTPUT_FORMAT; Plan 05-05 does not need to touch it.
- No blockers.

---
*Phase: 05-operator-flexibility*
*Completed: 2026-05-23*
