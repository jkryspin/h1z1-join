# Join the h1z1.kryspin.dev H1Z1 (Just Survive, 22 Dec 2016) server.
#
#   irm https://raw.githubusercontent.com/jkryspin/h1z1-join/main/join.ps1 | iex
#
# Does everything: runtimes, downloads the 2016 game from Steam (you sign in once),
# applies the H1Emu patch, and launches the game pointed at the server.
# Re-running is safe and quick: it remembers your id, game folder and Steam login.
#
# Optional env vars: H1Z1_NAME, H1Z1_GAME_DIR, H1Z1_STEAM_USER, H1Z1_NO_LAUNCH=1,
#                    H1Z1_SKIP_PREREQS=1, H1Z1_SKIP_DOWNLOAD=1

# Everything runs in a child scope so `iex` doesn't leak settings into the caller's session.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $ServerHost = 'h1z1.kryspin.dev'
    $LoginPort = 1115
    $ZonePort = 1117
    # Same depot/manifest and exe checksum the H1Emu launcher uses for "Just Survive: 22nd December 2016".
    $SteamApp = 295110
    $SteamDepot = 295111
    $SteamManifest = '8395659676467739522'
    $GameCrc = 'bc5b3ab6'
    $PatchBase = 'https://raw.githubusercontent.com/H1emu/h1emu-launcher/HEAD/H1Emu%20Launcher/Resources'
    $AssetFeed = 'https://raw.githubusercontent.com/H1emu/asset-pack/refs/heads/main/feed.json'
    $CrashUrl = 'https://www.h1emu.com/game-error?code=G'
    $StateDir = Join-Path $env:LOCALAPPDATA 'h1z1-kryspin'
    $StateFile = Join-Path $StateDir 'state.json'
    $DefaultGameDir = Join-Path $env:SystemDrive 'Games\H1Z1 Just Survive 2016'

    function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }
    function Step([string]$msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
    function Ok([string]$msg) { Write-Host "    [ok] $msg" -ForegroundColor Green }
    function Warn([string]$msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

    function Load-State {
        if (Test-Path $StateFile) {
            try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
        }
        return [pscustomobject]@{ name = $null; gameDir = $null; steamUser = $null }
    }
    function Save-State($s) {
        New-Item -ItemType Directory -Force $StateDir | Out-Null
        $s | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
    }

    if (-not ('H1z1Join.Crc32' -as [type])) {
        Add-Type -TypeDefinition @'
namespace H1z1Join {
    public static class Crc32 {
        static readonly uint[] T = Make();
        static uint[] Make() {
            var t = new uint[256];
            for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; t[i] = c; }
            return t;
        }
        public static string OfFile(string path) {
            uint crc = 0xFFFFFFFFu; var buf = new byte[1 << 20]; int n;
            using (var fs = System.IO.File.OpenRead(path))
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                    for (int i = 0; i < n; i++) crc = T[(crc ^ buf[i]) & 0xFF] ^ (crc >> 8);
            return (crc ^ 0xFFFFFFFFu).ToString("x8");
        }
    }
}
'@
    }

    function Test-Game2016([string]$dir) {
        if (-not $dir) { return $false }
        $exe = Join-Path $dir 'H1Z1.exe'
        if (-not (Test-Path $exe)) { return $false }
        try { return [H1z1Join.Crc32]::OfFile($exe) -eq $GameCrc } catch { return $false }
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

    function Get-File([string]$url, [string]$dest) {
        $tmp = "$dest.part"
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers @{ 'User-Agent' = 'h1z1-join' }
        Move-Item -Force $tmp $dest
    }

    # Places the 2016 game might already be: a previous H1Emu launcher install, Steam libraries, common folders.
    function Find-ExistingGame {
        $dirs = @()
        $launcherCfg = Join-Path $env:APPDATA 'H1Emu Launcher\user.config'
        if (Test-Path $launcherCfg) {
            $m = [regex]::Match((Get-Content $launcherCfg -Raw), '<setting name="activeDirectory"[^>]*>\s*<value>([^<]+)</value>')
            if ($m.Success) { $dirs += $m.Groups[1].Value }
        }
        $dirs += $DefaultGameDir
        $roots = @()
        foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
            try { $p = Get-ItemProperty $k -ErrorAction Stop; foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $roots += ($v -replace '/', '\') } } } catch {}
        }
        foreach ($r in ($roots | Select-Object -Unique)) {
            $libs = @($r)
            $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') } }
            foreach ($l in $libs) {
                $common = Join-Path $l 'steamapps\common'
                if (Test-Path $common) { $dirs += (Get-ChildItem $common -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
            }
        }
        foreach ($c in @((Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Games'), 'C:\Games', 'D:\Games', 'E:\Games')) {
            if (Test-Path $c) { $dirs += (Get-ChildItem -Path $c -Filter 'H1Z1.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName }) }
        }
        foreach ($d in ($dirs | Where-Object { $_ } | Select-Object -Unique)) {
            if (Test-Game2016 $d) { return $d }
        }
        return $null
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

    function Get-DepotDownloader {
        $ddDir = Join-Path $StateDir 'DepotDownloader'
        $exe = Join-Path $ddDir 'DepotDownloader.exe'
        if (Test-Path $exe) { return $exe }
        $rel = Invoke-RestMethod 'https://api.github.com/repos/SteamRE/DepotDownloader/releases/latest' -Headers @{ 'User-Agent' = 'h1z1-join' }
        $asset = $rel.assets | Where-Object { $_.name -eq 'DepotDownloader-windows-x64.zip' } | Select-Object -First 1
        $zip = Join-Path $StateDir $asset.name
        New-Item -ItemType Directory -Force $ddDir | Out-Null
        Say "    fetching DepotDownloader $($rel.tag_name) (open-source Steam downloader by SteamRE)..."
        Get-File $asset.browser_download_url $zip
        Expand-Archive -Path $zip -DestinationPath $ddDir -Force
        Remove-Item $zip -Force
        return $exe
    }

    function Download-Game([string]$dir, $state) {
        $free = (Get-PSDrive -Name $dir.Substring(0, 1)).Free
        if ($free -lt 25GB) { Warn ("only {0:N0} GB free on {1} - the game needs about 20 GB." -f ($free / 1GB), $dir.Substring(0, 2)) }
        $dd = Get-DepotDownloader
        $user = if ($env:H1Z1_STEAM_USER) { $env:H1Z1_STEAM_USER } else { $state.steamUser }
        if (-not $user) {
            Say ''
            Say '    The 2016 game files come straight from Steam, so sign in with the Steam account' White
            Say '    that owns H1Z1 / H1Z1: Just Survive. Your password goes only to Steam.' White
            $user = Read-Host '    Steam username (or press Enter to sign in by scanning a QR code with the Steam app)'
        }
        $ddArgs = @('-app', $SteamApp, '-depot', $SteamDepot, '-manifest', $SteamManifest, '-dir', $dir, '-max-downloads', '16')
        if ($user) {
            $state.steamUser = $user; Save-State $state
            $ddArgs += @('-username', $user, '-remember-password')
        } else {
            $ddArgs += @('-qr')
        }
        Say '    Downloading (~20 GB). Enter your Steam password / Steam Guard code below when asked.' White
        Say '    If it gets interrupted, just run the command again - it resumes.' White
        Push-Location (Split-Path $dd)
        try { & $dd @ddArgs } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { Warn "DepotDownloader exited with code $LASTEXITCODE." }
        $cache = Join-Path $dir '.DepotDownloader'
        if (Test-Path $cache) { Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Mirrors what the H1Emu launcher does before every launch of the 2016 build.
    function Install-Patch([string]$dir) {
        $cache = Join-Path $StateDir 'patch'
        New-Item -ItemType Directory -Force $cache | Out-Null
        $files = 'Game_Patch_2016.zip', 'Sound_Banks.zip', 'Locales.zip', 'H1EmuVoiceClient.exe', 'H1Z1_BE.exe', 'H1Z1_FP.exe', 'logo.bmp', 'lz4.dll', 'CustomClientConfig.ini'
        foreach ($f in $files) {
            $p = Join-Path $cache $f
            if (-not (Test-Path $p)) { Say "    downloading $f..."; Get-File "$PatchBase/$f" $p }
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function Expand-Over([string]$zip, [string]$to) {
            New-Item -ItemType Directory -Force $to | Out-Null
            $z = [IO.Compression.ZipFile]::OpenRead($zip)
            try {
                foreach ($e in $z.Entries) {
                    $target = Join-Path $to $e.FullName
                    if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force $target | Out-Null; continue }
                    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
                }
            } finally { $z.Dispose() }
        }
        Expand-Over (Join-Path $cache 'Game_Patch_2016.zip') $dir
        Expand-Over (Join-Path $cache 'Sound_Banks.zip') (Join-Path $dir 'Resources\Audio\pc9\SoundBanks')
        Expand-Over (Join-Path $cache 'Locales.zip') (Join-Path $dir 'Locale')
        foreach ($f in 'H1EmuVoiceClient.exe', 'H1Z1_BE.exe', 'H1Z1_FP.exe', 'logo.bmp', 'lz4.dll') { Copy-Item (Join-Path $cache $f) (Join-Path $dir $f) -Force }
        Copy-Item (Join-Path $cache 'CustomClientConfig.ini') (Join-Path $dir 'ClientConfig.ini') -Force
        Ok 'H1Emu game patch applied'

        # H1Emu asset pack: extra Assets_*.pack files. The feed's hashes can lag behind its release files,
        # so a download is checked against GitHub's release digest and remembered by url + hash.
        $assetsDir = Join-Path $dir 'Resources\Assets'
        $marks = Join-Path $StateDir 'assets'
        New-Item -ItemType Directory -Force $assetsDir, $marks | Out-Null
        $feed = Invoke-RestMethod $AssetFeed -Headers @{ 'User-Agent' = 'h1z1-join' }
        $keep = @(0..255 | ForEach-Object { 'Assets_{0:D3}.pack' -f $_ })
        foreach ($a in $feed.assets) {
            $keep += $a.filename
            $p = Join-Path $assetsDir $a.filename
            $mark = Join-Path $marks "$($a.filename).txt"
            if (Test-Path $p) {
                $have = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
                $known = if (Test-Path $mark) { (Get-Content $mark -Raw).Trim() } else { '' }
                if ($have -eq ($a.hash -replace '^sha256:', '') -or $known -eq "$($a.url) $have") { continue }
            }
            Say "    downloading asset pack $($a.filename)..."
            Get-File $a.url $p
            $have = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
            $digest = $null
            if ($a.url -match 'github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/') {
                try {
                    $rel = Invoke-RestMethod "https://api.github.com/repos/$($Matches[1])/releases/tags/$($Matches[2])" -Headers @{ 'User-Agent' = 'h1z1-join' }
                    $digest = ($rel.assets | Where-Object { $_.name -eq $a.filename } | Select-Object -First 1).digest -replace '^sha256:', ''
                } catch {}
            }
            if ($digest -and $have -ne $digest) { Remove-Item $p -Force; throw "Download of $($a.filename) was corrupted; run the command again." }
            if (-not $digest -and $have -ne ($a.hash -replace '^sha256:', '')) { Warn "$($a.filename) hash differs from the feed (using it anyway, like the H1Emu launcher)" }
            Set-Content -Path $mark -Value "$($a.url) $have" -Encoding ASCII
        }
        Get-ChildItem $assetsDir -File | Where-Object { $keep -notcontains $_.Name } | Remove-Item -Force
        Ok "asset pack up to date ($($feed.assets.Count) files)"

        # BattlEye folder makes the game try to go through Steam; the launcher removes it too.
        $be = Join-Path $dir 'BattlEye'
        if (Test-Path $be) { Remove-Item $be -Recurse -Force }
        foreach ($f in 'Game_Patch_2016.zip', 'Resources\Audio\pc9\SoundBanks\Sound_Banks.zip', 'Locale\Locales.zip') {
            $p = Join-Path $dir $f; if (Test-Path $p) { Remove-Item $p -Force }
        }
    }

    function Get-LaunchArgs([string]$name) {
        $sha = [Security.Cryptography.SHA256]::Create()
        $key = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($name)) | ForEach-Object { $_.ToString('x2') })
        return "sessionid={`"sessionId`":`"$key`",`"gameVersion`":2} gamecrashurl=$CrashUrl server=${ServerHost}:$LoginPort"
    }

    function New-PlayShortcut([string]$dir, [string]$launchArgs) {
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'H1Z1 (kryspin).lnk'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $dir 'H1Z1.exe'
        $sc.Arguments = $launchArgs
        $sc.WorkingDirectory = $dir
        $sc.Save()
        # Tick "Run as administrator" like the H1Emu launcher does.
        $bytes = [IO.File]::ReadAllBytes($lnk); $bytes[0x15] = $bytes[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnk, $bytes)
        Ok "desktop shortcut: $lnk"
    }

    Write-Host ''
    Write-Host '  H1Z1 Just Survive (2016)  ->  h1z1.kryspin.dev' -ForegroundColor Magenta
    Write-Host '  -----------------------------------------------' -ForegroundColor Magenta

    $state = Load-State
    if (-not ($state.PSObject.Properties.Name -contains 'steamUser')) { $state | Add-Member steamUser $null }

    # 1. Name / account
    Step 'Your player id'
    $name = if ($env:H1Z1_NAME) { $env:H1Z1_NAME } else { $state.name }
    if (-not $name) {
        Say '    This is your account on the server (no password). Pick something unique and keep it to yourself;'
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
    if (Test-SoeServer $ServerHost $LoginPort 'LoginUdp_11') { Ok "login server answering (UDP $LoginPort)" } else { Warn "login server not answering on UDP $LoginPort - tell John" }
    if (Test-SoeServer $ServerHost $ZonePort 'ClientProtocol_1080') { Ok "game server answering (UDP $ZonePort)" } else { Warn "game server not answering on UDP $ZonePort - tell John" }

    # 3. Runtimes
    Step 'Game runtimes'
    if ($env:H1Z1_SKIP_PREREQS -eq '1') { Say '    skipped (H1Z1_SKIP_PREREQS=1)' } else { Install-Prereqs }

    # 4. Game files (the exact 22 Dec 2016 build)
    Step 'H1Z1 Just Survive (22 Dec 2016) game files'
    $gameDir = $null
    foreach ($d in @($env:H1Z1_GAME_DIR, $state.gameDir)) { if (Test-Game2016 $d) { $gameDir = $d; break } }
    if (-not $gameDir) { $gameDir = Find-ExistingGame }
    if ($gameDir) {
        Ok "found: $gameDir"
    } elseif ($env:H1Z1_SKIP_DOWNLOAD -eq '1') {
        throw 'No 2016 game files found and H1Z1_SKIP_DOWNLOAD=1.'
    } else {
        $target = if ($env:H1Z1_GAME_DIR) { $env:H1Z1_GAME_DIR } else { $DefaultGameDir }
        if (-not $env:H1Z1_GAME_DIR) {
            $ans = Read-Host "    Install folder [Enter = $target]"
            if ($ans) { $target = $ans.Trim('"', ' ') }
        }
        if ($target -match 'King of the Kill|steamapps') { throw "Pick a separate folder, not a Steam game folder ('$target')." }
        New-Item -ItemType Directory -Force $target | Out-Null
        $state.gameDir = $target; Save-State $state
        Download-Game $target $state
        if (-not (Test-Game2016 $target)) {
            throw ("The download didn't finish or isn't the 2016 build. If Steam said the account doesn't own app $SteamApp, " +
                   'that Steam account cannot get these files. Otherwise just run the command again to resume.')
        }
        $gameDir = $target
        Ok "downloaded and verified: $gameDir"
    }
    $state.gameDir = $gameDir
    Save-State $state

    # 5. H1Emu patch (needed for the 2016 build to talk to community servers)
    Step 'Applying the H1Emu patch'
    Install-Patch $gameDir

    # 6. Shortcut + launch
    Step 'Done'
    $launchArgs = Get-LaunchArgs $name
    New-PlayShortcut $gameDir $launchArgs
    Say "    Next time just double-click 'H1Z1 (kryspin)' on your desktop (or re-run the command to re-patch)." White
    if ($env:H1Z1_NO_LAUNCH -eq '1') { Say '    (not launching: H1Z1_NO_LAUNCH=1)'; return }
    Say '    Launching H1Z1 (accept the admin prompt)... pick the server, make a character, have fun.' White
    Start-Process -FilePath (Join-Path $gameDir 'H1Z1.exe') -WorkingDirectory $gameDir -ArgumentList $launchArgs -Verb RunAs
}
