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
4. Gets the **22 Dec 2016 game files** (~20 GB) through **your own Steam app**. The script **never asks for your
   Steam login**. It opens Steam's built-in Console tab and types Steam's own command
   `download_depot 295110 295111 8395659676467739522`, so the download runs under the account already signed into
   Steam. Keep your hands off the keyboard for about 10 seconds while it types. That account needs to own
   **H1Z1 / H1Z1: Just Survive**. If you already have the 2016 build (for example from the H1Emu launcher), it's found
   and reused.
5. Checks it's the right build (`H1Z1.exe` CRC32 `bc5b3ab6`). Other H1Z1 versions such as King of the Kill won't work.
6. Applies the [H1Emu](https://github.com/H1emu/h1emu-launcher) 2016 patch and asset pack, the same steps the H1Emu launcher runs.
7. Adds an **H1Z1 (kryspin)** desktop shortcut and launches the game (accept the admin prompt).

Running it again is safe and quick. It resumes an interrupted download and re-applies the patch.

## Troubleshooting

- **"Steam didn't start the download"**: the account signed into Steam doesn't own H1Z1 / Just Survive (Steam stays
  silent in that case), or the typing missed the console. The command is left on your clipboard: open Steam →
  Console, paste, press Enter, then run the one-liner again.
- **Steam isn't installed or signed in**: install Steam, sign in, and run the command again.
- **Different install folder**: set `$env:H1Z1_GAME_DIR = 'D:\Games\H1Z1 2016'` before running the command.
