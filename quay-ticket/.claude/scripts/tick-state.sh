#!/bin/bash
# tick-state.sh -- State management for the Ralph Loop tick-loop.
#
# Each ticket gets a state file at .claude/tick-state/<TICKET-KEY>.json
# The tick loop reads state, executes the current state, writes back, and continues.
#
# Usage:
#   bash .claude/scripts/tick-state.sh init PROJQUAY-XXXX [--mode manual]
#   bash .claude/scripts/tick-state.sh read PROJQUAY-XXXX
#   bash .claude/scripts/tick-state.sh current PROJQUAY-XXXX
#   bash .claude/scripts/tick-state.sh advance PROJQUAY-XXXX NEXT_STATE
#   bash .claude/scripts/tick-state.sh set PROJQUAY-XXXX FIELD VALUE
#   bash .claude/scripts/tick-state.sh is-dormant PROJQUAY-XXXX

set -euo pipefail

STATE_DIR=".claude/tick-state"
mkdir -p "$STATE_DIR"

ACTION="${1:?Usage: tick-state.sh <action> [args]}"
shift

state_file() {
  echo "${STATE_DIR}/${1}.json"
}

case "$ACTION" in

  init)
    TICKET="${1:?Missing ticket key}"
    shift
    MODE="auto"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    FILE=$(state_file "$TICKET")
    if [ -f "$FILE" ]; then
      STATE=$(jq -r '.state' "$FILE")
      echo "Resuming ${TICKET} from state: ${STATE} (tick #$(jq '.tick_count' "$FILE"))"
      cat "$FILE"
      exit 0
    fi

    jq -n \
      --arg ticket "$TICKET" \
      --arg state "ASSIGN" \
      --arg mode "$MODE" \
      --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg session "${SESSION_ID:-local}" \
      '{
        ticket: $ticket,
        state: $state,
        mode: $mode,
        created_at: $created,
        last_updated: $created,
        session_id: $session,
        tick_count: 0,
        branch: null,
        pr_number: null,
        area_docs: [],
        backport_required: false,
        triage_attempts: 0,
        last_poll_exit: null,
        history: []
      }' > "$FILE"

    echo "Tick state initialized: ${TICKET} → ASSIGN (mode: ${MODE})"
    ;;

  read)
    TICKET="${1:?Missing ticket key}"
    FILE=$(state_file "$TICKET")
    [ -f "$FILE" ] || { echo "No tick state for ${TICKET}" >&2; exit 1; }
    cat "$FILE"
    ;;

  current)
    TICKET="${1:?Missing ticket key}"
    FILE=$(state_file "$TICKET")
    [ -f "$FILE" ] || { echo "No tick state for ${TICKET}" >&2; exit 1; }
    jq -r '.state' "$FILE"
    ;;

  advance)
    TICKET="${1:?Missing ticket key}"
    NEXT="${2:?Missing next state}"
    FILE=$(state_file "$TICKET")
    [ -f "$FILE" ] || { echo "No tick state for ${TICKET}" >&2; exit 1; }

    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PREV=$(jq -r '.state' "$FILE")
    TICK=$(jq '.tick_count' "$FILE")
    NEW_TICK=$((TICK + 1))

    TMP=$(mktemp)
    jq --arg next "$NEXT" \
       --arg now "$NOW" \
       --arg prev "$PREV" \
       --argjson tick "$NEW_TICK" \
       '.state = $next |
        .last_updated = $now |
        .tick_count = $tick |
        .history += [{from: $prev, to: $next, at: $now, tick: $tick}]' \
       "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "${PREV} → ${NEXT} (tick #${NEW_TICK})"
    ;;

  set)
    TICKET="${1:?Missing ticket key}"
    FIELD="${2:?Missing field}"
    VALUE="${3:?Missing value}"
    FILE=$(state_file "$TICKET")
    [ -f "$FILE" ] || { echo "No tick state for ${TICKET}" >&2; exit 1; }

    TMP=$(mktemp)
    # Try to parse as JSON (numbers, booleans, arrays), fall back to string
    if echo "$VALUE" | jq . >/dev/null 2>&1; then
      jq --argjson v "$VALUE" --arg f "$FIELD" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.[$f] = $v | .last_updated = $now' "$FILE" > "$TMP"
    else
      jq --arg v "$VALUE" --arg f "$FIELD" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.[$f] = $v | .last_updated = $now' "$FILE" > "$TMP"
    fi
    mv "$TMP" "$FILE"
    echo "Set ${FIELD}=${VALUE}"
    ;;

  is-dormant)
    TICKET="${1:?Missing ticket key}"
    FILE=$(state_file "$TICKET")
    [ -f "$FILE" ] || { echo "No tick state for ${TICKET}" >&2; exit 1; }
    STATE=$(jq -r '.state' "$FILE")
    if [[ "$STATE" == DORMANT_* ]]; then
      echo "dormant (${STATE})"
      exit 0
    else
      echo "active (${STATE})"
      exit 1
    fi
    ;;

  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Actions: init, read, current, advance, set, is-dormant" >&2
    exit 1
    ;;
esac
