"""Crawl GameHacking.org Dreamcast codes into markdown packs for the EmuCoreH cheat catalog.

Uses curl_cffi with Chrome TLS impersonation (Cloudflare passes) and the site's
own group AJAX endpoint (/modules/game.php). Resumable: processed game ids are
tracked in gh-dc-done.json and existing .md files are skipped.
"""

import json
import html
import os
import re
import sys
import time

from curl_cffi import requests

OUT_DIR = r"E:\TMP\gshi-dreamcast"
STATE_FILE = r"C:\windows\Temp\opencode\gh-dc-done.json"
LIST_FILE = r"C:\windows\Temp\opencode\gh-dc-games.json"
BASE = "https://gamehacking.org"

session = requests.Session(impersonate="chrome")
HEADERS = {"Referer": BASE + "/system/dc", "Origin": BASE}

MASTER_RE = re.compile(r"^\s*[\[\(]?M[\]\)]?|must be on|enable code", re.IGNORECASE)
CODE_RE = re.compile(r"(?<![0-9A-F])[0-9A-F]{8,16}(?![0-9A-F])", re.IGNORECASE)


def slugify(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:80] or "game"


def region_suffix(title):
    lowered = title.lower()
    if "usa" in lowered or "u.s.a" in lowered:
        return "usa"
    if "europe" in lowered or "pal" in lowered:
        return "pal"
    if "japan" in lowered:
        return "jap"
    return "world"


def list_games():
    if os.path.exists(LIST_FILE):
        with open(LIST_FILE, encoding="utf-8") as handle:
            cached = json.load(handle)
        if cached:
            return cached
    ids = []
    seen = set()
    for page in range(0, 80):
        url = f"{BASE}/system/dc/all/{page}"
        try:
            response = session.get(url, timeout=60)
        except Exception as error:
            print("list page", page, "failed:", error)
            break
        found = re.findall(r'href="/game/(\d+)"', response.text)
        new = [gid for gid in dict.fromkeys(found) if gid not in seen]
        for gid in new:
            seen.add(gid)
            ids.append(gid)
        print(f"page {page}: {len(new)} new (total {len(ids)})", flush=True)
        if not new:
            break
        time.sleep(0.3)
    with open(LIST_FILE, "w", encoding="utf-8") as handle:
        json.dump(ids, handle)
    return ids


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as handle:
            return set(json.load(handle))
    return set()


def save_state(done):
    with open(STATE_FILE, "w", encoding="utf-8") as handle:
        json.dump(sorted(done), handle)


def parse_codes(html):
    blocks = []
    for row in re.split(r"<tr[^>]*>", html):
        if "<pre>" not in row:
            continue
        name_match = re.search(r"<label[^>]*>.*?</label>", row, re.S)
        if not name_match:
            continue
        name = re.sub(r"<[^>]+>", " ", name_match.group(0))
        name = re.sub(r"\s+", " ", name).strip()
        if not name or MASTER_RE.search(name):
            continue
        code_match = re.search(r"<pre>(.*?)</pre>", row, re.S)
        if not code_match:
            continue
        codes = []
        for line in code_match.group(1).splitlines():
            tokens = [token.upper() for token in CODE_RE.findall(line)]
            for token in tokens:
                codes.append(token)
        if not codes:
            continue
        pairs = []
        index = 0
        while index < len(codes):
            token = codes[index]
            if len(token) == 16:
                pairs.append(token[:8] + " " + token[8:])
                index += 1
            elif len(token) == 8 and index + 1 < len(codes) and len(codes[index + 1]) == 8:
                pairs.append(token + " " + codes[index + 1])
                index += 2
            else:
                index += 1
        if pairs:
            blocks.append((name, pairs))
    return blocks


def fetch_game(game_id):
    response = session.get(f"{BASE}/game/{game_id}", timeout=60)
    if response.status_code != 200:
        return None, []
    title_match = re.search(r"<title>GameHacking.org \| (.+?)</title>", response.text)
    title = html.unescape(title_match.group(1).strip()) if title_match else f"game-{game_id}"
    group_ids = list(dict.fromkeys(re.findall(r"grpID:\s*(\d+)", response.text)))
    blocks = []
    for group_id in group_ids:
        try:
            group = session.post(
                f"{BASE}/modules/game.php",
                data={
                    "gamID": game_id,
                    "grpID": group_id,
                    "filter[name]": "",
                    "filter[format]": "original",
                    "filter[enc]": "",
                    "filter[hacker]": "",
                },
                headers=HEADERS,
                timeout=90,
            )
        except Exception as error:
            print(f"  group {group_id} failed: {error}", flush=True)
            continue
        blocks.extend(parse_codes(group.text))
        time.sleep(0.2)
    return title, blocks


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    games = list_games()
    done = load_state()
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(games)
    processed = 0
    written = 0
    for game_id in games:
        if game_id in done:
            continue
        if processed >= limit:
            break
        processed += 1
        try:
            title, blocks = fetch_game(game_id)
        except Exception as error:
            print(f"game {game_id} failed: {error}", flush=True)
            continue
        if title and blocks:
            suffix = region_suffix(title)
            path = os.path.join(OUT_DIR, f"{slugify(title)}-({suffix}).md")
            lines = [f"# {title}", ""]
            for name, pairs in blocks:
                lines.append(f"## {name}")
                lines.append("")
                lines.append("```")
                lines.extend(pairs)
                lines.append("```")
                lines.append("")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("\n".join(lines))
            written += 1
        done.add(game_id)
        if processed % 20 == 0:
            save_state(done)
            print(f"progress: processed={processed} written={written} done={len(done)}/{len(games)}", flush=True)
        time.sleep(0.25)
    save_state(done)
    print(f"finished: processed={processed} written={written} done={len(done)}/{len(games)}", flush=True)


if __name__ == "__main__":
    main()
