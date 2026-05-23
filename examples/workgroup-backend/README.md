# Workgroup Backend Example

This folder is a minimal local backend for the CcCompanion workgroup tab.

It gives you:

- `/group/send`
- `/group/poll`
- `/group/roster`
- `/group/typing`
- `/group/roster_heartbeat`
- JSONL message storage
- a generic tmux dispatch script
- an agent heartbeat script
- a Claude Code Stop hook example

## 1. Start the server

```bash
cd examples/workgroup-backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

export WORKGROUP_SECRET=dev-secret
export WORKGROUP_DATA_DIR="$PWD/.workgroup-data"
python3 group_chat_server.py --host 127.0.0.1 --port 8795
```

In another terminal:

```bash
export WORKGROUP_URL=http://127.0.0.1:8795
export WORKGROUP_SECRET=dev-secret
```

## 2. Smoke test the endpoints

Health:

```bash
curl -s "$WORKGROUP_URL/health"
```

Roster:

```bash
curl -s "$WORKGROUP_URL/group/roster" \
  -H "Authorization: Bearer $WORKGROUP_SECRET"
```

Send a task:

```bash
curl -s -X POST "$WORKGROUP_URL/group/send" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WORKGROUP_SECRET" \
  -d '{
    "sender_id": "user",
    "mentions": ["shu"],
    "message_type": "task",
    "owner": "shu",
    "text": "@shu test task from user"
  }'
```

Poll messages:

```bash
curl -s "$WORKGROUP_URL/group/poll?limit=120" \
  -H "Authorization: Bearer $WORKGROUP_SECRET"
```

Typing state:

```bash
curl -s -X POST "$WORKGROUP_URL/group/typing" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WORKGROUP_SECRET" \
  -d '{"sender_id":"shu","is_typing":true,"status_text":"reading spec"}'
```

Heartbeat once:

```bash
AGENT_ID=shu AGENT_NAME=Codex AGENT_MODEL=GPT ./agent_register.sh --once
```

## 3. Keep an agent online

```bash
export AGENT_ID=shu
export AGENT_NAME=Codex
export AGENT_MODEL=GPT-5.5
./agent_register.sh
```

The script posts to `/group/roster_heartbeat` every 30 seconds.

## 4. Dispatch to a tmux agent

Start a local agent session:

```bash
tmux new -s shu
```

From another shell:

```bash
./dispatch.sh shu /absolute/path/to/spec.md high
```

The dispatch template:

1. validates the spec file
2. checks the tmux session
3. posts a `message_type=task` message to the group
4. injects the instruction into tmux

## 5. Add the Claude Code Stop hook

Example hook config:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/examples/workgroup-backend/claude_hook.sh"
          }
        ]
      }
    ]
  }
}
```

Environment:

```bash
export WORKGROUP_URL=http://127.0.0.1:8795
export WORKGROUP_SECRET=dev-secret
export AGENT_ID=opia
export WORKGROUP_NOTIFY_TARGET=user
```

## 6. Point CcCompanion at it

Use the same server URL and secret in CcCompanion. The workgroup tab needs:

- `GET /group/poll`
- `GET /group/roster`
- `POST /group/send`
- `POST /group/typing`

If your phone is not on the same machine, expose the server through a trusted local network path or private VPN.

