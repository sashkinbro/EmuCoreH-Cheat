# EmuCoreH Dreamcast Cheat Catalog

Cheat packs for Dreamcast games running on the Flycast core inside EmuCoreH.

The app reads the catalog from:

`https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/cheats.json`

Every entry is a plain text pack for one game revision. Packs contain the
address/value pairs that EmuCoreH imports and hands to the core cheat API.
The serials field is the disc product code the core reports after loading a
disc, for example `MK-51035`, so a pack only appears for the discs it was
built for.

## Contents

- `cheats.json` - schema version 1 catalog consumed by EmuCoreH.
- `files/libretro-dreamcast/` - packs converted from the Dreamcast folder of
  libretro-database under its repository CC-BY-SA-4.0 license.
- `scripts/build-catalog.ps1` - rebuilds every pack and the catalog from a
  sparse checkout of libretro-database. Run it after the upstream folder or
  the metadata DAT changes.
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
