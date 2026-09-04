#!/usr/bin/env python3
"""Seed scraper for Odoo Experience 2026.

Pulls the public website (talk list, talk pages, exhibitors, tags) into
SQLite + JSON that a future companion app can load as-is.

Re-run whenever the official agenda changes:

    python3 scripts/scrape_oxp.py
"""

from __future__ import annotations

import argparse
import hashlib
import html as html_lib
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from bs4 import BeautifulSoup, Tag

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
CACHE_DIR = ROOT / ".cache"
BASE = "https://www.odoo.com"
TAGS_RPC_URL = f"{BASE}/event/track_tag/search_read"
DEFAULT_EVENT_ID = 9099

# Separate Odoo events — never merge talks across editions.
EVENTS: list[dict[str, Any]] = [
    {
        "code": "us",
        "id": 10327,
        "slug": "odoo-experience-2026-americas-10327",
        "short_name": "Americas",
        "name": "Odoo Experience Americas 2026",
        "timezone": "America/Los_Angeles",
        "venue_name": "Pier 27",
        "venue_address": "The Embarcadero, San Francisco, CA",
        "country_code": "US",
        "has_map": False,
    },
    {
        "code": "mx",
        "id": 9992,
        "slug": "odoo-experience-2026-latam-9992",
        "short_name": "LATAM",
        "name": "Odoo Experience LATAM 2026",
        "timezone": "America/Mexico_City",
        "venue_name": "Centro Banamex",
        "venue_address": "Mexico City, Mexico",
        "country_code": "MX",
        "has_map": False,
    },
    {
        "code": "ke",
        "id": 9277,
        "slug": "odoo-experience-2026-africa-9277",
        "short_name": "Africa",
        "name": "Odoo Experience Africa 2026",
        "timezone": "Africa/Nairobi",
        "venue_name": "Ngong Racecourse",
        "venue_address": "Waterfront 1 & 2, Nairobi, Kenya",
        "country_code": "KE",
        "has_map": False,
    },
    {
        "code": "in",
        "id": 10174,
        "slug": "odoo-experience-2026-india-10174",
        "short_name": "India",
        "name": "Odoo Experience India 2026",
        "timezone": "Asia/Kolkata",
        "venue_name": "Mahatma Mandir Convention Center",
        "venue_address": "Gandhinagar, India",
        "country_code": "IN",
        "has_map": False,
    },
    {
        "code": "be",
        "id": 9099,
        "slug": "odoo-experience-2026-9099",
        "short_name": "Belgium",
        "name": "Odoo Experience 2026",
        "timezone": "Europe/Brussels",
        "venue_name": "Brussels Expo",
        "venue_address": "Avenue de Miramar 11, 1020 Brussels, Belgium",
        "country_code": "BE",
        "has_map": True,
    },
]

USER_AGENT = (
    "OXP-seed/1.0 (unofficial Odoo Experience companion seed; "
    "+https://github.com/jonathanbertholet)"
)
HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
}

DURATION_RE = re.compile(
    r"(?:(\d+)\s*hr)?\s*(?:(\d+)\s*min)?", re.IGNORECASE
)
TAG_ID_RE = re.compile(r"tags=(?:%5B|\[)(\d+)(?:%5D|\])", re.IGNORECASE)
TRACK_HREF_ID_RE = re.compile(r"/track/[^/?#]*-(\d+)(?:/|$|\?)")
SPONSOR_IMAGE_RE = re.compile(
    r"url\((['\"]?)(https?://[^)'\"]+/web/image/event\.sponsor/(\d+)/[^)'\"]+)\1\)"
)


def log(msg: str) -> None:
    print(msg, flush=True)


def soupify(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "lxml")


def text(el: Tag | None) -> str:
    if el is None:
        return ""
    return re.sub(r"\s+", " ", el.get_text(" ", strip=True)).strip()


def inner_html(el: Tag | None) -> str:
    if el is None:
        return ""
    return el.decode_contents().strip()


def html_to_text(el: Tag | None) -> str:
    if el is None:
        return ""
    raw = el.get_text("\n", strip=True)
    return re.sub(r"\n{3,}", "\n\n", raw).strip()


def parse_duration_minutes(label: str) -> int | None:
    if not label:
        return None
    match = DURATION_RE.search(label.replace(".", ""))
    if not match or not any(match.groups()):
        return None
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2) or 0)
    total = hours * 60 + minutes
    return total or None


def parse_wallclock(label: str) -> tuple[int, int] | None:
    """Parse '9:00 AM' / '11:30 AM' / localized '9:00 a. m.' into 24h (hour, minute)."""
    raw = html_lib.unescape(label or "").strip()
    if not raw:
        return None
    raw = raw.replace("\u202f", " ").replace("\xa0", " ")
    raw = re.sub(r"\s+", " ", raw)
    lowered = (
        raw.lower()
        .replace("a. m.", "am")
        .replace("p. m.", "pm")
        .replace("a.m.", "am")
        .replace("p.m.", "pm")
    )
    for candidate in (lowered.upper(), lowered):
        for fmt in ("%I:%M %p", "%I:%M%p", "%H:%M"):
            try:
                parsed = datetime.strptime(candidate, fmt)
                return parsed.hour, parsed.minute
            except ValueError:
                continue
    return None


def local_dt(day: str, hour: int, minute: int, timezone: str) -> datetime:
    tz = ZoneInfo(timezone)
    return datetime(
        int(day[:4]),
        int(day[5:7]),
        int(day[8:10]),
        hour,
        minute,
        tzinfo=tz,
    )


def iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def weekday_name(day: str | None) -> str | None:
    if not day:
        return None
    return date.fromisoformat(day).strftime("%A")


def abs_url(href: str | None) -> str | None:
    if not href:
        return None
    return urllib.parse.urljoin(BASE, href)


def infer_kind(name: str, duration_minutes: int | None, coming_soon: bool) -> str:
    """Coarse type for filters. Derived from the title/duration, not an Odoo field."""
    lower = name.lower()
    if coming_soon:
        return "tba"
    if lower.startswith("masterclass") or lower.startswith("master class"):
        return "masterclass"
    if "keynote" in lower:
        return "keynote"
    if lower.startswith("opening"):
        return "opening"
    if lower.startswith(("lunch", "dinner")) or "open bar" in lower:
        return "break"
    if lower.startswith("concert"):
        return "social"
    if duration_minutes and duration_minutes >= 60:
        return "session"
    return "talk"


class Fetcher:
    def __init__(self, timeout: int = 40, retries: int = 3, cache: bool = True) -> None:
        self.timeout = timeout
        self.retries = retries
        self.cache = cache
        if cache:
            (CACHE_DIR / "tracks").mkdir(parents=True, exist_ok=True)
            (CACHE_DIR / "exhibitors").mkdir(parents=True, exist_ok=True)
            CACHE_DIR.mkdir(parents=True, exist_ok=True)

    def _cache_path(self, key: str) -> Path:
        return CACHE_DIR / key

    def get(self, url: str, cache_key: str | None = None) -> tuple[str, str]:
        """Return (final_url, body)."""
        if self.cache and cache_key:
            path = self._cache_path(cache_key)
            meta = path.with_suffix(path.suffix + ".url")
            if path.exists():
                return (
                    meta.read_text(encoding="utf-8") if meta.exists() else url,
                    path.read_text(encoding="utf-8"),
                )

        last_error: Exception | None = None
        for attempt in range(1, self.retries + 1):
            try:
                req = urllib.request.Request(url, headers=HEADERS)
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    body = resp.read().decode("utf-8", errors="replace")
                    final = resp.geturl()
                if self.cache and cache_key:
                    path = self._cache_path(cache_key)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(body, encoding="utf-8")
                    path.with_suffix(path.suffix + ".url").write_text(
                        final, encoding="utf-8"
                    )
                return final, body
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last_error = exc
                time.sleep(0.6 * attempt)
        raise RuntimeError(f"GET failed for {url}: {last_error}") from last_error

    def post_json(self, url: str, payload: dict[str, Any]) -> Any:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={**HEADERS, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            parsed = json.loads(resp.read().decode("utf-8"))
        if "error" in parsed:
            raise RuntimeError(parsed["error"])
        return parsed.get("result")


def fetch_tags(fetcher: Fetcher) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    result = fetcher.post_json(
        TAGS_RPC_URL,
        {
            "jsonrpc": "2.0",
            "method": "call",
            "id": 1,
            "params": {
                "domain": [],
                "fields": ["id", "name", "category_id", "color"],
            },
        },
    )
    categories: dict[int, dict[str, Any]] = {}
    tags: list[dict[str, Any]] = []
    for row in result:
        cat = row.get("category_id") or [None, None]
        cat_id, cat_name = (cat[0], cat[1]) if isinstance(cat, list) else (None, None)
        if cat_id and cat_id not in categories:
            categories[cat_id] = {"id": cat_id, "name": cat_name}
        tags.append(
            {
                "id": row["id"],
                "name": row["name"],
                "category_id": cat_id,
                "category": cat_name,
                "color": row.get("color"),
            }
        )
    return list(categories.values()), tags


def listing_track_id(item: Tag) -> tuple[int | None, str | None]:
    """Odoo omits data-track-id when the wishlist button isn’t rendered (LATAM)."""
    reminder = item.select_one("[data-track-id]")
    href = item.get("href") if item.name == "a" else None
    if not href:
        link = item.select_one("a[href*='/track/']")
        href = link.get("href") if link else None
    if reminder and reminder.get("data-track-id"):
        return int(reminder["data-track-id"]), href
    if href:
        match = TRACK_HREF_ID_RE.search(href)
        if match:
            return int(match.group(1)), href
    return None, href


def parse_listing(html: str, timezone: str) -> list[dict[str, Any]]:
    soup = soupify(html)
    tracks: list[dict[str, Any]] = []
    sequence = 0

    for day_block in soup.select(".o_wesession_list > ul > li"):
        time_el = day_block.select_one("time[datetime]")
        day = time_el["datetime"] if time_el and time_el.has_attr("datetime") else None
        day_title = text(day_block.select_one(".o_we_track_day_header .h4"))
        coming_soon = (not day) and "coming soon" in day_title.lower()

        for item in day_block.select(".o_wesession_list_item"):
            sequence += 1
            track_id, href = listing_track_id(item)
            if not track_id:
                continue

            title_el = item.select_one(".o_wesession_list_item_title")
            name = html_lib.unescape(text(title_el))

            time_label = text(
                item.select_one('[data-oe-expression="track.date"]')
            )
            duration_el = item.select_one('[data-oe-expression="track.duration"]') or item.select_one(
                '[data-oe-type="duration"]'
            )
            duration_label = text(duration_el)
            duration_minutes = parse_duration_minutes(duration_label)

            location = None
            marker = item.select_one(".fa-map-marker")
            if marker:
                loc_span = marker.find_next("span")
                location = text(loc_span) or None

            speaker_line = None
            # Prefer the dedicated speaker <span>; the parent div is also .text-muted
            # and would concatenate "Name • 30 min" if we used the broader selector.
            for span in item.select("span.text-muted"):
                if span.has_attr("data-oe-expression"):
                    continue
                if span.select('[data-oe-expression="track.duration"]'):
                    continue
                candidate = html_lib.unescape(text(span))
                if not candidate or candidate in {"•", "·", "&bull;"}:
                    continue
                speaker_line = candidate
                break

            tag_ids: list[int] = []
            for badge in item.select("[data-post]"):
                post = badge.get("data-post") or ""
                match = TAG_ID_RE.search(post)
                if match:
                    tag_ids.append(int(match.group(1)))

            starts_at = None
            ends_at = None
            start_time = None
            end_time = None
            wall = parse_wallclock(time_label)
            if day and wall:
                start_dt = local_dt(day, wall[0], wall[1], timezone)
                starts_at = start_dt
                start_time = f"{wall[0]:02d}:{wall[1]:02d}"
                if duration_minutes:
                    end_dt = start_dt + timedelta(minutes=duration_minutes)
                    ends_at = end_dt
                    end_time = end_dt.strftime("%H:%M")

            tracks.append(
                {
                    "id": track_id,
                    "sequence": sequence,
                    "name": name,
                    "day": day,
                    "weekday": weekday_name(day),
                    "time_label": time_label or None,
                    "start_time": start_time,
                    "end_time": end_time,
                    "starts_at": iso(starts_at),
                    "ends_at": iso(ends_at),
                    "timezone": timezone,
                    "duration_minutes": duration_minutes,
                    "duration_label": duration_label or None,
                    "location": location,
                    "speaker_line": speaker_line,
                    "tag_ids": tag_ids,
                    "listing_url": abs_url(href),
                    "coming_soon": coming_soon,
                    "kind": infer_kind(name, duration_minutes, coming_soon),
                }
            )
    return tracks


def parse_track_detail(track_id: int, final_url: str, html: str) -> dict[str, Any]:
    soup = soupify(html)
    root = soup.select_one(".o_wesession_track_main_description")
    og = soup.select_one('meta[property="og:url"]')
    canonical = (og.get("content") if og else None) or final_url

    slug = None
    parsed = urllib.parse.urlparse(canonical)
    m = re.search(r"/track/([^/]+)$", parsed.path)
    if m:
        slug = m.group(1)

    description_el = root.select_one(".my-2.oe_no_empty") if root else None
    # Speaker bio is the other oe_no_empty block (usually before the talk text).
    bio_el = None
    if root:
        for el in root.select(".oe_no_empty"):
            if el is description_el:
                continue
            bio_el = el
            break

    speaker_name = None
    function = None
    company = None
    if root:
        # Desktop + mobile duplicate the name; take the first fw-bold that isn't the title.
        for el in root.select(".fw-bold"):
            if "h4" in (el.get("class") or []):
                continue
            candidate = text(el)
            if candidate:
                speaker_name = html_lib.unescape(candidate)
                break
        briefcase = root.select_one(".fa-briefcase")
        if briefcase:
            row = briefcase.find_parent("div")
            if row:
                spans = [text(s) for s in row.select("span") if text(s)]
                if spans:
                    function = html_lib.unescape(spans[0]).strip() or None
                if len(spans) >= 2:
                    company = html_lib.unescape(spans[-1]).strip() or None

    image_url = None
    if root:
        img = root.select_one("img")
        if img and img.get("src") and "event.track" in img.get("src", ""):
            image_url = abs_url(img["src"])
    if not image_url:
        image_url = f"{BASE}/web/image/event.track/{track_id}/image"

    return {
        "url": canonical.split("?")[0],
        "slug": slug,
        "description_html": inner_html(description_el) or None,
        "description_text": html_to_text(description_el) or None,
        "image_url": image_url,
        "speaker": {
            "name": speaker_name,
            "function": function,
            "company": company,
            "biography_html": inner_html(bio_el) or None,
            "biography_text": html_to_text(bio_el) or None,
            "image_url": image_url if speaker_name else None,
        },
    }


def parse_exhibitors(html: str) -> list[dict[str, Any]]:
    soup = soupify(html)
    exhibitors: list[dict[str, Any]] = []
    level = "Sponsor"
    # Walk heading + card nodes in document order so Startup vs Sponsors sticks.
    nodes = soup.select(".o_wesponsor_container h4, .o_wesponsor_card")
    sequence = 0
    for node in nodes:
        if node.name == "h4":
            level = text(node) or level
            continue
        sequence += 1
        btn = node.select_one(".o_wesponsor_connect_button")
        sponsor_id = int(btn["data-sponsor-id"]) if btn and btn.get("data-sponsor-id") else None
        path = btn.get("data-sponsor-url") if btn else None
        name = text(node.select_one("h5.card-title"))
        slogan = text(node.select_one("main.card-body > span.text-muted")) or None
        flag = node.select_one("img[alt]")
        country = flag.get("alt") if flag and flag.get("alt") else None
        logo_url = None
        bg = node.select_one(".o_wesponsor_bg_image")
        if bg and bg.get("style"):
            match = SPONSOR_IMAGE_RE.search(bg["style"])
            if match:
                logo_url = match.group(2)
        if not logo_url and sponsor_id:
            logo_url = f"{BASE}/web/image/event.sponsor/{sponsor_id}/image_256"
        exhibitors.append(
            {
                "id": sponsor_id,
                "sequence": sequence,
                "name": html_lib.unescape(name),
                "slogan": html_lib.unescape(slogan) if slogan else None,
                "level": level,
                "country": country,
                "logo_url": logo_url,
                "url": abs_url(path),
            }
        )
    return exhibitors


def clean_url(value: str | None) -> str | None:
    """Sponsor websites are often 'http:// example.com' or a bare domain."""
    if not value:
        return None
    raw = re.sub(r"[\t\r\n]+", " ", str(value)).strip()
    if not raw:
        return None
    lower = raw.lower()
    if "https://" in lower:
        raw = raw[lower.index("https://") :].strip()
    elif lower.startswith("http://"):
        rest = raw[7:].strip()
        raw = rest if rest.lower().startswith("http") else f"http://{rest}"
    raw = raw.replace(" ", "")
    if raw.startswith("/"):
        return abs_url(raw)
    if "://" not in raw:
        if "." not in raw:
            return None
        raw = f"https://{raw}"
    return raw or None


def parse_exhibitor_detail(html: str) -> dict[str, Any]:
    soup = soupify(html)
    main = soup.select_one(".o_wevent_sponsor") or soup.select_one(
        ".o_wesponsor_exhibitor_main"
    )
    website = None
    email = None
    phone = None
    hours = None
    contact_name = None
    if main:
        globe = main.select_one(".fa-globe")
        if globe:
            link = globe.find_parent("div")
            a = link.select_one("a[href]") if link else None
            website = clean_url(a.get("href") if a else None)
        envelope = main.select_one(".fa-envelope")
        if envelope:
            row = envelope.find_parent("div")
            email = text(row.select_one("span")) if row else None
        phone_icon = main.select_one(".fa-phone")
        if phone_icon:
            row = phone_icon.find_parent("div")
            phone = text(row.select_one("span")) if row else None
        blob = text(main)
        hours_match = re.search(
            r"Available from\s+(\d{1,2}:\d{2}\s*[AP]M)\s*-\s*(\d{1,2}:\d{2}\s*[AP]M)",
            blob,
            re.I,
        )
        if hours_match:
            hours = f"{hours_match.group(1)} – {hours_match.group(2)}"
    alert = soup.select_one(".o_wesponsor_exhibitor_main .alert b")
    if alert:
        contact_name = text(alert)
        # "Attentia, Nicole Verschuere" → person after the company comma when present
        if contact_name and "," in contact_name:
            contact_name = contact_name.split(",", 1)[1].strip() or contact_name
    about = soup.select_one(".o_wesponsor_exhibitor_main")
    description_text = None
    if about:
        # Keep contact card, not the "other exhibitors" aside.
        description_text = None
    return {
        "website": website,
        "email": email,
        "phone": phone,
        "hours": hours,
        "contact_name": contact_name,
        "description_text": description_text,
    }


def merge_speakers(tracks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Deduplicate speakers across talks; attach speaker_ids on each track."""
    speakers: list[dict[str, Any]] = []
    index: dict[tuple[str, str], int] = {}

    def key_for(name: str, company: str | None) -> tuple[str, str]:
        return (name.strip().lower(), (company or "").strip().lower())

    for track in tracks:
        raw = track.pop("speaker_detail", None)
        track["speaker_ids"] = []
        name = None
        company = None
        function = None
        bio_html = None
        bio_text = None
        image_url = None
        if raw and raw.get("name"):
            name = raw["name"]
            company = raw.get("company")
            function = raw.get("function")
            bio_html = raw.get("biography_html")
            bio_text = raw.get("biography_text")
            image_url = raw.get("image_url")
        elif track.get("speaker_line"):
            name = track["speaker_line"]

        if not name:
            continue
        key = key_for(name, company)
        if key not in index:
            speaker_id = len(speakers) + 1
            index[key] = speaker_id
            speakers.append(
                {
                    "id": speaker_id,
                    "name": name,
                    "function": function,
                    "company": company,
                    "biography_html": bio_html,
                    "biography_text": bio_text,
                    "image_url": image_url,
                }
            )
        else:
            speaker_id = index[key]
            existing = speakers[speaker_id - 1]
            # Fill gaps if a later talk has a richer profile.
            if not existing.get("function") and function:
                existing["function"] = function
            if not existing.get("company") and company:
                existing["company"] = company
            if not existing.get("biography_text") and bio_text:
                existing["biography_html"] = bio_html
                existing["biography_text"] = bio_text
            if not existing.get("image_url") and image_url:
                existing["image_url"] = image_url
        track["speaker_ids"].append(speaker_id)
    return speakers


def decorate_tracks(
    tracks: list[dict[str, Any]],
    tags_by_id: dict[int, dict[str, Any]],
    speakers: list[dict[str, Any]],
) -> None:
    speakers_by_id = {s["id"]: s for s in speakers}
    for track in tracks:
        track["tags"] = [
            tags_by_id[i] for i in track.get("tag_ids", []) if i in tags_by_id
        ]
        track["speakers"] = [
            speakers_by_id[i] for i in track.get("speaker_ids", []) if i in speakers_by_id
        ]


SQLITE_SCHEMA = """
CREATE TABLE event (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL,
    short_name TEXT NOT NULL,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    timezone TEXT NOT NULL,
    venue_name TEXT,
    venue_address TEXT,
    country_code TEXT,
    has_map INTEGER NOT NULL DEFAULT 0,
    website_url TEXT,
    agenda_url TEXT,
    tracks_url TEXT,
    exhibitors_url TEXT,
    starts_on TEXT,
    ends_on TEXT,
    scraped_at TEXT NOT NULL
);
CREATE TABLE tag_categories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    category_id INTEGER REFERENCES tag_categories(id),
    color INTEGER
);
CREATE TABLE speakers (
    event_id INTEGER NOT NULL REFERENCES event(id),
    id INTEGER NOT NULL,
    name TEXT NOT NULL,
    function TEXT,
    company TEXT,
    biography_html TEXT,
    biography_text TEXT,
    image_url TEXT,
    PRIMARY KEY (event_id, id)
);
CREATE TABLE tracks (
    id INTEGER PRIMARY KEY,
    event_id INTEGER NOT NULL REFERENCES event(id),
    sequence INTEGER,
    name TEXT NOT NULL,
    slug TEXT,
    url TEXT,
    kind TEXT,
    day TEXT,
    weekday TEXT,
    start_time TEXT,
    end_time TEXT,
    starts_at TEXT,
    ends_at TEXT,
    timezone TEXT,
    duration_minutes INTEGER,
    duration_label TEXT,
    location TEXT,
    speaker_line TEXT,
    description_html TEXT,
    description_text TEXT,
    image_url TEXT,
    coming_soon INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE track_tags (
    track_id INTEGER NOT NULL REFERENCES tracks(id),
    tag_id INTEGER NOT NULL REFERENCES tags(id),
    PRIMARY KEY (track_id, tag_id)
);
CREATE TABLE track_speakers (
    event_id INTEGER NOT NULL,
    track_id INTEGER NOT NULL REFERENCES tracks(id),
    speaker_id INTEGER NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (track_id, speaker_id)
);
CREATE TABLE exhibitors (
    id INTEGER PRIMARY KEY,
    event_id INTEGER NOT NULL REFERENCES event(id),
    sequence INTEGER,
    name TEXT NOT NULL,
    slogan TEXT,
    level TEXT,
    country TEXT,
    logo_url TEXT,
    url TEXT,
    website TEXT,
    email TEXT,
    phone TEXT,
    hours TEXT,
    contact_name TEXT
);
CREATE VIRTUAL TABLE tracks_fts USING fts5(
    name, speaker_line, description_text, location,
    content='tracks', content_rowid='id'
);
"""


def write_sqlite(path: Path, bundle: dict[str, Any]) -> None:
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SQLITE_SCHEMA)

    events = bundle["events"]
    # Tags are global on odoo.com — take the first event's catalog (same RPC).
    first = events[0]
    conn.executemany(
        "INSERT OR IGNORE INTO tag_categories (id, name) VALUES (?, ?)",
        [(c["id"], c["name"]) for c in first.get("tag_categories") or []],
    )
    conn.executemany(
        "INSERT OR IGNORE INTO tags (id, name, category_id, color) VALUES (?, ?, ?, ?)",
        [
            (t["id"], t["name"], t.get("category_id"), t.get("color"))
            for t in first.get("tags") or []
        ],
    )

    for payload in events:
        event = payload["event"]
        event_id = event["id"]
        conn.execute(
            """
            INSERT INTO event (
                id, code, short_name, name, slug, timezone, venue_name, venue_address,
                country_code, has_map, website_url, agenda_url, tracks_url, exhibitors_url,
                starts_on, ends_on, scraped_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                event_id,
                event.get("code"),
                event.get("short_name"),
                event["name"],
                event["slug"],
                event["timezone"],
                event.get("venue_name"),
                event.get("venue_address"),
                event.get("country_code"),
                1 if event.get("has_map") else 0,
                event.get("website_url"),
                event.get("agenda_url"),
                event.get("tracks_url"),
                event.get("exhibitors_url"),
                event.get("starts_on"),
                event.get("ends_on"),
                event["scraped_at"],
            ),
        )
        conn.executemany(
            """
            INSERT INTO speakers (
                event_id, id, name, function, company, biography_html, biography_text, image_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    event_id,
                    s["id"],
                    s["name"],
                    s.get("function"),
                    s.get("company"),
                    s.get("biography_html"),
                    s.get("biography_text"),
                    s.get("image_url"),
                )
                for s in payload.get("speakers") or []
            ],
        )
        conn.executemany(
            """
            INSERT INTO tracks (
                id, event_id, sequence, name, slug, url, kind, day, weekday, start_time, end_time,
                starts_at, ends_at, timezone, duration_minutes, duration_label, location,
                speaker_line, description_html, description_text, image_url, coming_soon
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            [
                (
                    t["id"],
                    event_id,
                    t.get("sequence"),
                    t["name"],
                    t.get("slug"),
                    t.get("url"),
                    t.get("kind"),
                    t.get("day"),
                    t.get("weekday"),
                    t.get("start_time"),
                    t.get("end_time"),
                    t.get("starts_at"),
                    t.get("ends_at"),
                    t.get("timezone"),
                    t.get("duration_minutes"),
                    t.get("duration_label"),
                    t.get("location"),
                    t.get("speaker_line"),
                    t.get("description_html"),
                    t.get("description_text"),
                    t.get("image_url"),
                    1 if t.get("coming_soon") else 0,
                )
                for t in payload["tracks"]
            ],
        )
        known_tag_ids = {tag["id"] for tag in first.get("tags") or []}
        tag_rows = []
        speaker_rows = []
        for t in payload["tracks"]:
            for tag_id in t.get("tag_ids", []):
                if tag_id in known_tag_ids:
                    tag_rows.append((t["id"], tag_id))
            for pos, speaker_id in enumerate(t.get("speaker_ids", [])):
                speaker_rows.append((event_id, t["id"], speaker_id, pos))
        conn.executemany(
            "INSERT OR IGNORE INTO track_tags (track_id, tag_id) VALUES (?, ?)",
            tag_rows,
        )
        conn.executemany(
            "INSERT INTO track_speakers (event_id, track_id, speaker_id, position) VALUES (?, ?, ?, ?)",
            speaker_rows,
        )
        conn.executemany(
            """
            INSERT INTO exhibitors (
                id, event_id, sequence, name, slogan, level, country, logo_url, url,
                website, email, phone, hours, contact_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    e["id"],
                    event_id,
                    e.get("sequence"),
                    e["name"],
                    e.get("slogan"),
                    e.get("level"),
                    e.get("country"),
                    e.get("logo_url"),
                    e.get("url"),
                    e.get("website"),
                    e.get("email"),
                    e.get("phone"),
                    e.get("hours"),
                    e.get("contact_name"),
                )
                for e in payload["exhibitors"]
                if e.get("id") is not None
            ],
        )

    conn.execute(
        """
        INSERT INTO tracks_fts(rowid, name, speaker_line, description_text, location)
        SELECT id, name, speaker_line, description_text, location FROM tracks
        """
    )
    conn.commit()
    conn.close()


def slim_track(track: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": track["id"],
        "sequence": track.get("sequence"),
        "name": track["name"],
        "slug": track.get("slug"),
        "url": track.get("url"),
        "kind": track.get("kind") or "talk",
        "day": track.get("day"),
        "weekday": track.get("weekday"),
        "start_time": track.get("start_time"),
        "end_time": track.get("end_time"),
        "starts_at": track.get("starts_at"),
        "ends_at": track.get("ends_at"),
        "timezone": track.get("timezone"),
        "duration_minutes": track.get("duration_minutes"),
        "duration_label": track.get("duration_label"),
        "location": track.get("location"),
        "speaker_line": track.get("speaker_line"),
        "description_text": track.get("description_text"),
        "image_url": track.get("image_url"),
        "coming_soon": bool(track.get("coming_soon")),
        "tag_ids": track.get("tag_ids") or [],
        "speaker_ids": track.get("speaker_ids") or [],
        "tags": [
            {
                "id": tag["id"],
                "name": tag["name"],
                "category": tag.get("category"),
                "color": tag.get("color"),
            }
            for tag in (track.get("tags") or [])
        ],
        "speakers": [
            {
                "id": speaker["id"],
                "name": speaker["name"],
                "function": speaker.get("function"),
                "company": speaker.get("company"),
                "biography_text": speaker.get("biography_text"),
                "image_url": speaker.get("image_url"),
            }
            for speaker in (track.get("speakers") or [])
        ],
    }


def slim_event_payload(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "event": payload["event"],
        "tags": payload["tags"],
        "tag_categories": payload.get("tag_categories") or [],
        "locations": payload.get("locations") or [],
        "tracks": [slim_track(track) for track in payload["tracks"]],
        "exhibitors": [
            {
                "id": exhibitor["id"],
                "sequence": exhibitor.get("sequence"),
                "name": exhibitor["name"],
                "slogan": exhibitor.get("slogan"),
                "level": exhibitor.get("level") or "Sponsors",
                "country": exhibitor.get("country"),
                "logo_url": exhibitor.get("logo_url"),
                "url": exhibitor.get("url"),
                "website": clean_url(exhibitor.get("website")),
                "hours": exhibitor.get("hours"),
            }
            for exhibitor in payload["exhibitors"]
        ],
    }


def write_ios_catalog(bundle: dict[str, Any]) -> Path:
    """Slim JSON for the iOS bundle — text only, no HTML."""
    slim = {
        "default_event_id": bundle.get("default_event_id", DEFAULT_EVENT_ID),
        "events": [slim_event_payload(payload) for payload in bundle["events"]],
    }
    dest = ROOT / "OXP" / "Resources" / "catalog.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(slim, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return dest


def fetch_all_details(
    fetcher: Fetcher,
    ids: list[int],
    kind: str,
    workers: int,
    event_url: str,
) -> dict[int, tuple[str, str]]:
    results: dict[int, tuple[str, str]] = {}
    errors: list[tuple[int, str]] = []

    def one(item_id: int) -> tuple[int, str, str]:
        if kind == "track":
            url = f"{event_url}/track/{item_id}"
            cache_key = f"tracks/{item_id}.html"
        else:
            url = f"{event_url}/exhibitor/{item_id}"
            cache_key = f"exhibitors/{item_id}.html"
        final, body = fetcher.get(url, cache_key=cache_key)
        return item_id, final, body

    done = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(one, i): i for i in ids}
        for fut in as_completed(futures):
            item_id = futures[fut]
            try:
                got_id, final, body = fut.result()
                results[got_id] = (final, body)
            except Exception as exc:  # noqa: BLE001 — keep scrape going
                errors.append((item_id, str(exc)))
            done += 1
            if done % 50 == 0 or done == len(ids):
                log(f"  {kind}s {done}/{len(ids)}")
    if errors:
        log(f"  {len(errors)} {kind} detail fetches failed")
        for item_id, err in errors[:8]:
            log(f"    {item_id}: {err}")
    return results


def build_payload(
    spec: dict[str, Any],
    tracks: list[dict[str, Any]],
    speakers: list[dict[str, Any]],
    tags: list[dict[str, Any]],
    categories: list[dict[str, Any]],
    exhibitors: list[dict[str, Any]],
    scraped_at: str,
) -> dict[str, Any]:
    days = sorted({t["day"] for t in tracks if t.get("day")})
    locations = sorted({t["location"] for t in tracks if t.get("location")})
    event_url = f"{BASE}/event/{spec['slug']}"
    return {
        "event": {
            "id": spec["id"],
            "code": spec["code"],
            "short_name": spec["short_name"],
            "name": spec["name"],
            "slug": spec["slug"],
            "timezone": spec["timezone"],
            "venue_name": spec["venue_name"],
            "venue_address": spec["venue_address"],
            "country_code": spec["country_code"],
            "has_map": spec["has_map"],
            "website_url": event_url,
            "agenda_url": f"{event_url}/agenda",
            "tracks_url": f"{event_url}/track",
            "exhibitors_url": f"{event_url}/exhibitors",
            "starts_on": days[0] if days else None,
            "ends_on": days[-1] if days else None,
            "scraped_at": scraped_at,
        },
        "stats": {
            "tracks": len(tracks),
            "tracks_with_description": sum(
                1 for t in tracks if t.get("description_text")
            ),
            "speakers": len(speakers),
            "tags": len(tags),
            "locations": len(locations),
            "exhibitors": len(exhibitors),
            "days": days,
        },
        "tag_categories": categories,
        "tags": tags,
        "locations": locations,
        "speakers": speakers,
        "tracks": tracks,
        "exhibitors": exhibitors,
    }


def scrape_event(
    spec: dict[str, Any],
    fetcher: Fetcher,
    tags: list[dict[str, Any]],
    tags_by_id: dict[int, dict[str, Any]],
    categories: list[dict[str, Any]],
    scraped_at: str,
    args: argparse.Namespace,
) -> dict[str, Any]:
    event_url = f"{BASE}/event/{spec['slug']}"
    code = spec["code"]
    log(f"\n=== {spec['short_name']} ({spec['id']}) ===")

    log("Fetching talk list…")
    _, listing_html = fetcher.get(
        f"{event_url}/track", cache_key=f"{code}/listing.html"
    )
    tracks = parse_listing(listing_html, spec["timezone"])
    log(f"  {len(tracks)} tracks")

    log("Fetching exhibitors list…")
    _, exhibitors_html = fetcher.get(
        f"{event_url}/exhibitors", cache_key=f"{code}/exhibitors.html"
    )
    exhibitors = parse_exhibitors(exhibitors_html)
    log(f"  {len(exhibitors)} exhibitors")

    if not args.skip_details:
        log("Fetching talk pages…")
        details = fetch_all_details(
            fetcher, [t["id"] for t in tracks], "track", args.workers, event_url
        )
        for track in tracks:
            pair = details.get(track["id"])
            if not pair:
                track["url"] = track.get("listing_url") or f"{event_url}/track/{track['id']}"
                track["slug"] = None
                track["description_html"] = None
                track["description_text"] = None
                track["image_url"] = f"{BASE}/web/image/event.track/{track['id']}/image"
                track["speaker_detail"] = None
                continue
            final, body = pair
            parsed = parse_track_detail(track["id"], final, body)
            track["url"] = parsed["url"]
            track["slug"] = parsed["slug"]
            track["description_html"] = parsed["description_html"]
            track["description_text"] = parsed["description_text"]
            track["image_url"] = parsed["image_url"]
            track["speaker_detail"] = parsed["speaker"]
    else:
        for track in tracks:
            track["url"] = track.get("listing_url") or f"{event_url}/track/{track['id']}"
            track["slug"] = None
            track["description_html"] = None
            track["description_text"] = None
            track["image_url"] = f"{BASE}/web/image/event.track/{track['id']}/image"
            track["speaker_detail"] = None

    if not args.skip_exhibitor_details:
        log("Fetching exhibitor pages…")
        ids = [e["id"] for e in exhibitors if e.get("id")]
        details = fetch_all_details(fetcher, ids, "exhibitor", args.workers, event_url)
        for exhibitor in exhibitors:
            pair = details.get(exhibitor["id"])
            extra = parse_exhibitor_detail(pair[1]) if pair else {}
            exhibitor.update(extra)
    else:
        for exhibitor in exhibitors:
            exhibitor.update(
                {
                    "website": None,
                    "email": None,
                    "phone": None,
                    "hours": None,
                    "contact_name": None,
                }
            )

    speakers = merge_speakers(tracks)
    decorate_tracks(tracks, tags_by_id, speakers)
    payload = build_payload(spec, tracks, speakers, tags, categories, exhibitors, scraped_at)
    dest = DATA_DIR / "events" / f"{code}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    log(
        f"  {payload['stats']['tracks']} talks, "
        f"{payload['stats']['tracks_with_description']} with descriptions, "
        f"{payload['stats']['exhibitors']} exhibitors"
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Scrape Odoo Experience 2026 seed data")
    parser.add_argument("--workers", type=int, default=10)
    parser.add_argument("--skip-details", action="store_true")
    parser.add_argument("--skip-exhibitor-details", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument(
        "--events",
        default="all",
        help="Comma-separated event codes (us,mx,ke,in,be) or 'all'",
    )
    args = parser.parse_args()

    wanted = {item.strip().lower() for item in args.events.split(",")}
    specs = EVENTS if "all" in wanted else [spec for spec in EVENTS if spec["code"] in wanted]
    if not specs:
        log("No matching events. Use: us, mx, ke, in, be")
        return 1

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    fetcher = Fetcher(cache=not args.no_cache)
    scraped_at = datetime.now(ZoneInfo("Europe/Brussels")).isoformat(timespec="seconds")

    log("Fetching tag catalog (public JSON-RPC)…")
    categories, tags = fetch_tags(fetcher)
    tags_by_id = {t["id"]: t for t in tags}
    log(f"  {len(tags)} tags in {len(categories)} categories")

    payloads = []
    for spec in specs:
        try:
            payloads.append(
                scrape_event(spec, fetcher, tags, tags_by_id, categories, scraped_at, args)
            )
        except Exception as exc:  # noqa: BLE001 — keep other editions
            log(f"FAILED {spec['short_name']} ({spec['id']}): {exc}")
    if not payloads:
        log("No events scraped.")
        return 1
    bundle = {
        "default_event_id": DEFAULT_EVENT_ID,
        "scraped_at": scraped_at,
        "events": payloads,
    }

    json_path = DATA_DIR / "oxp-2026.json"
    sqlite_path = DATA_DIR / "oxp-2026.sqlite"
    json_path.write_text(
        json.dumps(bundle, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_sqlite(sqlite_path, bundle)
    ios_path = write_ios_catalog(bundle)

    checksum = hashlib.sha256(json_path.read_bytes()).hexdigest()[:12]
    log("")
    log(f"Wrote {json_path.relative_to(ROOT)}")
    log(f"Wrote {sqlite_path.relative_to(ROOT)}")
    log(f"Wrote {ios_path.relative_to(ROOT)}")
    for payload in payloads:
        event = payload["event"]
        stats = payload["stats"]
        log(
            f"  {event['short_name']}: {stats['tracks']} talks, "
            f"{stats['exhibitors']} exhibitors, days {', '.join(stats['days']) or '—'}"
        )
    log(f"JSON sha256[0:12]: {checksum}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
