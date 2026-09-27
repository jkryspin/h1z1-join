# Join the h1z1.kryspin.dev H1Z1 (Just Survive 2016) server.
#
#   irm https://raw.githubusercontent.com/jkryspin/h1z1-join/main/join.ps1 | iex
#
# Re-running is safe: it remembers your name and game folder.
# Optional env vars: H1Z1_NAME, H1Z1_GAME_DIR, H1Z1_NO_LAUNCH=1, H1Z1_SKIP_PREREQS=1

# Everything runs in a child scope so `iex` doesn't leak settings into the caller's session.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $ServerHost = 'h1z1.kryspin.dev'
    $LoginPort = 1115
    $ZonePort = 1117
    $LauncherRepo = 'H1emu/h1emu-launcher'
    $StateDir = Join-Path $env:LOCALAPPDATA 'h1z1-kryspin'
    $StateFile = Join-Path $StateDir 'state.json'

    function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }
    function Step([string]$msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
    function Ok([string]$msg) { Write-Host "    [ok] $msg" -ForegroundColor Green }
    function Warn([string]$msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

    function Load-State {
        if (Test-Path $StateFile) {
            try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
        }
        return [pscustomobject]@{ name = $null; gameDir = $null }
    }
    function Save-State($s) {
        New-Item -ItemType Directory -Force $StateDir | Out-Null
        $s | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
    }

    # Sends an SOE SessionRequest and waits for a SessionReply.
    function Test-SoeServer([string]$h, [int]$port, [string]$proto) {
        $be = { param([uint32]$v) $b = [BitConverter]::GetBytes($v); [Array]::Reverse($b); $b }
        $pkt = [byte[]](0x00, 0x01) + (& $be 3) + (& $be (Get-Random -Maximum 2147483647)) + (& $be 512) +
               [Text.Encoding]::ASCII.GetBytes($proto) + [byte[]](0)
        $udp = New-Object Net.Sockets.UdpClient
        try {
            $udp.Client.ReceiveTimeout = 4000
            $udp.Connect($h, $port)
            [void]$udp.Send($pkt, $pkt.Length)
            $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
            $r = $udp.Receive([ref]$ep)
            return ($r.Length -ge 2 -and $r[1] -eq 0x02)
        } catch { return $false } finally { $udp.Close() }
    }

    function Get-SteamLibraries {
        $roots = @()
        foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
            try {
                $p = Get-ItemProperty $k -ErrorAction Stop
                foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $roots += ($v -replace '/', '\') } }
            } catch {}
        }
        $libs = @()
        foreach ($r in ($roots | Select-Object -Unique)) {
            $libs += $r
            $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) {
                foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $libs += ($m.Groups[1].Value -replace '\\\\', '\')
                }
            }
        }
        return $libs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    }

    function Find-GameDirs {
        $candidates = @()
        foreach ($lib in Get-SteamLibraries) { $candidates += Join-Path $lib 'steamapps\common' }
        $candidates += @(
            (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Desktop'),
            (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Games'),
            $env:APPDATA, $env:LOCALAPPDATA, 'C:\Games', 'D:\Games', 'D:\', 'E:\Games'
        )
        $found = @()
        foreach ($c in ($candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
            $found += Get-ChildItem -Path $c -Filter 'H1Z1.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                      ForEach-Object { $_.DirectoryName }
        }
        return $found | Select-Object -Unique
    }

    function Install-Prereqs {
        $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        $installed = (Get-ItemProperty $keys -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName }) -join "`n"
        $need = @(
            @{ id = 'Microsoft.VCRedist.2010.x64'; has = $installed -match 'Visual C\+\+ 2010\s+x64 Redistributable' },
            @{ id = 'Microsoft.VCRedist.2010.x86'; has = $installed -match 'Visual C\+\+ 2010\s+x86 Redistributable' },
            @{ id = 'Microsoft.VCRedist.2015+.x64'; has = $installed -match 'Visual C\+\+ (v14|2015-20\d\d|20(15|17|19|22)) .*(x64|X64)' },
            @{ id = 'Microsoft.VCRedist.2015+.x86'; has = $installed -match 'Visual C\+\+ (v14|2015-20\d\d|20(15|17|19|22)) .*(x86|X86)' },
            @{ id = 'Microsoft.DirectX'; has = (Test-Path "$env:WINDIR\System32\d3dx9_43.dll") -and (Test-Path "$env:WINDIR\SysWOW64\d3dx9_43.dll") }
        )
        $missing = $need | Where-Object { -not $_.has }
        if (-not $missing) { Ok 'VC++ 2010 / 2015+ runtimes and DirectX (June 2010) already installed'; return }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Warn 'winget not found. Install these manually: VC++ 2010 x86+x64, VC++ 2015-2022 x86+x64, DirectX June 2010 runtime.'
            return
        }
        foreach ($m in $missing) {
            Say "    installing $($m.id) (accept the Windows admin prompt if one appears)..."
            winget install --id $m.id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok $m.id } else { Warn "$($m.id) install returned code $LASTEXITCODE (may already be installed; continuing)" }
        }
    }

    function Get-Launcher {
        Step 'Getting the H1Emu launcher (downloads the 2016 game files with your Steam account)'
        $rel = Invoke-RestMethod "https://api.github.com/repos/$LauncherRepo/releases/latest" -Headers @{ 'User-Agent' = 'h1z1-join' }
        $asset = $rel.assets | Where-Object { $_.name -like '*Setup*.exe' } | Select-Object -First 1
        $dest = Join-Path $StateDir $asset.name
        New-Item -ItemType Directory -Force $StateDir | Out-Null
        if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $asset.size) {
            Say "    downloading $($asset.name) $($rel.tag_name) ($([math]::Round($asset.size / 1MB)) MB)..."
            Invoke-WebRequest $asset.browser_download_url -OutFile $dest -UseBasicParsing
        }
        Ok "launcher saved to $dest"
        return $dest
    }

    function Set-ClientConfig([string]$dir, [string]$name) {
        $ini = Join-Path $dir 'ClientConfig.ini'
        $server = "${ServerHost}:$LoginPort"
        $lines = @()
        if (Test-Path $ini) {
            $bak = "$ini.bak"
            if (-not (Test-Path $bak)) { Copy-Item $ini $bak }
            $lines = @(Get-Content $ini | Where-Object { $_ -notmatch '^\s*sessionid\s*=' })
        }
        $hasServer = $false
        $lines = @($lines | ForEach-Object {
            if ($_ -match '^\s*Server\s*=') { $hasServer = $true; "Server=$server" } else { $_ }
        })
        if (-not $hasServer) { $lines += "Server=$server" }
        $out = @("sessionid=$name") + $lines
        [IO.File]::WriteAllLines($ini, [string[]]$out, (New-Object Text.UTF8Encoding($false)))
        Ok "ClientConfig.ini -> sessionid=$name, Server=$server"
    }

    function New-PlayShortcut([string]$dir, [string]$name) {
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'H1Z1 (kryspin).lnk'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $dir 'H1Z1.exe'
        $sc.Arguments = "sessionid=$name server=${ServerHost}:$LoginPort"
        $sc.WorkingDirectory = $dir
        $sc.Save()
        Ok "desktop shortcut: $lnk"
    }

    Write-Host ''
    Write-Host '  H1Z1 Just Survive  ->  h1z1.kryspin.dev' -ForegroundColor Magenta
    Write-Host '  ---------------------------------------' -ForegroundColor Magenta

    $state = Load-State

    # 1. Name / account
    Step 'Your player id'
    $name = if ($env:H1Z1_NAME) { $env:H1Z1_NAME } else { $state.name }
    if (-not $name) {
        Say '    This is your account on the server (no password). Pick something unique and keep it secret-ish;'
        Say '    anyone who uses the same id plays as you. Letters, numbers, - and _ only.'
        $name = Read-Host '    Player id'
    }
    $name = ($name -replace '[^A-Za-z0-9_-]', '')
    if ($name.Length -lt 3) { throw 'Player id must be at least 3 letters/numbers.' }
    $state.name = $name
    Save-State $state
    Ok "using id '$name'"

    # 2. Server reachable?
    Step "Checking the server at $ServerHost"
    $loginUp = Test-SoeServer $ServerHost $LoginPort 'LoginUdp_11'
    $zoneUp = Test-SoeServer $ServerHost $ZonePort 'ClientProtocol_1080'
    if ($loginUp) { Ok "login server answering (UDP $LoginPort)" } else { Warn "login server not answering on UDP $LoginPort - tell John" }
    if ($zoneUp) { Ok "game server answering (UDP $ZonePort)" } else { Warn "game server not answering on UDP $ZonePort - tell John" }

    # 3. Runtimes
    Step 'Game runtimes'
    if ($env:H1Z1_SKIP_PREREQS -eq '1') { Say '    skipped (H1Z1_SKIP_PREREQS=1)' } else { Install-Prereqs }

    # 4. Game folder
    Step 'Finding your H1Z1 (2016) game folder'
    $gameDir = $null
    foreach ($d in @($env:H1Z1_GAME_DIR, $state.gameDir)) {
        if ($d -and (Test-Path (Join-Path $d 'H1Z1.exe'))) { $gameDir = $d; break }
    }
    if (-not $gameDir) {
        $found = @(Find-GameDirs)
        if ($found.Count -eq 1) { $gameDir = $found[0] }
        elseif ($found.Count -gt 1) {
            for ($i = 0; $i -lt $found.Count; $i++) { Say "    [$($i + 1)] $($found[$i])" }
            $pick = Read-Host '    Which one is the 2016 / Just Survive version? (number)'
            $gameDir = $found[[int]$pick - 1]
        }
    }
    if (-not $gameDir) {
        Warn 'No H1Z1.exe found yet.'
        $setup = Get-Launcher
        Say ''
        Say '    The H1Emu launcher will open. In it:' White
        Say '      1. Sign in with the Steam account that owns H1Z1.' White
        Say '      2. Download the 2016 (Just Survive) game version and note the folder.' White
        Say '      3. Come back here and paste that folder, or close this and re-run the same command later.' White
        Start-Process $setup
        $p = Read-Host '    Game folder (contains H1Z1.exe), or Enter to stop for now'
        if (-not $p) { Say ''; Say '    Re-run the same one-line command once the download finishes.' Yellow; return }
        $p = $p.Trim('"', ' ')
        if (-not (Test-Path (Join-Path $p 'H1Z1.exe'))) { throw "No H1Z1.exe in '$p'." }
        $gameDir = $p
    }
    $state.gameDir = $gameDir
    Save-State $state
    Ok "game folder: $gameDir"

    # 5. Point the client at the server
    Step 'Pointing the game at h1z1.kryspin.dev'
    Set-ClientConfig $gameDir $name
    New-PlayShortcut $gameDir $name

    # 6. Launch
    Step 'Done'
    Say "    Next time just double-click 'H1Z1 (kryspin)' on your desktop." White
    if ($env:H1Z1_NO_LAUNCH -eq '1') { Say '    (not launching: H1Z1_NO_LAUNCH=1)'; return }
    Say '    Launching H1Z1... pick the server in the list, make a character, have fun.' White
    Start-Process -FilePath (Join-Path $gameDir 'H1Z1.exe') -WorkingDirectory $gameDir -ArgumentList "sessionid=$name", "server=${ServerHost}:$LoginPort"
}
