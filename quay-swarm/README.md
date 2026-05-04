# Quay Feature Swarm

Multi-agent workflow for large Quay features. Decomposes JIRA epics into stories and spawns parallel implementer, reviewer, and integration agents as child ambient sessions.

## How It Works

```
/swarm PROJQUAY-XXXX
    │
    ├── Phase 1: Decompose epic into stories
    │   └── Present to user for approval → create in JIRA
    │
    ├── Phase 2: Spawn implementers (parallel, up to 3)
    │   ├── impl-PROJQUAY-1001  ──→  /start → /code → /pr → /poll
    │   ├── impl-PROJQUAY-1002  ──→  /start → /code → /pr → /poll
    │   └── impl-PROJQUAY-1003  ──→  (blocked, waiting on 1001)
    │
    ├── Phase 3: Monitor progress, unblock dependents
    │
    ├── Phase 4: Spawn reviewers for each PR
    │   ├── review-PR-456  ──→  /review-pr 456
    │   └── review-PR-457  ──→  /review-pr 457
    │
    ├── Phase 5: Integration testing (after all PRs approved)
    │   └── integrate-PROJQUAY-XXXX  ──→  alembic check, tests
    │
    └── Phase 6: Report and close epic
```

## Commands

| Command | Purpose |
|---------|---------|
| `/swarm PROJQUAY-XXXX` | Decompose epic and spawn agent team |
| `/swarm-status` | Progress dashboard for all agents and PRs |
| `/swarm-review <PR#>` | Manually spawn a reviewer for a PR |

## Prerequisites

- Child sessions run in a Quay project that has the single-ticket workflow (`.claude/skills/` with `/start`, `/code`, `/pr`, `/poll`)
- JIRA access via `acli` (credentials inherited from parent session)
- GitHub access via `gh` CLI (credentials inherited from parent session)

## Architecture

- **Coordinator** (this workflow) — decomposes, delegates, monitors
- **Implementers** (child sessions) — each implements one story using the Quay single-ticket pipeline
- **Reviewers** (child sessions) — each reviews one PR
- **Integration tester** (child session) — validates cross-story compatibility after all PRs pass

Child sessions are spawned via `acp_create_session` with `parent_session_id` for automatic credential inheritance.

## State

Swarm state is tracked in `.claude/swarm-state/<EPIC-KEY>.json` with story statuses:

```
pending → implementing → pr-created → reviewing → approved → done
                                                 ↘ changes-requested
```
