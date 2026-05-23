#!/usr/bin/env bash
# Claude Code Stop hook example. Reads optional hook JSON from stdin and posts a workgroup event.
set -euo pipefail

BASE_URL="${WORKGROUP_URL:-http://127.0.0.1:8795}"
SECRET="${WORKGROUP_SECRET:-}"
AGENT_ID="${AGENT_ID:-opia}"
NOTIFY_TARGET="${WORKGROUP_NOTIFY_TARGET:-user}"
MESSAGE_TYPE="${WORKGROUP_HOOK_MESSAGE_TYPE:-ship}"
INPUT_JSON="$(cat || true)"

AUTH_ARGS=()
if [[ -n "$SECRET" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $SECRET")
fi

PAYLOAD="$(
  python3 - "$AGENT_ID" "$NOTIFY_TARGET" "$MESSAGE_TYPE" "$INPUT_JSON" <<'PY'
import json
import sys

agent_id, notify_target, message_type, raw = sys.argv[1:5]
result_path = ""
try:
    data = json.loads(raw) if raw.strip() else {}
    result_path = str(data.get("result_path") or data.get("transcript_path") or "")
except Exception:
    result_path = ""

suffix = f" result {result_path}" if result_path else ""
print(json.dumps({
    "sender_id": agent_id,
    "mentions": [notify_target],
    "message_type": message_type,
    "text": f"@{notify_target} agent stopped{suffix}",
    "source": "claude-hook",
}, ensure_ascii=False))
PY
)"

curl -sS -X POST "$BASE_URL/group/send" \
  -H "Content-Type: application/json" \
  "${AUTH_ARGS[@]}" \
  -d "$PAYLOAD" >/dev/null

