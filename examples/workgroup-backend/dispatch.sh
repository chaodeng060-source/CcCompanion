#!/usr/bin/env bash
# Generic workgroup dispatch template.
set -euo pipefail

BASE_URL="${WORKGROUP_URL:-http://127.0.0.1:8795}"
SECRET="${WORKGROUP_SECRET:-}"
SENDER_ID="${WORKGROUP_SENDER_ID:-user}"
AGENT_ID="${1:-}"
SPEC_PATH="${2:-}"
PRIORITY="${3:-normal}"
TMUX_SESSION="${AGENT_TMUX_SESSION:-$AGENT_ID}"

if [[ -z "$AGENT_ID" || -z "$SPEC_PATH" ]]; then
  echo "usage: $0 <agent_id> <spec_path> [priority]" >&2
  exit 2
fi

if [[ ! -f "$SPEC_PATH" ]]; then
  echo "spec not found: $SPEC_PATH" >&2
  exit 1
fi

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "tmux session not found: $TMUX_SESSION" >&2
  exit 1
fi

AUTH_ARGS=()
if [[ -n "$SECRET" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $SECRET")
fi

TEXT="@$AGENT_ID please execute $SPEC_PATH priority=$PRIORITY"
PAYLOAD="$(
  python3 - "$SENDER_ID" "$AGENT_ID" "$TEXT" "$PRIORITY" <<'PY'
import json
import sys

sender_id, agent_id, text, priority = sys.argv[1:5]
print(json.dumps({
    "sender_id": sender_id,
    "mentions": [agent_id],
    "message_type": "task",
    "owner": agent_id,
    "text": text,
    "meta": {"priority": priority},
}, ensure_ascii=False))
PY
)"

curl -sS -X POST "$BASE_URL/group/send" \
  -H "Content-Type: application/json" \
  "${AUTH_ARGS[@]}" \
  -d "$PAYLOAD" >/dev/null

tmux send-keys -t "$TMUX_SESSION" -l "Please execute $SPEC_PATH priority=$PRIORITY. Report completion to the workgroup with message_type=ship."
tmux send-keys -t "$TMUX_SESSION" Enter

echo "dispatched $SPEC_PATH to $AGENT_ID through $TMUX_SESSION"

