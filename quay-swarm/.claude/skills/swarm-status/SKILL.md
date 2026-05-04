---
name: swarm-status
description: >
  Progress dashboard for an active feature swarm. Shows all stories, their
  agent sessions, PRs, CI status, and review state in a summary table.
allowed-tools:
  - Bash(bash .claude/scripts/swarm-state.sh *)
  - Bash(gh *)
  - Bash(jq *)
  - Bash(cat *)
  - Read
  - Glob
  - mcp:acp_get_session_status
  - mcp:acp_list_sessions
---

# Swarm Status Dashboard

Show progress for the active feature swarm.

## Step 1: Find Active Swarm

Look for swarm state files:

```bash
bash .claude/scripts/swarm-state.sh list
```

If `$ARGUMENTS` is provided, use that epic key. Otherwise, use the most recent active swarm.

## Step 2: Read State

```bash
bash .claude/scripts/swarm-state.sh read <EPIC-KEY>
```

## Step 3: Enrich with Live Data

For each story in the swarm state:

1. **Session status**: Call `acp_get_session_status` for stories with active sessions
2. **PR status**: For stories with a PR number:
   ```bash
   gh pr checks <PR#> --repo quay/quay --json name,state,bucket 2>/dev/null \
     | jq '{pass: [.[] | select(.bucket=="pass")] | length,
            fail: [.[] | select(.bucket=="fail")] | length,
            pending: [.[] | select(.bucket=="pending")] | length}'
   ```
3. **Review status**: 
   ```bash
   gh pr view <PR#> --repo quay/quay --json reviewDecision --jq '.reviewDecision'
   ```

## Step 4: Display Dashboard

```
═══════════════════════════════════════════════════════════════════
  PROJQUAY-XXXX Feature Swarm — Phase: <phase>
  Started: <timestamp>  |  Concurrency: <N>/<max>
═══════════════════════════════════════════════════════════════════

  Story             Session          PR      CI          Review       Status
  ─────────────────────────────────────────────────────────────────────────
  PROJQUAY-1001     impl-1001        #456    12/12 pass  APPROVED     done
  PROJQUAY-1002     impl-1002        #457    8/12 run    —            implementing
  PROJQUAY-1003     (blocked)        —       —           —            waiting on 1001
  PROJQUAY-1004     impl-1004        #458    0/12 pend   —            pr-created

  Integration: <pending|running|passed|failed>

═══════════════════════════════════════════════════════════════════
```

## Step 5: Suggest Actions

Based on current state, suggest next actions:
- Stories ready to spawn (deps resolved, under concurrency limit)
- PRs ready for review (CI passing, not yet reviewed)
- Integration ready to run (all stories approved)
- Failed sessions that need respawning
