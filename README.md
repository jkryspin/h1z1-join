# h1z1-join

One command to join John's H1Z1 (Just Survive, 2016) server at `h1z1.kryspin.dev`.

Open **PowerShell** (Start menu → type `powershell` → Enter) and paste:

```powershell
irm https://raw.githubusercontent.com/jkryspin/h1z1-join/main/join.ps1 | iex
```

It will:

1. Ask for your player id. That id is your account (no password), so keep it unique.
2. Check the server is up.
3. Install the VC++ 2010 / 2015+ and DirectX runtimes if missing (via winget).
4. Find your H1Z1 game folder. If you don't have the game yet, it downloads the
   [H1Emu launcher](https://github.com/H1emu/h1emu-launcher). Sign in with the Steam
   account that owns H1Z1, download the **2016 / Just Survive** version, then run the
   command again.
5. Point `ClientConfig.ini` at the server (a `.bak` copy is kept), add an
   **H1Z1 (kryspin)** desktop shortcut, and launch the game.

Running it again is safe. After the first time, just use the desktop shortcut.

Manual equivalent, from the game folder:

```
.\H1Z1.exe sessionid=YOURNAME server=h1z1.kryspin.dev:1115
```
