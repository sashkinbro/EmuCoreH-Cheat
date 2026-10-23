# EmuCoreH Cheat Catalog

Cheat packs for Dreamcast and arcade (Naomi, Naomi 2, Atomiswave, System SP)
games running on the Flycast core inside EmuCoreH.

The app reads the catalog from:

`https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/cheats.json`

Every entry is a plain text pack for one game revision. Packs contain the
address/value pairs that EmuCoreH imports and hands to the core cheat API.
The serials field is the key the app looks up for a running game: the disc
product code for Dreamcast, for example `MK-51035`, or the romset name for
arcade games, for example `mvsc2`.

## Contents

- `cheats.json` - schema version 1 catalog consumed by EmuCoreH.
- `files/libretro-dreamcast/` - packs converted from the Dreamcast folder of
  libretro-database under its repository CC-BY-SA-4.0 license.
- `files/bucanero-dreamcast/` - Action Replay CDX packs from bucanero's
  Dreamcast Cheat Database (GPL-3.0), added only for disc codes the libretro
  packs do not cover.
- `files/gshi-dreamcast/` - packs crawled from the GameHacking.org Dreamcast
  database with `scripts/crawl-gamehacking.py`.
- `files/mame-arcade/` - packs converted from the MAME cheat collection for
  arcade romsets known to EmuCoreH.
- `scripts/build-catalog.ps1` - rebuilds every pack and the catalog from a
  sparse checkout of libretro-database, bucanero's cheat database, the
  GameHacking.org crawl output, the extracted MAME cheat XMLs and the arcade
  game table of the app. Run it after any of those change.
- `scripts/crawl-gamehacking.py` - refreshes `files/gshi-dreamcast/` from
  GameHacking.org (requires `curl_cffi`).
- `schemas/cheat-catalog.schema.json` - field contract of the catalog.
- `sources.json` - pinned upstream revisions and licensing notes.

## Rebuilding

```powershell
git clone --filter=blob:none --sparse https://github.com/libretro/libretro-database E:\TMP\libretro-database
git -C E:\TMP\libretro-database sparse-checkout set "cht/Sega - Dreamcast" "metadat/redump"
.\scripts\build-catalog.ps1
```

Cheat blocks that target unsupported code types, repeats or GameShark enable
codes are dropped during conversion; only plain value writes reach the core.
For arcade romsets only unconditional run-state writes to SH4 main RAM are
converted.

## Sega cartridges and CD main CPU RAM

`files/libretro-sega/` contains device-code packs from the pinned libretro-database
revision in `sources.json`. New entries have a `platform` field; older entries
without that field are Flycast packs. Sega packs keep the upstream game revision
filename. Match that revision before enabling codes. The app isolates platforms
and compares the complete source filename including region/revision markers;
other revisions remain unavailable for automatic installation.

The conversion preserves Game Genie, Action Replay and plain address:value
spelling and complete block descriptions. Genesis/32X support cartridge ROM and
main 68000 RAM; Sega CD supports main 68000 RAM only. SMS/Game Gear/SG-1000
support the upstream Game Genie and Pro Action Replay byte override formats.
CD program/word RAM, SH-2 RAM, odd 68000 byte addresses, master/enable codes and
unsupported multi-code blocks are excluded. These exclusions prevent unsupported
codes from appearing as usable packs. The engine is tested using authored ROM
programs; the individual retail game effects have not been independently tested.

Run `python scripts/build-sega-catalog.py` to regenerate deterministically from
the pinned source revision. Downloads are cached in ignored `.source-cache/`.
`scripts/sega-import-report.json` records platform pack/block totals. The source
license is included in `LICENSES/libretro-database-CC-BY-SA-4.0.txt`; converted
Sega packs retain CC-BY-SA-4.0 and credit the original contributors. Existing
Dreamcast/arcade entries remain intact.
