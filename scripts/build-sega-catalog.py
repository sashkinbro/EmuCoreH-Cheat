#!/usr/bin/env python3
"""Import only jgenesis-supported device codes from a pinned libretro-database revision.
No retail ROMs are used. Existing Dreamcast/arcade entries remain unchanged.
"""
import concurrent.futures, collections, datetime, hashlib, json, re, time, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "6a23a64fea8b0498e69ab534dda1c602ed064544"
RAW = "https://raw.githubusercontent.com/libretro/libretro-database/" + REVISION + "/"
FOLDERS = {
 "Sega - Mega Drive - Genesis": "GENESIS", "Sega - Mega-CD - Sega CD": "SEGA_CD",
 "Sega - 32X": "SEGA_32X", "Sega - Master System - Mark III": "MASTER_SYSTEM",
 "Sega - Game Gear": "GAME_GEAR", "Sega - SG-1000": "SG_1000",
}
CACHE = ROOT / ".source-cache"
ALPHABET = "ABCDEFGHJKLMNPRSTVWXYZ0123456789"


def fetch(url):
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "EmuCoreH-cheat-catalog/1"})
            return urllib.request.urlopen(request, timeout=45).read()
        except Exception:
            if attempt == 3: raise
            time.sleep(attempt + 1)


def source_paths():
    tree_file = CACHE / "tree.json"
    if tree_file.exists(): return json.loads(tree_file.read_text())["paths"]
    api = "https://api.github.com/repos/libretro/libretro-database/git/trees/"
    root = json.loads(fetch(api + REVISION))
    cht = next(item["sha"] for item in root["tree"] if item["path"] == "cht")
    tree = json.loads(fetch(api + cht + "?recursive=1"))
    assert not tree.get("truncated"), "Cannot build from a partial source tree"
    paths = sorted(item["path"] for item in tree["tree"] if item["path"].endswith(".cht")
                   and item["path"].split("/")[0] in FOLDERS)
    tree_file.write_text(json.dumps({"commit": REVISION, "paths": paths}, indent=2))
    return paths


def genesis_address(code):
    if re.fullmatch(r"[A-HJ-NPR-TV-Z0-9]{4}-[A-HJ-NPR-TV-Z0-9]{4}", code):
        scrambled = 0
        for char in code.replace("-", ""): scrambled = (scrambled << 5) | ALPHABET.index(char)
        return ((scrambled >> 16 & 255) << 16) | ((scrambled >> 24 & 255) << 8) | (scrambled & 255)
    if re.fullmatch(r"[0-9A-F]{6}:[0-9A-F]{4}", code): return int(code[:6], 16)
    if re.fullmatch(r"[0-9A-F]{5}[ -][0-9A-F]{5}", code): return int(code.replace("-", "").replace(" ", "")[:6], 16)
    return None


def supported(code, platform):
    if platform in ("GENESIS", "SEGA_CD", "SEGA_32X"):
        address = genesis_address(code)
        if address is None: return False
        # These upstream APIs expose word overrides. Odd address byte codes can
        # overwrite a neighbouring byte, so do not advertise those as supported.
        if address & 1: return False
        return 0xFF0000 <= address <= 0xFFFFFE or (platform != "SEGA_CD" and address <= 0x3FFFFE)
    return bool(re.fullmatch(r"[0-9A-F]{3}-[0-9A-F]{3}(?:-[0-9A-F]{3})?|00[0-9A-F]{2}[ -]?[0-9A-F]{4}", code))


def load_source(path):
    file = CACHE / "cht" / path
    if not file.exists():
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(fetch(RAW + "cht/" + urllib.parse.quote(path, safe="/")))
    try: raw = file.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError: raw = file.read_bytes().decode("cp1252")
    return path, raw


def blocks_from(raw, platform):
    fields = {}
    for match in re.finditer(r'^cheat(\d+)_(desc|code)\s*=\s*"?(.*?)"?\s*$', raw, re.M):
        fields.setdefault(int(match[1]), {})[match[2]] = match[3].strip()
    blocks = []
    for _, fields in sorted(fields.items()):
        codes = [part.strip().upper() for part in fields.get("code", "").split("+") if part.strip()]
        if not codes or not all(supported(code, platform) for code in codes): continue
        title = fields.get("desc", "").strip()
        if not title or re.search(r"master code|enable code|\(m\)|\[m\]", title, re.I): continue
        # Single, intact upstream blocks; never retain half a conditional code.
        blocks.append((title.replace("\n", " "), codes))
    return blocks


def main():
    CACHE.mkdir(exist_ok=True)
    license_path = ROOT / "LICENSES" / "libretro-database-CC-BY-SA-4.0.txt"
    license_path.parent.mkdir(exist_ok=True)
    license_path.write_bytes(fetch(RAW + "LICENSE"))
    catalog = json.loads((ROOT / "cheats.json").read_text(encoding="utf-8-sig"))
    previous = [entry for entry in catalog["entries"] if not entry["id"].startswith("libretro-sega-")]
    paths = [path for path in source_paths() if path.split("/")[0] in FOLDERS]
    imported, counts, block_counts = [], collections.Counter(), collections.Counter()
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
        for index, (source, raw) in enumerate(pool.map(load_source, paths), 1):
            platform = FOLDERS[source.split("/")[0]]
            blocks = blocks_from(raw, platform)
            if not blocks: continue
            title = Path(source).stem
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:140]
            ident = "libretro-sega-" + platform.lower().replace("_", "-") + "-" + slug + "-" + hashlib.sha256(source.encode()).hexdigest()[:8]
            pack_path = "files/libretro-sega/" + platform.lower() + "/" + ident + ".txt"
            pack = ROOT / pack_path
            pack.parent.mkdir(parents=True, exist_ok=True)
            contents = "\n\n".join("// " + label + "\n" + "\n".join(codes) for label, codes in blocks) + "\n"
            pack.write_text(contents, encoding="utf-8", newline="\n")
            # Round-trip guarantees generated text uses only exactly accepted syntax.
            actual_codes = [line for line in contents.splitlines() if line and not line.startswith("//")]
            assert all(supported(code, platform) for code in actual_codes)
            entry = dict(id=ident, title=title, platform=platform, serials=[],
                authors=["libretro-database contributors and the original cheat authors"],
                description=f"{len(blocks)} device-code blocks for {platform}; match the named game revision. "
                    "Only supported ROM/main CPU RAM overrides are included. Individual retail-game effects are not independently verified.",
                downloadUrl="https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/" + pack_path,
                packPath=pack_path, sourceUrl="https://github.com/libretro/libretro-database/blob/" + REVISION + "/cht/" + urllib.parse.quote(source, safe="/"),
                sourceName="libretro-database Sega device cheats", license="CC-BY-SA-4.0; converted from the pinned upstream file; original description and revision retained",
                blockCount=len(blocks), updatedAt=now, sha256=hashlib.sha256(contents.encode()).hexdigest())
            imported.append(entry); counts[platform] += 1; block_counts[platform] += len(blocks)
            if index % 250 == 0: print(f"Processed {index}/{len(paths)}", flush=True)
    catalog["entries"] = previous + sorted(imported, key=lambda entry: (entry["platform"], entry["title"]))
    catalog["generatedAt"] = now
    assert len({entry["id"] for entry in catalog["entries"]}) == len(catalog["entries"])
    (ROOT / "cheats.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    report = {"commit": REVISION, "sourceFiles": len(paths), "preservedEntries": len(previous), "packs": dict(counts), "blocks": dict(block_counts)}
    (ROOT / "scripts" / "sega-import-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))

if __name__ == "__main__": main()
