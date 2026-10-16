#!/usr/bin/env python3
"""Ship CloudFront access logs (standard logging v2, JSON) to Loki as site traffic.

Runs on the operator host from a systemd timer. Each run:
  1. mirrors the log bucket's cloudfront/ prefix to RAW_DIR with `aws s3 sync`,
     as the read-only reader role (AWS_PROFILE);
  2. reads every .gz file it has not shipped yet, one JSON object per line;
  3. pushes one Loki line per request to the stream {job="site-traffic", site, agent}.

What a Loki line holds: host, path, status, method, kind (page, asset, redirect,
error), agent (human or bot), the bot's name, country, referrer host, CloudFront
result type, bytes and time to first byte. The logs carry no IP address (the
distribution does not record one), and this job keeps no User-Agent string and
no full referrer URL either: only the class, the bot name and the referrer host.

Idempotent: a file is marked shipped only after Loki accepted all of its lines,
and Loki drops exact duplicates, so a failed run is repeated safely by the next.
Standard library only; needs the AWS CLI on PATH.
"""
import datetime
import gzip
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

LOG_BUCKET = os.environ["LOG_BUCKET"]
LOG_PREFIX = os.environ.get("LOG_PREFIX", "cloudfront")
LOKI_URL = os.environ.get("LOKI_URL", "http://localhost:3100")
STATE_DIR = pathlib.Path(os.environ.get("STATE_DIR", "~/.local/state/site-traffic")).expanduser()
RAW_DIR = STATE_DIR / "raw"
STATE_FILE = STATE_DIR / "shipped.json"
KEEP_RAW_DAYS = int(os.environ.get("KEEP_RAW_DAYS", "32"))  # S3 keeps 30 days; older local copies go
MAX_AGE = 6 * 86400  # Loki rejects samples older than 7 days
BATCH = 2000

NAMED_BOTS = [
    # AI crawlers and assistants first: the AIEO question is which of them read the site.
    "GPTBot", "OAI-SearchBot", "ChatGPT-User", "ClaudeBot", "Claude-User", "Claude-SearchBot",
    "anthropic-ai", "PerplexityBot", "Perplexity-User", "Google-Extended", "Applebot-Extended",
    "Bytespider", "CCBot", "Amazonbot", "meta-externalagent", "meta-externalfetcher",
    "MistralAI-User", "cohere-ai", "DuckAssistBot", "YouBot", "Diffbot",
    # Search engines and link previews.
    "Googlebot", "bingbot", "Applebot", "DuckDuckBot", "YandexBot", "Baiduspider", "SeznamBot",
    "facebookexternalhit", "LinkedInBot", "Twitterbot", "Slackbot", "Discordbot", "TelegramBot",
    "WhatsApp", "redditbot", "Mastodon",
    # SEO tools and our own checks.
    "AhrefsBot", "SemrushBot", "MJ12bot", "DotBot", "site-infra-parity",
]
NAMED = [(name, name.lower()) for name in NAMED_BOTS]
GENERIC_BOT = re.compile(
    r"bot\b|bot/|crawl|spider|slurp|scan|monitor|preview|headless|lighthouse|uptime|"
    r"python|curl/|wget/|httpx|go-http|java/|okhttp|axios|node-fetch|libwww|feed|archiver",
    re.I,
)


def classify_agent(user_agent):
    ua = urllib.parse.unquote(user_agent or "")
    if ua in ("", "-"):
        return "bot", "no-user-agent"
    low = ua.lower()
    for name, token in NAMED:
        if token in low:
            return "bot", name
    if GENERIC_BOT.search(ua):
        return "bot", "other"
    return "human", ""


def referrer_host(referrer, site_hosts):
    if referrer in ("", "-"):
        return "direct"
    host = (urllib.parse.urlsplit(urllib.parse.unquote(referrer)).hostname or "").lower()
    if not host:
        return "direct"
    if host in site_hosts:
        return "internal"
    return host[4:] if host.startswith("www.") else host


def kind_of(status, content_type):
    if 300 <= status < 400:
        return "redirect"
    if status >= 400:
        return "error"
    if (content_type or "").startswith("text/html"):
        return "page"
    return "asset"


def normalise_path(path):
    path = urllib.parse.unquote(path or "/")
    if path.endswith("/index.html"):
        path = path[: -len("index.html")]
    return path


def to_line(record, site):
    host = (record.get("x-host-header") or site).lower()
    status = int(record.get("sc-status") or 0)
    agent, bot = classify_agent(record.get("cs(User-Agent)"))
    ttfb = record.get("time-to-first-byte")
    line = {
        "host": host,
        "path": normalise_path(record.get("cs-uri-stem")),
        "status": status,
        "method": record.get("cs-method"),
        "kind": kind_of(status, record.get("sc-content-type")),
        "agent": agent,
        "bot": bot,
        "country": record.get("c-country") if record.get("c-country") not in (None, "", "-") else "unknown",
        "referrer": referrer_host(record.get("cs(Referer)"), {site, "www." + site, "next." + site}),
        "edge": record.get("x-edge-result-type"),
        "bytes": int(record.get("sc-bytes") or 0),
        "ttfb_ms": round(float(ttfb) * 1000) if ttfb not in (None, "", "-") else None,
        "id": (record.get("x-edge-request-id") or "")[:12],
    }
    stamp = datetime.datetime.strptime(f'{record["date"]} {record["time"]}', "%Y-%m-%d %H:%M:%S")
    epoch = stamp.replace(tzinfo=datetime.timezone.utc).timestamp()
    return epoch, agent, json.dumps(line, separators=(",", ":"))


def push(site, agent, values):
    body = json.dumps({"streams": [{"stream": {"job": "site-traffic", "site": site, "agent": agent}, "values": values}]})
    req = urllib.request.Request(f"{LOKI_URL}/loki/api/v1/push", data=body.encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status not in (200, 204):
            raise RuntimeError(f"loki answered {resp.status}")


def ship_file(path, site, now):
    streams, too_old = {}, 0
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            epoch, agent, line = to_line(json.loads(raw), site)
            if now - epoch > MAX_AGE:
                too_old += 1
                continue
            streams.setdefault(agent, []).append([str(int(epoch * 1e9)), line])
    shipped = 0
    for agent, values in streams.items():
        values.sort()
        for i in range(0, len(values), BATCH):
            push(site, agent, values[i : i + BATCH])
        shipped += len(values)
    return shipped, too_old


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["aws", "s3", "sync", f"s3://{LOG_BUCKET}/{LOG_PREFIX}/", str(RAW_DIR), "--only-show-errors"],
        check=True,
    )
    state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
    now = time.time()
    files = lines = dropped = failed = 0
    for path in sorted(RAW_DIR.rglob("*.gz")):
        rel = str(path.relative_to(RAW_DIR))
        if rel in state:
            continue
        site = rel.split("/", 1)[0]  # cloudfront/<site>/<yyyy>/<MM>/<dd>/<HH>/<file>.gz
        try:
            shipped, too_old = ship_file(path, site, now)
        except Exception as exc:  # leave it unmarked; the next run retries
            failed += 1
            print(f"failed {rel}: {exc}", file=sys.stderr)
            continue
        state[rel] = int(now)
        files, lines, dropped = files + 1, lines + shipped, dropped + too_old
    # Forget local copies that S3 has expired too, and their state entries.
    for path in RAW_DIR.rglob("*.gz"):
        if now - path.stat().st_mtime > KEEP_RAW_DAYS * 86400:
            path.unlink()
    state = {rel: t for rel, t in state.items() if (RAW_DIR / rel).exists()}
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, sort_keys=True))
    tmp.replace(STATE_FILE)
    print(f"files {files}, lines {lines}, too old {dropped}, failed {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
