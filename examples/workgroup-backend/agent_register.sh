#!/usr/bin/env bash
# Register an agent and keep its online heartbeat fresh.
set -euo pipefail

BASE_URL="${WORKGROUP_URL:-http://127.0.0.1:8795}"
SECRET="${WORKGROUP_SECRET:-}"
AGENT_ID="${AGENT_ID:-shu}"
AGENT_NAME="${AGENT_NAME:-$AGENT_ID}"
AGENT_MODEL="${AGENT_MODEL:-local-agent}"
INTERVAL="${WORKGROUP_HEARTBEAT_SECONDS:-30}"
ONCE=0

if [[ "${1:-}" == "--once" ]]; then
  ONCE=1
fi

AUTH_ARGS=()
if [[ -n "$SECRET" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $SECRET")
fi

heartbeat() {
  local payload
  payload="$(
    python3 - "$AGENT_ID" "$AGENT_NAME" "$AGENT_MODEL" <<'PY'
import json
import sys

agent_id, name, model = sys.argv[1:4]
print(json.dumps({
    "sender_id": agent_id,
    "display_name": name,
    "model": model,
    "status_text": "idle",
}, ensure_ascii=False))
PY
  )"
  curl -sS -X POST "$BASE_URL/group/roster_heartbeat" \
    -H "Content-Type: application/json" \
    "${AUTH_ARGS[@]}" \
    -d "$payload" >/dev/null
}

heartbeat
if [[ "$ONCE" == "1" ]]; then
  exit 0
fi

while true; do
  sleep "$INTERVAL"
  heartbeat
done

