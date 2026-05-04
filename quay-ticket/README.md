# Quay Ticket — Ralph Loop

Single-ticket Quay development using a [Ralph Loop](https://ghuntley.com/loop/) tick-loop. Replaces the `/start → /code → /pr → /poll` skill chain with one continuous state machine.

## Why

The original Quay workflow uses four separate skills that the agent must chain via natural language instructions ("invoke /pr immediately"). The agent frequently stops mid-pipeline because skill boundaries create natural stopping points and safety training overrides "don't ask" instructions.

The Ralph Loop eliminates this: one skill (`/work`), one state machine, no skill boundaries. The agent advances mechanically through states. No chaining instructions needed.

## Usage

```
/work PROJQUAY-XXXX            # full autonomous loop
/work PROJQUAY-XXXX --manual   # step through with pause points
```

## State Machine

```
ASSIGN ──→ BRANCH ──→ IMPLEMENT ──→ TEST ──→ COMMIT ──→ PR_CREATE
                                                            │
                                                            ▼
COMPLETE ◄── DORMANT_REVIEW ◄── DORMANT_CI ◄────────────────┘
                                    │
                                    ▼ (exit 1 or 3)
                              ADDRESS_FEEDBACK ──→ DORMANT_CI
```

### States

| State | Type | Does |
|-------|------|------|
| ASSIGN | active | View JIRA ticket, assign, transition |
| BRANCH | active | Create feature branch, load area docs |
| IMPLEMENT | active | Read conventions, implement changes |
| TEST | active | Pre-commit, pytest, mypy |
| COMMIT | active | Commit with proper format |
| PR_CREATE | active | Validate title, create PR |
| DORMANT_CI | dormant | poll-pr.sh blocks — 0 tokens |
| ADDRESS_FEEDBACK | active | Fix CI or review comments, push |
| DORMANT_REVIEW | dormant | poll-pr.sh blocks — awaiting human |
| COMPLETE | terminal | Report summary |

### DORMANT States

DORMANT states are yield points where `poll-pr.sh --once` blocks the shell. The agent consumes zero tokens while waiting. When the script returns, the exit code determines the next state:

- `0` → COMPLETE
- `1` → ADDRESS_FEEDBACK (CI failures)
- `2` → DORMANT_CI (re-poll)
- `3` → ADDRESS_FEEDBACK (review comments)
- `4` → DORMANT_REVIEW (awaiting human)

### Manual Mode

Start with `--manual` to step through each state:

```
Tick #3: IMPLEMENT → TEST
Completed: Implemented pagination across 4 files
Next: Run pre-commit, pytest, mypy

[c] Continue  [s] Skip  [i] Inspect  [a] Abort
```

Ralph Loop principle: "start manual, then automate."

## Prerequisites

This workflow runs in a Quay project that has the existing scripts in `.claude/scripts/` (jira-ops.sh, poll-pr.sh, validate-pr-title.sh, format-and-lint.sh).

## State Persistence

State lives in `.claude/tick-state/<TICKET>.json`. Survives context compaction. Re-running `/work` with the same ticket resumes from the last state.
