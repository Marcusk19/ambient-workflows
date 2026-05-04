---
name: swarm-review
description: >
  Spawn a reviewer child session for a specific PR. Use when auto-review
  didn't trigger or a re-review is needed after fixes.
argument-hint: PR_NUMBER
allowed-tools:
  - Bash(bash .claude/scripts/swarm-state.sh *)
  - Bash(gh *)
  - Read
  - Glob
  - mcp:acp_create_session
  - mcp:acp_get_session_status
---

# Spawn Reviewer for PR

Manually trigger a code review for PR #$ARGUMENTS.

## Step 1: Validate PR

```bash
gh pr view $ARGUMENTS --repo quay/quay --json title,state,headRefName,reviewDecision \
  --jq '{title,state,branch:.headRefName,review:.reviewDecision}'
```

The PR must be open. If already approved, confirm with the user before re-reviewing.

## Step 2: Check Active Swarm

Find the swarm state that contains this PR:

```bash
bash .claude/scripts/swarm-state.sh find-by-pr $ARGUMENTS
```

If found, update the story's status to `reviewing`.

## Step 3: Spawn Reviewer

```
acp_create_session({
  project_id: $PROJECT_NAME,
  prompt: "You are a senior Quay code reviewer. Review PR #$ARGUMENTS in the quay/quay repo.

Use the /review-pr $ARGUMENTS command to perform a thorough review covering:
- Migration safety (table locks, backfill, downgrade paths)
- Query patterns (N+1, missing indexes, full table scans, transaction scope)
- API design, error handling, and backward compatibility
- Test coverage and quality
- Security considerations (injection, auth bypass, secrets)

Post your review directly on the PR.
If you approve, submit an APPROVED review.
If you request changes, be specific about what needs fixing and why.",
  parent_session_id: $SESSION_ID,
  name: "review-PR-$ARGUMENTS"
})
```

## Step 4: Report

Tell the user:
- Reviewer session spawned for PR #$ARGUMENTS
- Session name: review-PR-$ARGUMENTS
- Run `/swarm-status` to check when the review completes
