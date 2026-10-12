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
- `files/mame-arcade/` - packs converted from the MAME cheat collection for
  arcade romsets known to EmuCoreH.
- `scripts/build-catalog.ps1` - rebuilds every pack and the catalog from a
  sparse checkout of libretro-database, bucanero's cheat database, the
  extracted MAME cheat XMLs and the arcade game table of the app. Run it after
  any of those change.
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
