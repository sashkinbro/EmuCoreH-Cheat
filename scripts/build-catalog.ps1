param(
    [string]$DatabaseRoot = "E:\TMP\libretro-database",
    [string]$MameCheatRoot = "C:\windows\Temp\opencode\mame-cheats\xml264",
    [string]$ArcadeCatalogFile = "C:\Users\SBRO\AndroidStudioProjects\EmuCoreH\app\src\main\assets\catalog\arcade_games.json",
    [string]$BucaneroRoot = "E:\TMP\dreamcast-cheats",
    [string]$GshiRoot = "E:\TMP\gshi-dreamcast",
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$cheatsRoot = Join-Path $DatabaseRoot "cht\Sega - Dreamcast"
$datFile = Join-Path $DatabaseRoot "metadat\redump\Sega - Dreamcast.dat"
$libretroPackDir = Join-Path $RepositoryRoot "files\libretro-dreamcast"
$mamePackDir = Join-Path $RepositoryRoot "files\mame-arcade"
$bucaneroPackDir = Join-Path $RepositoryRoot "files\bucanero-dreamcast"
$gshiPackDir = Join-Path $RepositoryRoot "files\gshi-dreamcast"
$commit = (git -C $DatabaseRoot rev-parse HEAD).Trim()

# ---------------------------------------------------------------------------
# Title helpers
# ---------------------------------------------------------------------------

$stopTokens = @("the", "of", "a", "an", "and", "vol", "volume")
$romanTokens = @{
    "i" = "1"; "ii" = "2"; "iii" = "3"; "iv" = "4"; "v" = "5"; "vi" = "6";
    "vii" = "7"; "viii" = "8"; "ix" = "9"; "x" = "10"; "xi" = "11"; "xii" = "12"
}

function Get-TitleKey([string]$value) {
    $text = $value.ToLowerInvariant()
    $text = [regex]::Replace($text, "\([^)]*\)", " ")
    $text = [regex]::Replace($text, "[^a-z0-9]+", "")
    return $text
}

function Get-Tokens([string]$value) {
    $text = $value.ToLowerInvariant()
    $text = [regex]::Replace($text, "\([^)]*\)", " ")
    # Revision suffixes must not create fake tokens (Ready 2 Rumble Version 1.0).
    $text = [regex]::Replace($text, "\bversion\s*\d+(?:[.,]\d+)*\b", " ")
    $text = [regex]::Replace($text, "\bv\d+(?:[.,]\d+)*\b", " ")
    $text = [regex]::Replace($text, "[^a-z0-9]+", " ")
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($token in $text.Split(" ")) {
        if (-not $token -or $token -in $stopTokens) { continue }
        $mapped = if ($romanTokens.ContainsKey($token)) { $romanTokens[$token] } else { $token }
        if ($mapped -match "^\d{4}$" -and ($mapped.StartsWith("19") -or $mapped.StartsWith("20"))) {
            $mapped = $mapped.Substring(2)
        }
        if (-not $tokens.Contains($mapped)) { $tokens.Add($mapped) }
    }
    return $tokens
}

# One substitution is tolerated so upstream typos (Dalmations) still match.
function Test-TokenEqual([string]$a, [string]$b) {
    if ($a -eq $b) { return $true }
    if ($a.Length -ne $b.Length -or $a.Length -lt 5) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $a.Length; $i++) {
        if ($a[$i] -ne $b[$i]) {
            $diff++
            if ($diff -gt 1) { return $false }
        }
    }
    return $true
}

function Get-SharedTokens($tokens, $otherTokens) {
    $shared = [System.Collections.Generic.List[string]]::new()
    foreach ($token in $tokens) {
        foreach ($candidate in $otherTokens) {
            if (Test-TokenEqual $token $candidate) {
                $shared.Add($token)
                break
            }
        }
    }
    return $shared
}

function Get-NumericTokens($tokens) {
    return @($tokens | Where-Object { $_ -match "^\d+$" } | Sort-Object)
}

function Get-RegionRank([string]$region) {
    switch -Regex ($region) {
        "USA|World" { return 0 }
        "Europe" { return 1 }
        "Japan" { return 2 }
        default { return 3 }
    }
}

function Add-Serial($serials, $value) {
    foreach ($serial in $value) {
        if ($serial -and -not $serials.Contains($serial)) { $serials.Add($serial) }
    }
}

# ---------------------------------------------------------------------------
# Dreamcast metadata DAT
# ---------------------------------------------------------------------------

function Convert-ToCatalogSerial([string]$raw) {
    $value = $raw.Trim().ToUpperInvariant()
    if ($value -match "^\d{5}$") {
        # Redump stores Sega first-party codes without the MK- prefix (51036).
        return "MK-$value"
    }
    if ($value -match "^\d{3}-\d{4}$") {
        # Sega internal promo numbers (610-7118) belong to demo discs.
        return $null
    }
    foreach ($match in [regex]::Matches($value, "[A-Z0-9]{1,4}-[0-9]{3,5}[A-Z]?")) {
        $token = $match.Value
        if ($token.Split("-")[0] -match "[A-Z]") { return $token }
    }
    return $null
}

$script:datGames = [System.Collections.Generic.List[object]]::new()
$script:gamesByKey = @{}
$currentName = $null
$currentRegion = ""
$currentSerials = [System.Collections.Generic.List[string]]::new()

function Add-DatGame {
    if (-not $currentName) { return }
    $serials = [System.Collections.Generic.List[string]]::new()
    foreach ($serial in $currentSerials) {
        if (-not $serials.Contains($serial)) { $serials.Add($serial) }
    }
    $key = Get-TitleKey $currentName
    $game = [pscustomobject]@{
        Name = $currentName
        Key = $key
        Region = $currentRegion
        Serials = $serials
        Tokens = (Get-Tokens $currentName)
    }
    $script:datGames.Add($game)
    if (-not $script:gamesByKey.ContainsKey($key)) {
        $script:gamesByKey[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $script:gamesByKey[$key].Add($game)
}

foreach ($line in Get-Content $datFile) {
    if ($line -match '^\s*name\s+"(.+)"\s*$') {
Add-DatGame

# Manual serials for titles the Redump DAT names differently.
$script:manualSerials = @{
    "eldoradogatevol1" = @("T-1223M")
    "eldoradogatevol3" = @("T-1225M")
    "castleofshikigami2" = @("T-47701M", "T-47702M")
    "specopsomegasquad" = @("T-41704N")
    "floiganbrothers" = @("MK-51114")
    "radilgy" = @("T-47802M")
    "giantgramalljapan" = @("HDR-0005")
    "giantgram2000" = @("HDR-0101")
}
        $currentName = $Matches[1]
        $currentRegion = ""
        $currentSerials = [System.Collections.Generic.List[string]]::new()
        continue
    }
    if ($line -match '^\s*region\s+"(.+)"\s*$') { $currentRegion = $Matches[1]; continue }
    if ($line -match '^\s*serial\s+"(.+)"\s*$') {
        $serial = Convert-ToCatalogSerial $Matches[1]
        if ($serial) { $currentSerials.Add($serial) }
        continue
    }
}
Add-DatGame

# Prefix matching is what the published catalog was built with. It is kept so
# existing pack file names and serial lists stay stable.
function Resolve-Serials-ByPrefix([string]$key) {
    $serials = [System.Collections.Generic.List[string]]::new()
    if ($key.Length -lt 4) { return $serials.ToArray() }
    $fallback = [System.Collections.Generic.List[object]]::new()
    foreach ($game in $script:datGames) {
        if ($game.Key.Length -lt 4) { continue }
        if ($game.Key.StartsWith($key) -or $key.StartsWith($game.Key)) {
            $fallback.Add($game)
        }
    }
    if ($fallback.Count -eq 0) { return $serials.ToArray() }
    $regionMatches = @($fallback | Where-Object { $_.Region -match "USA|World" -and $_.Serials.Count -gt 0 })
    if ($regionMatches.Count -gt 0) {
        foreach ($game in $regionMatches) { Add-Serial $serials $game.Serials }
        return $serials.ToArray()
    }
    foreach ($game in $fallback) { Add-Serial $serials $game.Serials }
    return $serials.ToArray()
}

function Resolve-Serials-ByTokens([string]$chtTitle, [string]$regionHint = $null) {
    $tokens = Get-Tokens $chtTitle
    $serials = [System.Collections.Generic.List[string]]::new()
    if ($tokens.Count -lt 2) { return $serials.ToArray() }

    $numeric = Get-NumericTokens $tokens
    $scored = [System.Collections.Generic.List[object]]::new()
    foreach ($game in $script:datGames) {
        $shared = Get-SharedTokens $tokens $game.Tokens
        if ($shared.Count -lt 2) { continue }
        $gameNumeric = Get-NumericTokens $game.Tokens
        if ($gameNumeric.Count -ne $numeric.Count) { continue }
        if ($gameNumeric -join "," -ne ($numeric -join ",")) { continue }
        $allShared = $shared.Count -eq $tokens.Count
        $extra = $game.Tokens.Count - $shared.Count
        $score = 0
        if ($allShared -and $extra -eq 0) { $score = 100 }
        elseif ($allShared) { $score = 60 }
        elseif ($shared.Count -ge 3 -and ($tokens.Count - $shared.Count) -le 1 -and $extra -le 2) { $score = 40 }
        else { continue }
        if ($regionHint) {
            $matchesHint = switch ($regionHint) {
                "USA" { $game.Region -match "USA|World" }
                "Europe" { $game.Region -match "Europe" }
                "Japan" { $game.Region -match "Japan" }
                default { $false }
            }
            if ($matchesHint) { $score += 4 }
        }
        if ($game.Region -match "USA|World") { $score += 2 }
        if ($game.Serials.Count -eq 0) { $score -= 1 }
        $scored.Add([pscustomobject]@{ Game = $game; Score = $score })
    }
    if ($scored.Count -eq 0) { return $serials.ToArray() }

    $bestScore = ($scored | Sort-Object -Property @{ Expression = "Score"; Descending = $true } | Select-Object -First 1).Score
    $bestGames = @($scored | Where-Object { $_.Score -eq $bestScore } | ForEach-Object { $_.Game })
    $ordered = $bestGames | Sort-Object -Property @{ Expression = { Get-RegionRank $_.Region } }, @{ Expression = "Name" }
    foreach ($game in $ordered) { Add-Serial $serials $game.Serials }
    return $serials.ToArray()
}

function Resolve-Serials([string]$chtTitle, [string]$regionHint = $null) {
    $key = Get-TitleKey $chtTitle
    $serials = [System.Collections.Generic.List[string]]::new()

    # Titles whose upstream name never matched the Redump DAT entry.
    foreach ($alias in $script:manualSerials.Keys) {
        if ($key.StartsWith($alias)) {
            Add-Serial $serials $script:manualSerials[$alias]
        }
    }
    if ($serials.Count -gt 0) { return $serials.ToArray() }

    if ($script:gamesByKey.ContainsKey($key)) {
        foreach ($game in $script:gamesByKey[$key]) { Add-Serial $serials $game.Serials }
    }
    if ($serials.Count -gt 0) { return $serials.ToArray() }

    Add-Serial $serials (Resolve-Serials-ByPrefix $key)
    Add-Serial $serials (Resolve-Serials-ByTokens $chtTitle $regionHint)
    return $serials.ToArray()
}

# ---------------------------------------------------------------------------
# Dreamcast packs
# ---------------------------------------------------------------------------

# Serial lists published by the previous catalog are merged in first, so pack
# file names and per-disc coverage never regress between rebuilds. The map is
# case-sensitive: "Dead Or Alive 2" (Dreamcast) and "Dead or Alive 2" (arcade)
# are different entries.
$previousByTitle = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$previousCatalogFile = Join-Path $RepositoryRoot "cheats.json"
if (Test-Path $previousCatalogFile) {
    try {
        $previousEntries = (Get-Content $previousCatalogFile -Raw | ConvertFrom-Json).entries
        foreach ($entry in $previousEntries) {
            if ($entry.title) { $previousByTitle[$entry.title] = @($entry.serials) }
        }
    } catch { }
}

New-Item -ItemType Directory -Force -Path $libretroPackDir | Out-Null
Get-ChildItem $libretroPackDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

$entries = [System.Collections.Generic.List[object]]::new()
$skipped = 0
$dreamcastPacks = 0
foreach ($file in Get-ChildItem $cheatsRoot -Filter "*.cht" | Sort-Object Name) {
    [string[]]$serials = @(Resolve-Serials $file.BaseName)
    if ($serials.Count -eq 0) { $skipped++; continue }
    if ($previousByTitle.ContainsKey($file.BaseName)) {
        $merged = [System.Collections.Generic.List[string]]::new()
        foreach ($serial in $previousByTitle[$file.BaseName]) {
            # Only disc product codes are carried over: a rebuild must never
            # leak serials that belong to another source (for example an
            # arcade romset name) into a Dreamcast pack.
            if ($serial -and [regex]::IsMatch([string]$serial, "^[A-Z0-9]{1,4}-[0-9]{3,5}[A-Z]?$") -and
                -not $merged.Contains($serial)) {
                $merged.Add($serial)
            }
        }
        foreach ($serial in $serials) {
            if ($serial -and -not $merged.Contains($serial)) { $merged.Add($serial) }
        }
        $serials = $merged.ToArray()
    }

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
    $target = Join-Path $libretroPackDir $fileName
    $builder = [System.Text.StringBuilder]::new()
    foreach ($block in $blocks) {
        [void]$builder.Append("// ").Append($block.Desc).Append("`n")
        [void]$builder.Append($block.Code).Append("`n")
    }
    [System.IO.File]::WriteAllText($target, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))

    $entries.Add([pscustomobject]@{
        id = "libretro-dreamcast-$($safeSerial.ToLowerInvariant())-$slug"
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
    $dreamcastPacks++
}

# ---------------------------------------------------------------------------
# Community Dreamcast packs (markdown sources: bucanero, GameHacking.org)
# ---------------------------------------------------------------------------

$coveredSerials = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $entries) {
    foreach ($serial in $entry.serials) { [void]$coveredSerials.Add([string]$serial) }
}
$script:mdSkipped = [System.Collections.Generic.List[string]]::new()

function Add-MdCheatSource {
    param($Source)

    New-Item -ItemType Directory -Force -Path $Source.PackDir | Out-Null
    Get-ChildItem $Source.PackDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    foreach ($name in @("Packs", "Blocks", "NoBlocks", "NoSerials", "Covered")) {
        $Source | Add-Member -NotePropertyName $name -NotePropertyValue 0 -Force
    }
    if (-not (Test-Path $Source.Root)) { return }

    foreach ($file in Get-ChildItem $Source.Root -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name) {
        $lines = @()
        try { $lines = Get-Content -LiteralPath $file.FullName -ErrorAction Stop } catch { $script:mdSkipped.Add("$($Source.IdPrefix) read-error: $($file.Name)"); continue }
        $title = $null
        foreach ($line in $lines) {
            if ($line -match '^#\s+(.+?)\s*$') { $title = $Matches[1]; break }
        }
        if (-not $title) { continue }

        $regionHint = $null
        $lowerName = $file.Name.ToLowerInvariant()
        if ($lowerName -match "\(usa\)") { $regionHint = "USA" }
        elseif ($lowerName -match "\(pal\)") { $regionHint = "Europe" }
        elseif ($lowerName -match "\(jap\)") { $regionHint = "Japan" }

        $blocks = [System.Collections.Generic.List[object]]::new()
        $blockDesc = $null
        $inFence = $false
        $codes = [System.Collections.Generic.List[string]]::new()
        $pending8 = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            if ($line -match '^##\s+(.+?)\s*$') {
                $blockDesc = $Matches[1]
                $codes = [System.Collections.Generic.List[string]]::new()
                $pending8 = [System.Collections.Generic.List[string]]::new()
                $inFence = $false
                continue
            }
            if ($line -match '^```') {
                if (-not $inFence) {
                    $inFence = $true
                } else {
                    $inFence = $false
                    # Address/value halves that ended up on separate lines.
                    for ($i = 0; $i + 1 -lt $pending8.Count; $i += 2) {
                        $codes.Add($pending8[$i] + " " + $pending8[$i + 1])
                    }
                    if ($blockDesc -and $codes.Count -gt 0) {
                        $blocks.Add([pscustomobject]@{ Desc = $blockDesc; Codes = $codes })
                    }
                    $blockDesc = $null
                    $codes = [System.Collections.Generic.List[string]]::new()
                    $pending8 = [System.Collections.Generic.List[string]]::new()
                }
                continue
            }
            if ($inFence -and $blockDesc) {
                # Some source files glued the description to the code line or
                # split a pair over two lines, so hex tokens are collected
                # wherever they appear and paired in order.
                foreach ($match in [regex]::Matches($line.ToUpperInvariant(), '(?<![0-9A-F])[0-9A-F]{8,16}(?![0-9A-F])')) {
                    $token = $match.Value
                    if ($token.Length -eq 16) {
                        $codes.Add($token.Substring(0, 8) + " " + $token.Substring(8))
                    } elseif ($token.Length -eq 8) {
                        $pending8.Add($token)
                    }
                }
            }
        }

        # Master codes only set up the cheat device; the core decrypts Action
        # Replay codes itself, so they add nothing here.
        $usable = @($blocks | Where-Object {
                $_.Desc -notmatch '^\s*(\[M\]|\(M\))' -and
                $_.Desc -notmatch 'Enable Code' -and
                $_.Desc -notmatch 'Must Be On'
            })
        if ($usable.Count -eq 0) { $Source.NoBlocks++; $script:mdSkipped.Add("$($Source.IdPrefix) no-blocks: $($file.BaseName)"); continue }

        [string[]]$serials = @(Resolve-Serials $title $regionHint)
        $newSerials = @($serials | Where-Object { $_ })
        if ($Source.SkipCovered) {
            $newSerials = @($newSerials | Where-Object { -not $coveredSerials.Contains([string]$_) })
        }
        if ($newSerials.Count -eq 0) {
            if ($serials.Count -eq 0) { $Source.NoSerials++; $script:mdSkipped.Add("$($Source.IdPrefix) no-serials: $($file.BaseName)") }
            else { $Source.Covered++ }
            continue
        }
        if (-not $Source.SkipCovered -and @($serials | Where-Object { $_ -and $coveredSerials.Contains([string]$_) }).Count -gt 0) {
            $Source.Covered++
        }

        $primary = [string]$newSerials[0]
        $slug = ([regex]::Replace($file.BaseName.ToLowerInvariant(), "[^a-z0-9]+", "-")).Trim("-")
        $safeSerial = $primary -replace "[^A-Za-z0-9-]", "_"
        $fileName = "$safeSerial-$slug.txt"
        $target = Join-Path $Source.PackDir $fileName
        $builder = [System.Text.StringBuilder]::new()
        foreach ($block in $usable) {
            [void]$builder.Append("// ").Append($block.Desc).Append("`n")
            foreach ($code in $block.Codes) { [void]$builder.Append($code).Append("`n") }
        }
        [System.IO.File]::WriteAllText($target, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
        $Source.Packs++
        $Source.Blocks += $usable.Count
        foreach ($serial in $newSerials) { [void]$coveredSerials.Add([string]$serial) }

        $entries.Add([pscustomobject]@{
            id = "$($Source.IdPrefix)-$($safeSerial.ToLowerInvariant())-$slug"
            title = $title
            serials = @($newSerials)
            authors = @($Source.Authors)
            description = "$($usable.Count) cheat blocks from $($Source.SourceName)."
            downloadUrl = "https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/$($Source.PackPath)/$fileName"
            packPath = "$($Source.PackPath)/$fileName"
            sourceUrl = $Source.SourceUrl
            sourceName = $Source.SourceName
            license = $Source.License
            blockCount = $usable.Count
            updatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        })
    }
}

$mdSources = @(
    [pscustomobject]@{
        Root = $BucaneroRoot
        PackDir = $bucaneroPackDir
        PackPath = "files/bucanero-dreamcast"
        IdPrefix = "bucanero-dreamcast"
        SkipCovered = $true
        Authors = "Dreamcast Cheat Database contributors (bucanero)"
        Description = "Action Replay cheat blocks from bucanero's Dreamcast cheat database."
        SourceUrl = "https://github.com/bucanero/dreamcast-cheats"
        SourceName = "Dreamcast Cheat Database (bucanero)"
        License = "GPL-3.0 - bucanero/dreamcast-cheats"
    },
    [pscustomobject]@{
        Root = $GshiRoot
        PackDir = $gshiPackDir
        PackPath = "files/gshi-dreamcast"
        IdPrefix = "gshi-dreamcast"
        SkipCovered = $false
        Authors = "GameHacking.org contributors"
        Description = "cheat blocks from the GameHacking.org Dreamcast database."
        SourceUrl = "https://gamehacking.org/system/dc"
        SourceName = "GameHacking.org Dreamcast cheats"
        License = "GameHacking.org community codes; individual hackers credited on the site"
    }
)
foreach ($source in $mdSources) { Add-MdCheatSource $source }

# ---------------------------------------------------------------------------
# MAME arcade packs
# ---------------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $mamePackDir | Out-Null
Get-ChildItem $mamePackDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

$arcadePorts = 0
$arcadeCheats = 0
if (Test-Path $ArcadeCatalogFile) {
    $arcadeCatalog = Get-Content $ArcadeCatalogFile -Raw | ConvertFrom-Json
    foreach ($property in $arcadeCatalog.games.PSObject.Properties) {
        $romset = $property.Name
        $title = [string]$property.Value.title
        if (-not $title) { $title = $romset }
        $xmlFile = Join-Path $MameCheatRoot "$romset.xml"
        if (-not (Test-Path $xmlFile)) { continue }

        $xml = $null
        try { $xml = [xml](Get-Content $xmlFile -Raw) } catch { continue }
        if (-not $xml.mamecheat -or -not $xml.mamecheat.cheat) { continue }

        $blocks = [System.Collections.Generic.List[object]]::new()
        foreach ($cheat in $xml.mamecheat.cheat) {
            $desc = ([string]$cheat.desc).Trim()
            if (-not $desc) { continue }
            if ($cheat.condition) { continue }
            $runScript = $cheat.script | Where-Object { $_.state -eq "run" }
            if (-not $runScript) { continue }
            $codes = [System.Collections.Generic.List[string]]::new()
            foreach ($action in $runScript.action) {
                $text = ([string]$action).Trim()
                if ($text -notmatch '^maincpu\.(p?[bwd])@([0-9A-Fa-f]+)=([0-9A-Fa-f]+)$') { continue }
                $access = $Matches[1]
                try {
                    $address = [System.Convert]::ToUInt32($Matches[2], 16)
                    $value = [System.Convert]::ToUInt32($Matches[3], 16)
                } catch { continue }
                # The cheat API writes to SH4 main RAM only.
                if (($address -band 0xFF000000) -ne 0x0C000000 -and ($address -band 0xFF000000) -ne 0x8C000000) { continue }
                $type = switch ($access) {
                    "b" { 0 }
                    "pb" { 0 }
                    "w" { 1 }
                    "pw" { 1 }
                    "d" { 2 }
                    "pd" { 2 }
                    default { -1 }
                }
                if ($type -lt 0) { continue }
                $codes.Add(("{0:X2}{1:X6} {2:X8}" -f $type, ($address -band 0xFFFFFF), ($value -band 0xFFFFFFFF)))
            }
            if ($codes.Count -eq 0) { continue }
            $blocks.Add([pscustomobject]@{ Desc = $desc; Codes = $codes })
        }
        if ($blocks.Count -eq 0) { continue }

        $fileName = "$romset.txt"
        $target = Join-Path $mamePackDir $fileName
        $builder = [System.Text.StringBuilder]::new()
        foreach ($block in $blocks) {
            [void]$builder.Append("// ").Append($block.Desc).Append("`n")
            foreach ($code in $block.Codes) { [void]$builder.Append($code).Append("`n") }
        }
        [System.IO.File]::WriteAllText($target, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
        $arcadePorts++
        $arcadeCheats += ($blocks | ForEach-Object { $_.Codes.Count } | Measure-Object -Sum).Sum

        $entries.Add([pscustomobject]@{
            id = "mame-arcade-$romset"
            title = $title
            serials = @($romset)
            authors = @("MAME cheat collection contributors (Pugsy and others)")
            description = "$($blocks.Count) arcade cheat blocks for the $romset romset."
            downloadUrl = "https://raw.githubusercontent.com/sashkinbro/EmuCoreH-Cheat/main/files/mame-arcade/$fileName"
            packPath = "files/mame-arcade/$fileName"
            sourceUrl = "https://www.mamecheat.co.uk/"
            sourceName = "MAME cheat collection (Pugsy's XML cheats, MAME 0.264)"
            license = "MAME cheat XML collection by Pugsy and contributors; only plain main RAM writes are converted"
            blockCount = $blocks.Count
            updatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        })
    }
}

$ordered = $entries | Sort-Object -Property @{ Expression = { $_.title.ToLowerInvariant() } }, @{ Expression = "id" }
$catalog = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    entries = @($ordered)
}
$json = $catalog | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $RepositoryRoot "cheats.json"), $json, [System.Text.UTF8Encoding]::new($false))

$mdSummary = ($mdSources | ForEach-Object {
        "$($_.IdPrefix): $($_.Packs) packs (blocks: $($_.Blocks), covered: $($_.Covered), no-blocks: $($_.NoBlocks), no-serials: $($_.NoSerials))"
    }) -join ", "
"dreamcast packs: $dreamcastPacks, skipped: $skipped, $mdSummary, arcade packs: $arcadePorts (arcade blocks: $arcadeCheats)"
$script:mdSkipped | Set-Content -LiteralPath (Join-Path $env:TEMP "md-skipped.txt") -Encoding UTF8
