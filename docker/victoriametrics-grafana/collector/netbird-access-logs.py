#!/usr/bin/env python3
"""Read-only NetBird access-log API -> VictoriaLogs NDJSON, using durable SQLite state.

No third-party Python dependencies. This collector is at-least-once, not exactly-once:
a lost response after an accepted insert can rarely produce duplicate VictoriaLogs entries.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import logging
import os
import re
import signal
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

LOG = logging.getLogger("netbird-accesslog")
UTC = dt.timezone.utc
STOP = False

BLOCK_REASONS = {
    "path_block", "ip_restricted", "country_restricted", "geo_unavailable",
    "crowdsec_ban", "crowdsec_captcha", "crowdsec_throttle", "crowdsec_unavailable",
}
SENSITIVE_SEGMENT_KEYS = {
    "token", "tokens", "secret", "secrets", "apikey", "api-key", "api_key",
    "key", "keys", "password", "passwd", "pwd", "authorization",
    "auth", "bearer", "session", "sessions", "callback", "code",
    "reset", "activate", "invitation", "invite", "invitations",
}
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
LONG_TOKEN_RE = re.compile(r"^[A-Za-z0-9_=-]{20,}$")
JWT_RE = re.compile(r"^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$")
EMAIL_RE = re.compile(r"^[^/@\s]+@[^/@\s]+\.[^/@\s]+$")
SAFE_NAME = re.compile(r"^[a-zA-Z0-9_.:@-]{1,253}$")


def utcnow() -> dt.datetime:
    return dt.datetime.now(UTC)


def parse_time(value: str) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ValueError("missing timestamp")
    v = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if v.tzinfo is None:
        raise ValueError("timestamp lacks time zone")
    return v.astimezone(UTC)


def rfc3339(value: dt.datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


def safe_text(value, length=253) -> str:
    text = str(value or "").strip()
    if len(text) > length or not SAFE_NAME.fullmatch(text):
        return ""
    return text


def int_nonneg(value) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError, OverflowError):
        return 0


def sanitize_path(raw_path: object) -> tuple[str, str]:
    """Return normalized path and a best-effort sanitized path.

    The latter is opt-in and NOT a guarantee against secrets embedded in paths.
    Queries and fragments are always discarded. Sensitive identifiers are redacted.
    """
    raw = str(raw_path or "/")[:4096]
    # Accept both relative request-targets and accidental absolute-form URLs.
    raw = urllib.parse.urlsplit(raw).path or "/"
    for _ in range(2):
        updated = urllib.parse.unquote(raw, errors="replace")
        if updated == raw:
            break
        raw = updated
    # Avoid control characters, path traversal and misleading encoded separators.
    if any(ord(c) < 32 for c in raw) or "\\" in raw or not raw.startswith("/"):
        return "/{redacted}", "/{redacted}"
    parts = raw.split("/")
    filtered = []
    normalized = []
    hide_next = False
    for part in parts:
        if not part:
            filtered.append("")
            normalized.append("")
            continue
        lower = part.lower()
        if hide_next or lower in (".", ".."):
            clean = "{redacted}"
            norm = "{redacted}"
        elif lower in SENSITIVE_SEGMENT_KEYS:
            clean = lower
            norm = lower
        elif JWT_RE.fullmatch(part) or UUID_RE.fullmatch(part) or LONG_TOKEN_RE.fullmatch(part) or EMAIL_RE.fullmatch(part):
            clean = "{redacted}"
            norm = "{id}"
        elif re.fullmatch(r"\d+", part):
            clean = part
            norm = "{id}"
        elif len(part) > 80 or any(c in part for c in "?&#=:@\"'<> "):
            clean = "{redacted}"
            norm = "{id}"
        else:
            clean = part
            norm = part
        filtered.append(clean)
        normalized.append(norm)
        hide_next = lower in SENSITIVE_SEGMENT_KEYS
    return "/".join(normalized)[:512] or "/", "/".join(filtered)[:1024] or "/"


def normalize_event(event: dict, *, include_sanitized_path: bool = False) -> dict:
    """Explicit allowlist prevents unexpected fields and metadata from leaking."""
    event_id = str(event.get("id") or "")
    if not event_id or len(event_id) > 256 or not re.fullmatch(r"[\w.:-]+", event_id):
        raise ValueError("missing or invalid event id")
    timestamp = rfc3339(parse_time(event.get("timestamp")))
    protocol = safe_text(event.get("protocol") or "unknown", 24).lower() or "unknown"
    method = safe_text(event.get("method"), 30).upper()
    auth = safe_text(event.get("auth_method_used"), 60).lower()
    status = int_nonneg(event.get("status_code"))
    normalized, sanitized = sanitize_path(event.get("path"))
    if auth in BLOCK_REASONS:
        outcome = "blocked"
    elif 200 <= status < 300:
        outcome = "success"
    elif 300 <= status < 400:
        outcome = "redirect"
    elif 400 <= status < 500:
        outcome = "client_error"
    elif status >= 500:
        outcome = "server_error"
    else:
        outcome = "other"
    ip = str(event.get("source_ip") or "")
    try:
        ip = str(ipaddress.ip_address(ip))
    except ValueError:
        ip = ""
    country = safe_text(event.get("country_code"), 2).upper()
    if not re.fullmatch(r"[A-Z]{2}", country):
        country = ""
    metadata = event.get("metadata") if isinstance(event.get("metadata"), dict) else {}
    record = {
        "timestamp": timestamp,
        "source": "netbird_reverse_proxy",
        "event_id": event_id,
        "service_id": safe_text(event.get("service_id"), 128),
        "protocol": protocol,
        "host": safe_text(event.get("host"), 253).lower(),
        "method": method,
        "status_code": status,
        "status_class": f"{status // 100}xx" if 100 <= status <= 599 else "",
        "outcome": outcome,
        "duration_ms": int_nonneg(event.get("duration_ms")),
        "bytes_upload": int_nonneg(event.get("bytes_upload")),
        "bytes_download": int_nonneg(event.get("bytes_download")),
        "source_ip": ip,
        "country_code": country,
        "city_name": str(event.get("city_name") or "")[:128],
        "subdivision_code": safe_text(event.get("subdivision_code"), 32),
        "auth_method_used": auth,
        "crowdsec_verdict": safe_text(metadata.get("crowdsec_verdict"), 60),
        "crowdsec_mode": safe_text(metadata.get("crowdsec_mode"), 60),
        "access_action": safe_text(metadata.get("access_action"), 60),
        "path_pattern": normalized,
        "message": f"{protocol.upper()} {method} {status or '-'} {outcome}".strip(),
    }
    # Raw URL paths are not ingested by default. This best-effort sanitizer is
    # opt-in only; use a deployment-specific allowlist before enabling.
    if include_sanitized_path:
        record["path_sanitized"] = sanitized
    return record


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise RuntimeError("Unexpected HTTP redirect; refusing credential forwarding")


HTTP_OPENER = urllib.request.build_opener(NoRedirect())


def http_json(url: str, *, token: str, timeout: int = 25) -> dict:
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "Authorization": "Token " + token},
        method="GET",
    )
    with HTTP_OPENER.open(req, timeout=timeout) as r:
        raw = r.read(10_000_001)
        if len(raw) > 10_000_000:
            raise RuntimeError("API page exceeds 10 MB safety limit")
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise RuntimeError("Unexpected API response structure")
        return data


def fetch_pages(base_url: str, token: str, start: dt.datetime, end: dt.datetime,
                *, page_cap: int = 1000):
    endpoint = base_url.rstrip("/") + "/api/events/proxy"
    for page in range(1, page_cap + 1):
        qs = urllib.parse.urlencode({
            "page": page, "page_size": 100,
            "sort_by": "timestamp", "sort_order": "asc",
            "start_date": rfc3339(start), "end_date": rfc3339(end),
        })
        body = http_json(endpoint + "?" + qs, token=token)
        data = body.get("data")
        if not isinstance(data, list):
            raise RuntimeError("API data is not a list")
        for item in data:
            if not isinstance(item, dict):
                raise RuntimeError("Unexpected event item")
            yield item
        # Use page-size as stop condition; a small extra page is okay.
        if len(data) < 100:
            return
    raise RuntimeError("Pagination cap exceeded: refusing incomplete checkpoint")


class Store:
    def __init__(self, path: str):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, timeout=30)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA busy_timeout=30000")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS events (
            event_id TEXT PRIMARY KEY,
            event_ts TEXT NOT NULL,
            payload TEXT,
            delivered INTEGER NOT NULL DEFAULT 0,
            first_seen REAL NOT NULL
          );
          CREATE INDEX IF NOT EXISTS idx_events_delivered ON events(delivered, first_seen);
          CREATE TABLE IF NOT EXISTS settings (k TEXT PRIMARY KEY, v TEXT NOT NULL);
        """)
        self.db.commit()

    def setting(self, key: str):
        row = self.db.execute("SELECT v FROM settings WHERE k=?", (key,)).fetchone()
        return row[0] if row else None

    def set_setting(self, key: str, value: str):
        with self.db:
            self.db.execute("INSERT INTO settings(k,v) VALUES (?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (key, value))

    def enqueue(self, record: dict) -> bool:
        with self.db:
            result = self.db.execute(
                "INSERT OR IGNORE INTO events(event_id,event_ts,payload,first_seen) VALUES(?,?,?,?)",
                (record["event_id"], record["timestamp"], json.dumps(record, separators=(",", ":")), time.time()),
            )
        return result.rowcount == 1

    def pending(self, max_count: int = 100) -> list[tuple[str, str]]:
        return self.db.execute(
            "SELECT event_id,payload FROM events WHERE delivered=0 ORDER BY first_seen,event_id LIMIT ?",
            (max_count,),
        ).fetchall()

    def acknowledge(self, ids: list[str]):
        with self.db:
            self.db.executemany("UPDATE events SET delivered=1,payload=NULL WHERE event_id=?", [(x,) for x in ids])

    def count_pending(self) -> int:
        return self.db.execute("SELECT count(*) FROM events WHERE delivered=0").fetchone()[0]

    def prune(self, now: dt.datetime, seen_days: int = 5):
        cutoff = now.timestamp() - 86400 * seen_days
        with self.db:
            self.db.execute("DELETE FROM events WHERE delivered=1 AND first_seen < ?", (cutoff,))

    def close(self):
        self.db.close()


def post_batch(url: str, batch: list[tuple[str, str]], timeout: int = 25):
    query = urllib.parse.urlencode({"_stream_fields": "source,protocol", "_time_field": "timestamp", "_msg_field": "message"})
    dst = url.rstrip("/") + "/insert/jsonline?" + query
    data = ("\n".join(payload for _, payload in batch) + "\n").encode("utf-8")
    req = urllib.request.Request(
        dst, data=data, headers={"Content-Type": "application/stream+json"}, method="POST"
    )
    with HTTP_OPENER.open(req, timeout=timeout) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"VictoriaLogs returned HTTP {response.status}")
        response.read(4096)


def drain(store: Store, vlogs_url: str) -> int:
    count = 0
    while True:
        batch = store.pending(100)
        if not batch:
            return count
        post_batch(vlogs_url, batch)
        store.acknowledge([event_id for event_id, _ in batch])
        count += len(batch)


def collect_once(store: Store, cfg: dict) -> tuple[int, int]:
    now = utcnow()
    end = now - dt.timedelta(seconds=cfg["settle_seconds"])
    oldest = now - dt.timedelta(hours=cfg["backfill_hours"])
    checkpoint = store.setting("last_completed_end")
    start = oldest
    if checkpoint:
        checkpoint_time = parse_time(checkpoint)
        if checkpoint_time < oldest:
            LOG.warning("Checkpoint older than backfill window; source events may have expired")
        start = max(oldest, checkpoint_time - dt.timedelta(minutes=cfg["overlap_minutes"]))
    if start >= end:
        return 0, drain(store, cfg["victorialogs_url"])

    discovered = 0
    fetched = 0
    # Drain any previously staged events first. A previous insert failure must
    # not be quietly bypassed by advancing a checkpoint.
    drain(store, cfg["victorialogs_url"])
    for event in fetch_pages(cfg["netbird_url"], cfg["api_token"], start, end,
                             page_cap=cfg["page_cap"]):
        fetched += 1
        record = normalize_event(event, include_sanitized_path=cfg["include_sanitized_path"])
        if store.enqueue(record):
            discovered += 1
        if fetched % 100 == 0:
            drain(store, cfg["victorialogs_url"])
    # Only checkpoint once every page was read and deliveries were acknowledged.
    drain(store, cfg["victorialogs_url"])
    store.set_setting("last_completed_end", rfc3339(end))
    store.prune(now)
    LOG.info("collection_ok fetched=%s newly_ingested=%s pending=%s end=%s",
             fetched, discovered, store.count_pending(), rfc3339(end))
    return discovered, fetched


def parse_config():
    parser = argparse.ArgumentParser(description="NetBird reverse proxy access-log collector")
    parser.add_argument("--once", action="store_true", help="Collect once, then exit")
    args = parser.parse_args()
    token = os.environ.get("NETBIRD_API_TOKEN", "")
    base = os.environ.get("NETBIRD_MANAGEMENT_URL", "").rstrip("/")
    vlogs = os.environ.get("VICTORIALOGS_URL", "http://victorialogs:9428").rstrip("/")
    if not token or not base:
        parser.error("NETBIRD_API_TOKEN and NETBIRD_MANAGEMENT_URL are required")
    if urllib.parse.urlsplit(base).scheme != "https":
        parser.error("NETBIRD_MANAGEMENT_URL must use HTTPS")
    if urllib.parse.urlsplit(vlogs).scheme != "http":
        parser.error("VICTORIALOGS_URL must use HTTP on isolated Docker backend network")
    cfg = {
        "api_token": token, "netbird_url": base, "victorialogs_url": vlogs,
        "state_db": os.environ.get("STATE_DB", "/state/collector.sqlite"),
        "poll_seconds": max(15, int(os.environ.get("POLL_SECONDS", "60"))),
        "settle_seconds": max(30, int(os.environ.get("SETTLE_SECONDS", "120"))),
        "backfill_hours": min(72, max(1, int(os.environ.get("BACKFILL_HOURS", "70")))),
        "overlap_minutes": max(10, int(os.environ.get("OVERLAP_MINUTES", "120"))),
        "page_cap": max(1, int(os.environ.get("MAX_PAGES", "1000"))),
        "include_sanitized_path": os.environ.get("INCLUDE_SANITIZED_PATH", "false").lower() == "true",
    }
    return args, cfg


def stop_handler(_signum, _frame):
    global STOP
    STOP = True


def main():
    logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO)
    args, cfg = parse_config()
    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)
    os.umask(0o077)
    store = Store(cfg["state_db"])
    try:
        while not STOP:
            try:
                collect_once(store, cfg)
            except (OSError, ValueError, RuntimeError, urllib.error.HTTPError, json.JSONDecodeError) as exc:
                # Do not print API request headers, tokens, source events, or payloads.
                LOG.error("collection_failed type=%s pending=%s", type(exc).__name__, store.count_pending())
                if args.once:
                    return 1
            if args.once:
                return 0
            for _ in range(cfg["poll_seconds"]):
                if STOP:
                    break
                time.sleep(1)
    finally:
        store.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
