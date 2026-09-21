param(
    [string]$DatabaseRoot = "E:\TMP\libretro-database",
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$cheatsRoot = Join-Path $DatabaseRoot "cht\Sega - Dreamcast"
$datFile = Join-Path $DatabaseRoot "metadat\redump\Sega - Dreamcast.dat"
$packDir = Join-Path $RepositoryRoot "files\libretro-dreamcast"
$commit = (git -C $DatabaseRoot rev-parse HEAD).Trim()
$catalogIdPrefix = "libretro-dreamcast"

function Get-TitleKey([string]$value) {
    $text = $value.ToLowerInvariant()
    $text = [regex]::Replace($text, "\([^)]*\)", " ")
    $text = [regex]::Replace($text, "[^a-z0-9]+", "")
    return $text
}

function Get-PreferredSerial([string]$raw) {
    foreach ($match in [regex]::Matches($raw, "[A-Z0-9]{2,4}-[0-9]{3,5}[A-Z]?")) {
        $token = $match.Value
        $prefix = $token.Split("-")[0]
        if ($prefix -match "[A-Z]") { return $token }
    }
    return $null
}

$gamesByKey = @{}
$games = [System.Collections.Generic.List[object]]::new()
$currentName = $null
$currentRegion = ""
foreach ($line in Get-Content $datFile) {
    if ($line -match '^\s*name\s+"(.+)"\s*$') {
        $currentName = $Matches[1]
        $currentRegion = ""
        continue
    }
    if ($line -match '^\s*region\s+"(.+)"\s*$') {
        $currentRegion = $Matches[1]
        continue
    }
    if ($line -match '^\s*serial\s+"(.+)"\s*$' -and $currentName) {
        $serial = Get-PreferredSerial $Matches[1]
        if ($serial) {
            $key = Get-TitleKey $currentName
            if (-not $gamesByKey.ContainsKey($key)) { $gamesByKey[$key] = [System.Collections.Generic.List[string]]::new() }
            if (-not $gamesByKey[$key].Contains($serial)) { $gamesByKey[$key].Add($serial) }
            $games.Add([pscustomobject]@{ Key = $key; Serial = $serial; Region = $currentRegion })
        }
    }
}

function Resolve-Serials([string]$key) {
    $serials = [System.Collections.Generic.List[string]]::new()
    if ($gamesByKey.ContainsKey($key)) {
        foreach ($serial in $gamesByKey[$key]) { $serials.Add([string]$serial) }
    }
    if ($serials.Count -gt 0) { return $serials.ToArray() }

    $fallback = [System.Collections.Generic.List[object]]::new()
    $fallbackSerials = [System.Collections.Generic.List[string]]::new()
    foreach ($game in $games) {
        if ($game.Key.Length -lt 4 -or $key.Length -lt 4) { continue }
        if ($game.Key.StartsWith($key) -or $key.StartsWith($game.Key)) {
            if (-not $fallbackSerials.Contains($game.Serial)) { $fallbackSerials.Add($game.Serial) }
            $fallback.Add($game)
        }
    }
    if ($fallbackSerials.Count -eq 0) { return [string[]]@() }
    if (@($fallback | Where-Object { $_.Region -match "USA|World" }).Count -gt 0) {
        $serials.Clear()
        foreach ($game in $fallback) {
            if ($game.Region -match "USA|World") { $serials.Add($game.Serial) }
        }
        if ($serials.Count -gt 0) { return $serials.ToArray() }
    }
    return $fallbackSerials.ToArray()
}

New-Item -ItemType Directory -Force -Path $packDir | Out-Null
Get-ChildItem $packDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

$entries = [System.Collections.Generic.List[object]]::new()
$skipped = 0
foreach ($file in Get-ChildItem $cheatsRoot -Filter "*.cht" | Sort-Object Name) {
    $key = Get-TitleKey $file.BaseName
    [string[]]$serials = @(Resolve-Serials $key)
    if ($serials.Count -eq 0) { $skipped++; continue }

    $values = @{}
    foreach ($line in Get-Content $file.FullName) {
        if ($line -match '^\s*cheat(\d+)_([a-z_]+)\s*=\s*"(.*)"\s*$') {
            $slot = $Matches[1]
            if (-not $values.ContainsKey($slot)) { $values[$slot] = @{} }
            $values[$slot][$Matches[2]] = $Matches[3]
        }
    }

    $blocks = [System.Collections.Generic.List[object]]::new()
    foreach ($slot in ($values.Keys | Sort-Object { [int]$_ })) {
        $cheat = $values[$slot]
        if ($cheat["cheat_type"] -ne "1") { continue }
        if ($cheat["code"]) { continue }
        if ($cheat["repeat_count"] -and [int]$cheat["repeat_count"] -gt 1) { continue }
        $desc = $cheat["desc"]
        if (-not $desc) { continue }
        if ($desc -match "Enable Code") { continue }
        $size = 4
        if ($cheat["memory_search_size"]) { $size = [int]$cheat["memory_search_size"] }
        if ($size -lt 3 -or $size -gt 5) { continue }
        $address = 0
        $value = 0
        if (-not [int64]::TryParse($cheat["address"], [ref]$address)) { continue }
        if (-not [int64]::TryParse($cheat["value"], [ref]$value)) { continue }
        $type = $size - 3
        $code = "{0:X2}{1:X6} {2:X8}" -f $type, ($address -band 0xFFFFFF), ($value -band 0xFFFFFFFF)
        $blocks.Add([pscustomobject]@{ Desc = $desc; Code = $code })
    }
    if ($blocks.Count -eq 0) { $skipped++; continue }

    $serial = [string]$serials[0]
    $slug = ([regex]::Replace($file.BaseName.ToLowerInvariant(), "[^a-z0-9]+", "-")).Trim("-")
    if (-not $slug) { $slug = "pack" }
    $safeSerial = $serial -replace "[^A-Za-z0-9-]", "_"
    $fileName = "$safeSerial-$slug.txt"
    $target = Join-Path $packDir $fileName
    $builder = [System.Text.StringBuilder]::new()
    foreach ($block in $blocks) {
        [void]$builder.Append("// ").Append($block.Desc).Append("`n")
        [void]$builder.Append($block.Code).Append("`n")
    }
    [System.IO.File]::WriteAllText($target, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))

    $entries.Add([pscustomobject]@{
        id = "$catalogIdPrefix-$($safeSerial.ToLowerInvariant())-$slug"
        title = $file.BaseName
        serials = @($serials)
        authors = @("libretro-database contributors and the original Dreamcast cheat authors")
        description = "$($blocks.Count) libretro Dreamcast cheat blocks for $($serials -join ', ')."
        downloadUrl = "https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/files/libretro-dreamcast/$fileName"
        packPath = "files/libretro-dreamcast/$fileName"
        sourceUrl = "https://github.com/libretro/libretro-database/blob/$commit/cht/Sega%20-%20Dreamcast/$([uri]::EscapeDataString($file.Name))"
        sourceName = "libretro-database Dreamcast cheats"
        license = "CC-BY-SA-4.0 repository license; individual upstream code authors remain credited"
        blockCount = $blocks.Count
        updatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    })
}

$catalog = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    entries = $entries
}
$json = $catalog | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $RepositoryRoot "cheats.json"), $json, [System.Text.UTF8Encoding]::new($false))

"packs: $($entries.Count), skipped: $skipped, serials: $((($entries | ForEach-Object { $_.serials }).Count))"
