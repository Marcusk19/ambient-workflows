---
name: swarm
description: >
  Coordinator skill for multi-story feature development. Decomposes a JIRA epic
  into stories, spawns parallel implementer agents as child ambient sessions,
  monitors progress, triggers reviews, and validates integration.
argument-hint: PROJQUAY-XXXX
allowed-tools:
  - Bash(acli *)
  - Bash(gh *)
  - Bash(bash .claude/scripts/swarm-state.sh *)
  - Bash(jq *)
  - Bash(cat *)
  - Read
  - Write
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - CronCreate
  - CronDelete
  - CronList
  - mcp:acp_create_session
  - mcp:acp_get_session_status
  - mcp:acp_list_sessions
  - mcp:acp_send_message
  - mcp:acp_stop_session
---

# Feature Swarm — Coordinator

Orchestrate multi-story implementation of epic `$ARGUMENTS`.

## Phase 1: Decompose Epic

### Step 1.1: Fetch Epic

```bash
acli jira workitem view $ARGUMENTS
```

Read the epic summary, description, acceptance criteria, and any existing child issues.

### Step 1.2: Analyze and Decompose

Break the epic into independently deliverable stories. For each story, define:
- **Summary**: one-line description
- **Scope**: what files/subsystems are touched
- **Acceptance criteria**: concrete, testable outcomes
- **Dependencies**: which other stories must complete first (if any)

Guidelines for decomposition:
- Each story should be implementable by a single agent in one session
- Prefer vertical slices (schema + API + test) over horizontal layers
- Database migrations should be in their own story when they affect large tables
- Frontend and backend can be separate stories if they're independently testable
- Keep stories small enough that the agent doesn't hit context limits

### Step 1.3: Present to User

Display the story breakdown with a dependency graph:

```
Epic: PROJQUAY-XXXX — <summary>

Stories:
  1. STORY-A: <summary>              [no deps]
  2. STORY-B: <summary>              [no deps]
  3. STORY-C: <summary>              [depends on: A]
  4. STORY-D: <summary>              [depends on: A, B]

Dependency graph:
  A ──┐
      ├──→ C
  B ──┤
      └──→ D
```

Ask the user to approve, edit, or remove stories before proceeding.

### Step 1.4: Create Stories in JIRA

For each approved story, create it in JIRA linked to the parent epic:

```bash
acli jira workitem create --project PROJQUAY --type Story \
  --summary "<summary>" \
  --description "<description with acceptance criteria>" \
  --parent $ARGUMENTS
```

Record the created story keys.

### Step 1.5: Initialize Swarm State

```bash
bash .claude/scripts/swarm-state.sh init $ARGUMENTS
```

Then update the state file with story details:

```bash
bash .claude/scripts/swarm-state.sh add-story $ARGUMENTS \
  --key PROJQUAY-YYYY \
  --summary "<summary>" \
  --depends-on "PROJQUAY-ZZZZ"
```

---

## Phase 2: Spawn Implementers

### Step 2.1: Identify Ready Stories

A story is ready to spawn when all its dependencies have status `pr-created` or later.
On first run, stories with no dependencies are ready immediately.

### Step 2.2: Check Concurrency

Read `max_concurrency` from swarm state (default: 3). Count stories with status
`implementing`. Only spawn if under the limit.

### Step 2.3: Spawn Child Session

For each ready story within the concurrency limit:

```
acp_create_session({
  project_id: $PROJECT_NAME,
  prompt: "You are an implementer agent. Your task is PROJQUAY-YYYY: <full story summary and acceptance criteria>.

Run the following skills in order:
1. /start PROJQUAY-YYYY — assigns the ticket, creates your branch, loads area docs
2. /code — implements the changes, runs tests, commits
3. /pr — creates the pull request with correct title format
4. /poll <PR#> — monitors CI and reviews

Do not stop until the PR is created and CI is being polled.
Do not ask the user for confirmation — execute autonomously.

When you are done, your session will end naturally after /poll completes or reaches exit code 4 (awaiting human review).",
  parent_session_id: $SESSION_ID,
  name: "impl-PROJQUAY-YYYY"
})
```

Update swarm state:

```bash
bash .claude/scripts/swarm-state.sh update-story $ARGUMENTS \
  --key PROJQUAY-YYYY \
  --session-id "<returned-session-id>" \
  --status implementing
```

### Step 2.4: Report

Tell the user which agents were spawned and which stories are blocked.

---

## Phase 3: Monitor

### Step 3.1: Check Child Sessions

For each story with status `implementing`, check its session:

```
acp_get_session_status({ session_id: "<session-id>" })
```

### Step 3.2: Process Outcomes

- **Session completed successfully**: Check if a PR was created by searching:
  ```bash
  gh pr list --head "PROJQUAY-YYYY" --repo quay/quay --json number,state --jq '.[0]'
  ```
  Update story status to `pr-created` and record the PR number.

- **Session failed/errored**: Report to user. Ask whether to respawn or skip.

- **Session still running**: No action needed. Report progress.

### Step 3.3: Unblock Dependents

After updating statuses, check if any blocked stories are now ready (all dependencies
at `pr-created` or later). If so, go back to Phase 2 to spawn them.

### Step 3.4: Monitor Loop

If stories are still in `implementing` or `blocked` status, set up a periodic check:

```
CronCreate: every 5 minutes, /swarm-status
```

Delete the cron once all stories reach `pr-created` or later.

---

## Phase 4: Review

### Step 4.1: Identify Reviewable PRs

Stories with status `pr-created` that have CI passing are ready for review.
Check CI status:

```bash
gh pr checks <PR#> --repo quay/quay --json name,state,bucket \
  | jq '[.[] | select(.bucket == "fail")] | length'
```

If CI is still pending or failing, skip — the implementer's `/poll` will handle it.

### Step 4.2: Spawn Reviewer

For each reviewable PR:

```
acp_create_session({
  project_id: $PROJECT_NAME,
  prompt: "You are a senior Quay code reviewer. Review PR #NNN in the quay/quay repo.

Use the /review-pr NNN command to perform a thorough review covering:
- Migration safety (table locks, backfill, downgrade)
- Query patterns (N+1, missing indexes, full scans)
- API design and error handling
- Test coverage and quality
- Security considerations

Post your review directly on the PR via gh CLI.
If you approve, post an APPROVED review.
If you request changes, be specific about what needs fixing.",
  parent_session_id: $SESSION_ID,
  name: "review-PR-NNN"
})
```

Update story status to `reviewing` and record reviewer session ID.

### Step 4.3: Process Review Outcomes

When the reviewer session completes:
- Check the PR's review state: `gh pr view <PR#> --repo quay/quay --json reviewDecision`
- If APPROVED: update story status to `approved`
- If CHANGES_REQUESTED: update status to `changes-requested`, notify user

---

## Phase 5: Integration

### Step 5.1: Gate Check

Only proceed when ALL stories have status `approved`.

### Step 5.2: Spawn Integration Tester

```
acp_create_session({
  project_id: $PROJECT_NAME,
  prompt: "You are the integration tester for epic $ARGUMENTS.

The following PRs implement this epic:
<list all PR numbers and their story summaries>

Validate cross-story integration:
1. Check for Alembic migration chain conflicts: run `alembic heads` — there must be exactly one head
2. Check for import conflicts across PRs (duplicate symbols, circular imports)
3. Check for API contract mismatches between stories
4. Run the full test suite: `make unit-test && make registry-test && make types-test`
5. Report any integration issues with specific file paths and line numbers

If integration passes, report success.
If issues are found, list each one with the affected PRs and suggested fixes.",
  parent_session_id: $SESSION_ID,
  name: "integrate-$ARGUMENTS"
})
```

### Step 5.3: Handle Integration Results

- **Pass**: Update swarm phase to `complete`. Proceed to Phase 6.
- **Fail**: Report issues to user. The user decides whether to spawn fix sessions.

---

## Phase 6: Report and Close

### Step 6.1: Summary

Present a final report:

```
Feature Swarm Complete: $ARGUMENTS

Stories: N implemented, N PRs created, N approved
PRs: #A, #B, #C, #D
Integration: passed/failed
Duration: <total time>

Story Details:
  PROJQUAY-YYYY  PR #456  approved  ✓ integrated
  PROJQUAY-ZZZZ  PR #457  approved  ✓ integrated
  ...
```

### Step 6.2: JIRA Updates

- Transition the epic to its next status
- If Target Version is set, note that backporting will be needed after merge

### Step 6.3: Cleanup

```bash
bash .claude/scripts/swarm-state.sh set-phase $ARGUMENTS complete
```
