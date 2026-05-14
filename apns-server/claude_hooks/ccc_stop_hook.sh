#!/bin/bash
# CcCompanion Claude Code Stop hook
#
# Trigger: Claude Code 自动在每个 chain turn 结束时调一次. 这里读 transcript
# 抓最近这一 turn 的 assistant 文本, POST 给本地 apns-server /chat/append,
# server 再 push 到 iPhone.
#
# 配置方式 (一次性):
#   1. cp 这一份到 ~/.claude/hooks/ccc_stop_hook.sh
#   2. chmod +x ~/.claude/hooks/ccc_stop_hook.sh
#   3. 编辑 ~/.claude/settings.json 加 hook 引用:
#      {
#        "hooks": {
#          "Stop": [
#            { "type": "command", "command": "~/.claude/hooks/ccc_stop_hook.sh" }
#          ]
#        }
#      }
#   4. 重启 Claude Code (退出 tmux session 重进, 让 hook config 生效)
#
# 验证 hook 跑通:
#   iPhone 端 ccc 发一条 "hi"; Mac 上 cc 回复后, 看
#   tail -f /tmp/ccc_stop_hook.log
#   应该看到 "posted to /chat/append ok"
#
# Env:
#   CCC_SERVER_URL  default http://127.0.0.1:8795
#   CCC_AUTH_TOKEN  shared_secret 跟 server config.toml 对齐 (写接口必须)

set -uo pipefail

SERVER_URL="${CCC_SERVER_URL:-http://127.0.0.1:8795}"
AUTH_TOKEN="${CCC_AUTH_TOKEN:-}"
# 兜底从 server 自动生成的 secret 文件读
if [ -z "$AUTH_TOKEN" ] && [ -f "$HOME/.ots/secret" ]; then
    AUTH_TOKEN=$(cat "$HOME/.ots/secret" 2>/dev/null)
fi

LOG_PATH="/tmp/ccc_stop_hook.log"
log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*" >> "$LOG_PATH"; }

# Claude Code 通过 stdin 传 {session_id, transcript_path, stop_hook_active}
INPUT=$(cat 2>/dev/null || echo "{}")

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
    print(d.get("transcript_path") or "")
except Exception:
    print("")
' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    log "no transcript path (stdin=$INPUT)"
    exit 0
fi

# Claude Code transcript flush 慢 — 等 mtime 稳定 (最多 2 秒)
LAST_SIZE=0
for i in 1 2 3 4 5 6; do
    sleep 0.3
    CUR_SIZE=$(stat -f '%z' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$CUR_SIZE" = "$LAST_SIZE" ]; then
        break
    fi
    LAST_SIZE=$CUR_SIZE
done

# transcript 是 JSONL 一行一条 message
# 倒着读 抓自上次 user 以来的所有 assistant text part 然后 join
LAST_ASSISTANT=$(tail -r "$TRANSCRIPT_PATH" | python3 -c '
import json, sys
collected = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    t = obj.get("type")
    if t == "user":
        break
    if t == "assistant":
        msg = obj.get("message", {})
        content = msg.get("content", [])
        text_parts = [
            c.get("text", "")
            for c in content
            if isinstance(c, dict) and c.get("type") == "text" and c.get("text")
        ]
        if text_parts:
            collected.append("\n".join(text_parts))
collected.reverse()
print("\n\n".join(collected))
' 2>/dev/null)

if [ -z "$LAST_ASSISTANT" ]; then
    log "empty assistant text — skip"
    exit 0
fi

# POST 到 /chat/append
TS=$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z"))')
PAYLOAD=$(python3 -c '
import json, sys, os
text = os.environ.get("ASSISTANT_TEXT", "")
ts = os.environ.get("TS", "")
print(json.dumps({"role": "assistant", "text": text, "source": "ccc-stop-hook", "ts": ts}))
' <<EOF
EOF
)
# Inject env so python json.dumps escapes correctly
PAYLOAD=$(ASSISTANT_TEXT="$LAST_ASSISTANT" TS="$TS" python3 -c '
import json, os
print(json.dumps({
    "role": "assistant",
    "text": os.environ["ASSISTANT_TEXT"],
    "source": "ccc-stop-hook",
    "ts": os.environ["TS"],
}))
')

HTTP_CODE=$(curl -s -o /tmp/ccc_stop_hook.curlout -w "%{http_code}" \
    -X POST "$SERVER_URL/chat/append" \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    --data "$PAYLOAD" \
    --max-time 8 2>>"$LOG_PATH")

if [ "$HTTP_CODE" = "200" ]; then
    log "posted to /chat/append ok (chars=${#LAST_ASSISTANT})"
else
    log "POST /chat/append failed http=$HTTP_CODE body=$(cat /tmp/ccc_stop_hook.curlout 2>/dev/null | head -c 200)"
fi

exit 0
