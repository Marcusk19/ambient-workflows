#!/bin/bash
# swarm-state.sh -- Read/write helper for feature swarm state files.
#
# State files live at .claude/swarm-state/<EPIC-KEY>.json
#
# Usage:
#   bash .claude/scripts/swarm-state.sh init PROJQUAY-XXXX [--max-concurrency N]
#   bash .claude/scripts/swarm-state.sh read PROJQUAY-XXXX
#   bash .claude/scripts/swarm-state.sh list
#   bash .claude/scripts/swarm-state.sh add-story PROJQUAY-XXXX --key PROJQUAY-YYYY --summary "..." [--depends-on "KEY1,KEY2"]
#   bash .claude/scripts/swarm-state.sh update-story PROJQUAY-XXXX --key PROJQUAY-YYYY [--session-id ID] [--session-name NAME] [--branch NAME] [--pr-number N] [--status STATUS] [--reviewer-session-id ID] [--review-verdict VERDICT]
#   bash .claude/scripts/swarm-state.sh set-phase PROJQUAY-XXXX PHASE
#   bash .claude/scripts/swarm-state.sh ready-stories PROJQUAY-XXXX
#   bash .claude/scripts/swarm-state.sh find-by-pr PR_NUMBER
#   bash .claude/scripts/swarm-state.sh concurrency PROJQUAY-XXXX

set -euo pipefail

STATE_DIR=".claude/swarm-state"
mkdir -p "$STATE_DIR"

ACTION="${1:?Usage: swarm-state.sh <action> [args]}"
shift

state_file() {
  echo "${STATE_DIR}/${1}.json"
}

case "$ACTION" in

  init)
    EPIC="${1:?Missing epic key}"
    shift
    MAX_CONCURRENCY=3
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --max-concurrency) MAX_CONCURRENCY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    FILE=$(state_file "$EPIC")
    if [ -f "$FILE" ]; then
      echo "Swarm state already exists for ${EPIC}. Use 'read' to view it." >&2
      exit 1
    fi

    jq -n \
      --arg epic "$EPIC" \
      --arg phase "decomposing" \
      --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg session "${SESSION_ID:-unknown}" \
      --argjson max "$MAX_CONCURRENCY" \
      '{
        epic: $epic,
        phase: $phase,
        created_at: $created,
        coordinator_session: $session,
        max_concurrency: $max,
        stories: [],
        integration: { session_id: null, status: "pending" }
      }' > "$FILE"

    echo "Swarm state initialized: ${FILE}"
    ;;

  read)
    EPIC="${1:?Missing epic key}"
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }
    cat "$FILE"
    ;;

  list)
    for f in "$STATE_DIR"/*.json; do
      [ -f "$f" ] || continue
      jq -r '[.epic, .phase, .created_at, (.stories | length | tostring) + " stories"] | join("  ")' "$f"
    done
    ;;

  add-story)
    EPIC="${1:?Missing epic key}"; shift
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }

    KEY="" SUMMARY="" DEPENDS=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --key) KEY="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --depends-on) DEPENDS="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    [ -z "$KEY" ] && { echo "Missing --key" >&2; exit 1; }
    [ -z "$SUMMARY" ] && { echo "Missing --summary" >&2; exit 1; }

    # Convert comma-separated depends to JSON array
    if [ -n "$DEPENDS" ]; then
      DEPS_JSON=$(echo "$DEPENDS" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
    else
      DEPS_JSON='[]'
    fi

    TMP=$(mktemp)
    jq --arg key "$KEY" \
       --arg summary "$SUMMARY" \
       --argjson deps "$DEPS_JSON" \
       '.stories += [{
          key: $key,
          summary: $summary,
          depends_on: $deps,
          impl_session_id: null,
          impl_session_name: null,
          branch: null,
          pr_number: null,
          status: "pending",
          reviewer_session_id: null,
          review_verdict: null
        }]' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "Added story ${KEY} to ${EPIC}"
    ;;

  update-story)
    EPIC="${1:?Missing epic key}"; shift
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }

    KEY=""
    UPDATES=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --key) KEY="$2"; shift 2 ;;
        --session-id) UPDATES+=("impl_session_id" "$2"); shift 2 ;;
        --session-name) UPDATES+=("impl_session_name" "$2"); shift 2 ;;
        --branch) UPDATES+=("branch" "$2"); shift 2 ;;
        --pr-number) UPDATES+=("pr_number" "$2"); shift 2 ;;
        --status) UPDATES+=("status" "$2"); shift 2 ;;
        --reviewer-session-id) UPDATES+=("reviewer_session_id" "$2"); shift 2 ;;
        --review-verdict) UPDATES+=("review_verdict" "$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    [ -z "$KEY" ] && { echo "Missing --key" >&2; exit 1; }

    TMP=$(mktemp)
    JQ_EXPR='.'
    for ((i=0; i<${#UPDATES[@]}; i+=2)); do
      FIELD="${UPDATES[$i]}"
      VALUE="${UPDATES[$((i+1))]}"
      if [[ "$FIELD" == "pr_number" ]]; then
        JQ_EXPR="${JQ_EXPR} | (.stories[] | select(.key == \$key)).${FIELD} = (${VALUE} | tonumber)"
      else
        JQ_EXPR="${JQ_EXPR} | (.stories[] | select(.key == \$key)).${FIELD} = \"${VALUE}\""
      fi
    done

    jq --arg key "$KEY" "$JQ_EXPR" "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    echo "Updated story ${KEY}"
    ;;

  set-phase)
    EPIC="${1:?Missing epic key}"
    PHASE="${2:?Missing phase}"
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }

    TMP=$(mktemp)
    jq --arg phase "$PHASE" '.phase = $phase' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    echo "Phase set to ${PHASE} for ${EPIC}"
    ;;

  ready-stories)
    # Print stories whose dependencies are all at pr-created or later
    EPIC="${1:?Missing epic key}"
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }

    RESOLVED_STATUSES='["pr-created","reviewing","approved","changes-requested","done"]'

    jq -r --argjson resolved "$RESOLVED_STATUSES" '
      .stories as $all |
      .stories[] |
      select(.status == "pending") |
      select(
        .depends_on == [] or
        (.depends_on | all(. as $dep |
          $all[] | select(.key == $dep) | .status | IN($resolved[])))
      ) |
      .key + "  " + .summary
    ' "$FILE"
    ;;

  concurrency)
    # Print current/max concurrency
    EPIC="${1:?Missing epic key}"
    FILE=$(state_file "$EPIC")
    [ -f "$FILE" ] || { echo "No swarm state for ${EPIC}" >&2; exit 1; }

    ACTIVE=$(jq '[.stories[] | select(.status == "implementing")] | length' "$FILE")
    MAX=$(jq '.max_concurrency' "$FILE")
    echo "${ACTIVE}/${MAX}"
    ;;

  find-by-pr)
    PR="${1:?Missing PR number}"
    for f in "$STATE_DIR"/*.json; do
      [ -f "$f" ] || continue
      MATCH=$(jq -r --argjson pr "$PR" '
        .stories[] | select(.pr_number == $pr) | .key
      ' "$f" 2>/dev/null || true)
      if [ -n "$MATCH" ]; then
        EPIC=$(jq -r '.epic' "$f")
        echo "${EPIC}  ${MATCH}"
        exit 0
      fi
    done
    echo "PR #${PR} not found in any swarm state" >&2
    exit 1
    ;;

  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Actions: init, read, list, add-story, update-story, set-phase, ready-stories, concurrency, find-by-pr" >&2
    exit 1
    ;;
esac
