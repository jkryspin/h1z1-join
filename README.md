# h1z1-join

One command to join John's H1Z1 server at `h1z1.kryspin.dev` (Just Survive, 22 Dec 2016 build, via [h1z1-server](https://github.com/QuentinGruber/h1z1-server)).

Open **PowerShell** (Start menu → type `powershell` → Enter) and paste:

```powershell
irm https://raw.githubusercontent.com/jkryspin/h1z1-join/main/join.ps1 | iex
```

## What it does

1. Asks for a **player id**. That id is your account on the server (no password), so keep it unique and to yourself.
2. Checks the server is up.
3. Installs any missing VC++ 2010 / 2015+ and DirectX runtimes (via winget).
4. Gets the **22 Dec 2016 game files** (~20 GB) from Steam with
   [DepotDownloader](https://github.com/SteamRE/DepotDownloader) (app 295110, depot 295111, manifest 8395659676467739522).
   Sign in with the Steam account that owns **H1Z1 / H1Z1: Just Survive**. Type your username, then your password and
   Steam Guard code when asked, or press Enter to sign in with a QR code in the Steam mobile app.
   Your login goes only to Steam and is remembered for re-runs. If you already have the 2016 build (for example from the
   H1Emu launcher), it's found and reused.
5. Checks it's the right build (`H1Z1.exe` CRC32 `bc5b3ab6`). Other H1Z1 versions such as King of the Kill won't work.
6. Applies the [H1Emu](https://github.com/H1emu/h1emu-launcher) 2016 patch and asset pack, the same steps the H1Emu launcher runs.
7. Adds an **H1Z1 (kryspin)** desktop shortcut and launches the game (accept the admin prompt).

Running it again is safe and quick. It resumes an interrupted download and re-applies the patch.

## Troubleshooting

- **"App 295110 is not available from this account"**: that Steam account doesn't own H1Z1 / Just Survive.
- **Download stopped**: run the command again; it resumes.
- **Different install folder**: set `$env:H1Z1_GAME_DIR = 'D:\Games\H1Z1 2016'` before running the command.
