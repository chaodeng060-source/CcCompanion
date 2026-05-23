#!/usr/bin/env python3
"""Minimal CcCompanion workgroup backend example."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import threading
import time
import uuid
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


DATA_DIR = Path(os.environ.get("WORKGROUP_DATA_DIR", ".workgroup-data")).expanduser()
SECRET = os.environ.get("WORKGROUP_SECRET", "")
OFFLINE_AFTER_SECONDS = int(os.environ.get("WORKGROUP_OFFLINE_AFTER", "90"))
MENTION_RE = re.compile(r"@([A-Za-z0-9_\-]+|[\u4e00-\u9fff]+)")
MESSAGE_TYPES = {"task", "decision", "ship", "block", "progress", "chat"}
ALL_TOKEN = "__all__"

DEFAULT_ROSTER: list[dict[str, Any]] = [
    {
        "id": "user",
        "display_name": "User",
        "kind": "human",
        "avatar": "U",
        "color": "neutral",
        "model": None,
        "can_reply": False,
    },
    {
        "id": "opia",
        "display_name": "Opia",
        "kind": "agent",
        "avatar": "O",
        "color": "orange",
        "model": "Claude",
        "can_reply": True,
        "default_responder": True,
    },
    {
        "id": "shu",
        "display_name": "Codex",
        "kind": "agent",
        "avatar": "S",
        "color": "green",
        "model": "GPT",
        "can_reply": True,
    },
    {
        "id": "sonnet",
        "display_name": "Sonnet",
        "kind": "agent",
        "avatar": "N",
        "color": "blue",
        "model": "Claude Sonnet",
        "can_reply": True,
    },
]


def load_roster() -> list[dict[str, Any]]:
    raw = os.environ.get("WORKGROUP_ROSTER_JSON")
    if not raw:
        return DEFAULT_ROSTER
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return data
    except Exception:
        pass
    return DEFAULT_ROSTER


ROSTER = load_roster()
ROSTER_BY_ID = {str(m.get("id")): m for m in ROSTER}
AGENT_IDS = [str(m["id"]) for m in ROSTER if m.get("can_reply")]
ALIASES = {
    "all": ALL_TOKEN,
    "__all__": ALL_TOKEN,
    "everyone": ALL_TOKEN,
    "user": "user",
    "me": "user",
    **{str(m["id"]).lower(): str(m["id"]) for m in ROSTER},
}

MESSAGE_PATH = DATA_DIR / "group_messages.jsonl"
STATE_PATH = DATA_DIR / "roster_state.json"
LOCK = threading.Lock()
app = FastAPI(title="CcCompanion workgroup backend example")


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")


def load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {"agents": {}}
    try:
        with STATE_PATH.open(encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {"agents": {}}
    except Exception:
        return {"agents": {}}


STATE = load_state()


def save_state() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(STATE, f, ensure_ascii=False, indent=2)
    tmp.replace(STATE_PATH)


def json_response(status: int, body: dict[str, Any]) -> JSONResponse:
    return JSONResponse(status_code=status, content=body)


@app.middleware("http")
async def require_secret(request: Request, call_next):
    if SECRET and request.url.path != "/health":
        auth = request.headers.get("authorization", "")
        token = auth.removeprefix("Bearer ").strip()
        header_secret = request.headers.get("x-workgroup-secret", "").strip()
        if token != SECRET and header_secret != SECRET:
            return json_response(401, {"ok": False, "error": "bad or missing workgroup secret"})
    return await call_next(request)


def normalize_mentions(raw: Any, text: str = "") -> list[str]:
    items: list[str] = []
    if isinstance(raw, str):
        items.extend(x.strip() for x in raw.split(",") if x.strip())
    elif isinstance(raw, list):
        items.extend(str(x).strip() for x in raw if str(x).strip())
    items.extend(m.group(1) for m in MENTION_RE.finditer(text or ""))

    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        agent_id = ALIASES.get(item.strip().lstrip("@").lower())
        if agent_id and agent_id not in seen:
            out.append(agent_id)
            seen.add(agent_id)
    return out


def default_responder() -> str | None:
    for member in ROSTER:
        if member.get("default_responder"):
            return str(member["id"])
    return AGENT_IDS[0] if AGENT_IDS else None


def targets_for(sender_id: str, mentions: list[str]) -> list[str]:
    if sender_id not in AGENT_IDS:
        mentions = mentions or ([default_responder()] if default_responder() else [])
        if ALL_TOKEN in mentions:
            return AGENT_IDS
        return [m for m in mentions if m in AGENT_IDS]
    if not mentions or ALL_TOKEN in mentions:
        return []
    return [m for m in mentions if m in AGENT_IDS and m != sender_id]


def append_record(body: dict[str, Any], mentions: list[str], targets: list[str]) -> dict[str, Any]:
    sender_id = str(body.get("sender_id") or "user").strip()
    member = ROSTER_BY_ID.get(sender_id)
    message_type = str(body.get("message_type") or "chat").strip().lower()
    if not member:
        raise ValueError(f"unknown sender_id: {sender_id}")
    if message_type not in MESSAGE_TYPES:
        raise ValueError(f"bad message_type: {message_type}")
    text = str(body.get("text") or "").strip()
    if not text:
        raise ValueError("text required")
    task_id = str(body.get("task_id") or "").strip() or None
    if message_type == "task" and not task_id:
        task_id = f"task_{int(time.time() * 1000)}_{uuid.uuid4().hex[:6]}"

    record = {
        "id": f"grp_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}",
        "ts": now_iso(),
        "conversation_id": str(body.get("conversation_id") or "workgroup"),
        "sender_id": sender_id,
        "sender_model": body.get("model") or member.get("model"),
        "text": text,
        "mentions": mentions,
        "parent_msg_id": body.get("parent_msg_id"),
        "reply_to": body.get("reply_to"),
        "source": str(body.get("source") or "api"),
        "delivery": {
            "targets": targets,
            "mode": "all" if ALL_TOKEN in mentions else ("mention" if mentions else "default"),
            "dispatch_id": f"dsp_{int(time.time() * 1000)}",
            "delivered": [],
            "failed": [],
        },
        "meta": {"client_msg_id": body.get("client_msg_id")} if body.get("client_msg_id") else {},
        "message_type": message_type,
        "task_id": task_id,
        "parent_task_id": str(body.get("parent_task_id") or "").strip() or None,
        "owner": str(body.get("owner") or "").strip() or (targets[0] if targets else None),
    }
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK:
        with MESSAGE_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        if sender_id in AGENT_IDS:
            agent_state = STATE.setdefault("agents", {}).setdefault(sender_id, {})
            agent_state["last_seen"] = record["ts"]
            agent_state["is_typing"] = False
            agent_state["typing_since"] = None
            save_state()
    return record


def read_records(since: str | None, limit: int) -> list[dict[str, Any]]:
    if not MESSAGE_PATH.exists():
        return []
    rows: list[dict[str, Any]] = []
    with MESSAGE_PATH.open(encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if since and str(rec.get("ts", "")) <= since:
                continue
            rows.append(rec)
    return rows[:limit] if since else rows[-limit:]


def status_snapshot() -> dict[str, Any]:
    now = time.time()
    agents: dict[str, Any] = {}
    for agent_id in AGENT_IDS:
        stored = STATE.setdefault("agents", {}).get(agent_id, {})
        last_seen = stored.get("last_seen")
        seen_time = 0.0
        if last_seen:
            try:
                seen_time = datetime.fromisoformat(last_seen).timestamp()
            except Exception:
                seen_time = 0.0
        agents[agent_id] = {
            "state": "online" if last_seen and now - seen_time <= OFFLINE_AFTER_SECONDS else "offline",
            "last_seen": last_seen,
            "is_typing": bool(stored.get("is_typing")),
            "typing_since": stored.get("typing_since"),
            "dispatch_id": stored.get("dispatch_id"),
            "status_text": stored.get("status_text"),
        }
    return {"agents": agents}


def members_payload() -> list[dict[str, Any]]:
    status = status_snapshot()["agents"]
    members: list[dict[str, Any]] = []
    for member in ROSTER:
        agent_status = status.get(str(member.get("id")), {})
        item = dict(member)
        item["name"] = item.get("display_name") or item.get("id")
        item["online"] = agent_status.get("state") == "online"
        item["typing"] = bool(agent_status.get("is_typing"))
        members.append(item)
    return members


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True}


@app.get("/group/roster")
def group_roster() -> dict[str, Any]:
    return {"ok": True, "roster": ROSTER, "members": members_payload(), "status": status_snapshot()}


@app.get("/group/poll")
def group_poll(since: str | None = None, limit: int = 120) -> dict[str, Any]:
    limit = min(max(int(limit or 120), 1), 500)
    records = read_records(since, limit)
    return {
        "ok": True,
        "records": records,
        "count": len(records),
        "last_ts": records[-1]["ts"] if records else since,
        "roster": ROSTER,
        "members": members_payload(),
        "status": status_snapshot(),
    }


@app.post("/group/send")
async def group_send(request: Request) -> JSONResponse:
    body = await request.json()
    try:
        text = str(body.get("text") or "")
        mentions = normalize_mentions(body.get("mentions"), text)
        targets = targets_for(str(body.get("sender_id") or "user").strip(), mentions)
        record = append_record(body, mentions, targets)
    except ValueError as exc:
        return json_response(400, {"ok": False, "error": str(exc)})
    return json_response(200, {"ok": True, "record": record, "targets": targets})


@app.post("/group/typing")
async def group_typing(request: Request) -> dict[str, Any]:
    body = await request.json()
    agent_id = str(body.get("sender_id") or body.get("agent_id") or "").strip()
    if agent_id not in AGENT_IDS:
        return {"ok": False, "error": "unknown agent_id"}
    state = STATE.setdefault("agents", {}).setdefault(agent_id, {})
    state["is_typing"] = bool(body.get("is_typing", body.get("typing", False)))
    state["typing_since"] = now_iso() if state["is_typing"] else None
    state["dispatch_id"] = body.get("dispatch_id")
    if "status_text" in body:
        state["status_text"] = body.get("status_text") or None
    state["last_seen"] = now_iso()
    save_state()
    return {"ok": True, "status": status_snapshot()}


@app.post("/group/roster_heartbeat")
async def group_roster_heartbeat(request: Request) -> dict[str, Any]:
    body = await request.json()
    agent_id = str(body.get("sender_id") or body.get("agent_id") or "").strip()
    if agent_id not in AGENT_IDS:
        return {"ok": False, "error": "unknown agent_id"}
    state = STATE.setdefault("agents", {}).setdefault(agent_id, {})
    state["last_seen"] = now_iso()
    state["is_typing"] = bool(body.get("is_typing", state.get("is_typing", False)))
    if "status_text" in body:
        state["status_text"] = body.get("status_text") or None
    save_state()
    return {"ok": True, "status": status_snapshot()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8795")))
    args = parser.parse_args()
    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
