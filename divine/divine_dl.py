#!/usr/bin/env python3
"""Download videos + metadata from divine.video feeds (e.g. /discovery/classics).

The divine.video web app is a SPA; its feeds come from the public "funnelcake"
REST API at api.divine.video. Videos are content-addressed blobs on
media.divine.video (URL path == sha256), so every download is hash-verified.

Output layout (flat, one trio per video):
    <out>/<key>.mp4    video
    <out>/<key>.jpg    thumbnail (unless --no-thumbnails)
    <out>/<key>.json   normalized metadata + raw API record
    <out>/manifest.jsonl  one normalized record per downloaded video

Stdlib only; no install required.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

API_BASE = "https://api.divine.video"
VIDEOS_ENDPOINT = "/api/v2/videos"
USER_AGENT = "divine-dl/0.1 (+personal archiving)"

# Query params mirror what the web app sends for each feed tab.
FEEDS: dict[str, dict[str, str]] = {
    "classics": {"classic": "true", "platform": "vine", "sort": "loops"},
    "trending": {"sort": "watching"},
    "recent": {"sort": "recent"},
}

PAGE_SIZE = 50  # API accepts up to 100; the web app uses ~24-50
SAFE_KEY = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


# --------------------------------------------------------------------------- HTTP

def http_get(url: str, *, retries: int = 4, timeout: int = 30) -> bytes:
    """GET with exponential backoff on 429/5xx/network errors."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "identity"})
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or attempt == retries:
                raise
            wait = float(e.headers.get("Retry-After") or 2 ** attempt)
        except (urllib.error.URLError, TimeoutError):
            if attempt == retries:
                raise
            wait = 2 ** attempt
        time.sleep(wait)
    raise RuntimeError("unreachable")


def fetch_page(feed: str, cursor: str | None, limit: int) -> tuple[list[dict], str | None]:
    params = {**FEEDS[feed], "limit": str(limit)}
    if cursor:
        params["cursor"] = cursor
    url = f"{API_BASE}{VIDEOS_ENDPOINT}?{urllib.parse.urlencode(params)}"
    body = json.loads(http_get(url))
    pagination = body.get("pagination") or {}
    next_cursor = pagination.get("next_cursor") if pagination.get("has_more") else None
    return body.get("data") or [], next_cursor


def iter_feed(feed: str, max_videos: int, start_cursor: str | None, page_delay: float):
    """Yield (video, cursor_of_its_page) until max_videos or the feed ends."""
    cursor, seen, yielded = start_cursor, set(), 0
    while yielded < max_videos:
        videos, next_cursor = fetch_page(feed, cursor, min(PAGE_SIZE, max_videos - yielded))
        for v in videos:
            if v["id"] in seen:
                continue
            seen.add(v["id"])
            yield v, next_cursor
            yielded += 1
            if yielded >= max_videos:
                return
        if not next_cursor or not videos:
            return
        cursor = next_cursor
        time.sleep(page_delay)


# ----------------------------------------------------------------------- Metadata

def _tags(video: dict) -> dict[str, list[list[str]]]:
    out: dict[str, list[list[str]]] = {}
    for t in video.get("tags") or []:
        if t:
            out.setdefault(t[0], []).append(t[1:])
    return out


def _imeta(tags: dict) -> dict[str, str]:
    """Parse the NIP-92 imeta tag ("key value" strings) into a dict."""
    out = {}
    for entry in (tags.get("imeta") or [[]])[0]:
        k, _, v = entry.partition(" ")
        out[k] = v
    return out


def _tag1(tags: dict, name: str) -> str | None:
    vals = tags.get(name)
    return vals[0][0] if vals and vals[0] else None


def _int(x) -> int | None:
    try:
        return int(x)
    except (TypeError, ValueError):
        return None


def _iso(ts) -> str | None:
    ts = _int(ts)
    return datetime.fromtimestamp(ts, timezone.utc).isoformat() if ts else None


def normalize(video: dict) -> dict:
    """Flatten an API record into the fields a downstream app actually needs."""
    tags = _tags(video)
    imeta = _imeta(tags)
    published = video.get("published_at") or video.get("created_at")
    return {
        "id": video["id"],  # nostr event id
        "kind": video.get("kind"),
        "d_tag": video.get("d_tag"),
        "pubkey": video.get("pubkey"),
        "platform": video.get("platform") or _tag1(tags, "platform"),
        "vine_id": _tag1(tags, "vine_id"),
        "title": video.get("title") or _tag1(tags, "title"),
        "description": _tag1(tags, "summary"),
        "author_name": video.get("author_name") or _tag1(tags, "author"),
        "author_avatar": video.get("author_avatar") or None,
        "hashtags": [t[0] for t in tags.get("t", []) if t],
        "published_at": _iso(published),
        "published_at_unix": _int(published),
        "duration_s": _int(imeta.get("duration")) or video.get("duration") or None,
        "dimensions": video.get("dimensions") or imeta.get("dim"),
        "mime_type": video.get("mime_type") or imeta.get("m") or "video/mp4",
        "sha256": video.get("sha256") or imeta.get("x"),
        "video_url": video.get("video_url") or imeta.get("url"),
        "thumbnail_url": video.get("thumbnail") or imeta.get("image"),
        "original_url": _tag1(tags, "r"),
        "divine_url": f"https://divine.video/video/{video['id']}",
        # Original Vine-era stats (from the archive import tags)
        "original_stats": {
            "loops": _int(_tag1(tags, "loops")),
            "likes": _int(_tag1(tags, "likes")) or video.get("embedded_likes"),
            "comments": _int(_tag1(tags, "comments")) or video.get("embedded_comments"),
            "reposts": _int(_tag1(tags, "reposts")) or video.get("embedded_reposts"),
        },
        # Live stats on divine.video
        "divine_stats": {
            "loops": video.get("loops"),
            "views": video.get("views"),
            "reactions": video.get("reactions"),
            "comments": video.get("comments"),
            "reposts": video.get("reposts"),
        },
        "content_labels": video.get("content_labels") or [],
        "moderation_labels": video.get("moderation_labels") or [],
    }


# ---------------------------------------------------------------------- Download

def file_key(meta: dict) -> str:
    for candidate in (meta.get("vine_id"), meta.get("d_tag")):
        if candidate and SAFE_KEY.match(candidate):
            return candidate
    return meta["id"][:16]


def download_file(url: str, dest: Path, expected_sha256: str | None = None) -> int:
    """Stream to a .part file, verify sha256 if given, then atomically rename."""
    tmp = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(4):
        try:
            size = 0
            with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as f:
                while chunk := resp.read(1 << 16):
                    f.write(chunk)
                    h.update(chunk)
                    size += len(chunk)
            break
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            h = hashlib.sha256()
            if attempt == 3:
                tmp.unlink(missing_ok=True)
                raise
            time.sleep(2 ** attempt)
    if expected_sha256 and h.hexdigest() != expected_sha256.lower():
        tmp.unlink(missing_ok=True)
        raise ValueError(f"sha256 mismatch for {url}")
    os.replace(tmp, dest)
    return size


def process(video: dict, out: Path, thumbnails: bool) -> tuple[str, dict, str]:
    """Download one video. Returns (status, meta, key)."""
    meta = normalize(video)
    key = file_key(meta)
    mp4, jpg, js = out / f"{key}.mp4", out / f"{key}.jpg", out / f"{key}.json"

    if not meta["video_url"]:
        return "no-url", meta, key
    if mp4.exists() and js.exists():
        return "skipped", meta, key

    download_file(meta["video_url"], mp4, meta["sha256"])
    meta["file_size"] = mp4.stat().st_size
    meta["files"] = {"video": mp4.name}

    if thumbnails and meta["thumbnail_url"]:
        try:
            download_file(meta["thumbnail_url"], jpg)
            meta["files"]["thumbnail"] = jpg.name
        except Exception as e:  # thumbnail failure shouldn't sink the video
            print(f"  ! thumbnail failed for {key}: {e}", file=sys.stderr)

    meta["downloaded_at"] = datetime.now(timezone.utc).isoformat()
    js.write_text(json.dumps({"meta": meta, "raw": video}, ensure_ascii=False, indent=2))
    return "ok", meta, key


# ---------------------------------------------------------------------------- CLI

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-f", "--feed", choices=sorted(FEEDS), default="classics", help="feed to scrape (default: classics)")
    ap.add_argument("-n", "--limit", type=int, default=50, help="max videos to process (default: 50)")
    ap.add_argument("-o", "--out", type=Path, default=Path("downloads"), help="output dir (default: ./downloads/<feed>)")
    ap.add_argument("-w", "--workers", type=int, default=4, help="parallel downloads (default: 4)")
    ap.add_argument("--cursor", help="resume from a pagination cursor (e.g. o:500); printed at the end of each run")
    ap.add_argument("--page-delay", type=float, default=0.5, help="seconds between API page requests")
    ap.add_argument("--no-thumbnails", action="store_true", help="skip thumbnail downloads")
    ap.add_argument("--metadata-only", action="store_true", help="write metadata JSONL only, no media")
    args = ap.parse_args()

    out = args.out / args.feed
    out.mkdir(parents=True, exist_ok=True)
    manifest = out / "manifest.jsonl"
    print(f"Feed: {args.feed}  ->  {out.resolve()}")

    counts = {"ok": 0, "skipped": 0, "no-url": 0, "failed": 0}
    last_cursor = args.cursor
    feed = iter_feed(args.feed, args.limit, args.cursor, args.page_delay)

    if args.metadata_only:
        with open(manifest, "a", encoding="utf-8") as mf:
            for video, last_cursor in feed:
                mf.write(json.dumps(normalize(video), ensure_ascii=False) + "\n")
                counts["ok"] += 1
    else:
        with ThreadPoolExecutor(max_workers=args.workers) as pool, open(manifest, "a", encoding="utf-8") as mf:
            futures = {}
            for video, last_cursor in feed:
                futures[pool.submit(process, video, out, not args.no_thumbnails)] = video["id"]
            for i, fut in enumerate(as_completed(futures), 1):
                try:
                    status, meta, key = fut.result()
                except Exception as e:
                    counts["failed"] += 1
                    print(f"[{i}/{len(futures)}] FAILED {futures[fut][:12]}: {e}", file=sys.stderr)
                    continue
                counts[status] += 1
                if status == "ok":
                    mf.write(json.dumps(meta, ensure_ascii=False) + "\n")
                    mf.flush()
                title = (meta["title"] or "").replace("\n", " ")[:60]
                print(f"[{i}/{len(futures)}] {status:7} {key}  {meta['author_name']}: {title}")

    print("\nDone:", ", ".join(f"{k}={v}" for k, v in counts.items()))
    if last_cursor:
        print(f"Next page cursor: {last_cursor}   (resume with --cursor {last_cursor})")
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
