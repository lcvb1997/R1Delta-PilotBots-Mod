# Pilot Bots for R1Delta

Script-driven pilot bots for [R1Delta](https://github.com/r1delta/r1delta) (Titanfall 1) private matches.
The bots run, jump, wallrun, call in and pilot titans and fight using real player movement physics.

*Versão em português abaixo.*

## Installation

1. Download `PilotBots_R1Delta_Setup_<version>.exe` from [Releases](../../releases).
2. Close the game and the R1Delta launcher.
3. Run the installer and tick the client versions (`app-*` folders) that should get the mod.
4. Host a private match: bot count and lethality are in the match settings menu.

When the launcher updates R1Delta to a new version, run the installer again so the new folder gets the mod.
To remove it, use Windows "Apps" (**Pilot Bots para R1Delta**). Everything the installer changed is restored.

The installer is available in English, Portuguese, Russian and Chinese.

## How it works

- **`pilotbots.dll`**: the bots' native code (usercmd input for bots, pathfinding over the map's AI node graph,
  bot creation, the `pm_bot_count`/`pm_bot_lethality` convars). It hooks the game binaries directly
  (`launcher.dll`, `server.dll`, `engine.dll`), which don't change between R1Delta versions.
- **The official `tier0.dll` is not replaced.** The installer backs it up and `pbinject.exe` only adds one import
  entry (`pilotbots.dll!PilotBots_Init`) so Windows loads `pilotbots.dll` along with it. Every R1Delta update
  keeps all of its own fixes.
- **Scripts**: the bot brain (`mp/_bot_ai.nut`, `mp/_bot_manager.nut`) plus the changes to the game's scripts and menus.

Before installing each hook the DLL checks the target bytes. If anything doesn't match it leaves that part alone
and logs the reason to `r1delta\bin_delta\pilotbots.log`.

### Limitations

- Works when hosting from the game client (listen server). It has no effect on the dedicated server (`R1Delta_DS.exe`).
- The scripts are based on R1Delta 2.14.x and replace the matching official files. If a new R1Delta version
  changes those same files, its changes are overwritten until the mod is updated. The installer warns when
  installing into a version other than 2.14.x.

## Repository layout

| Folder | Contents |
|---|---|
| `native/src/pilotbots.cpp` | `pilotbots.dll` |
| `native/tools/pbinject.cpp` | tool that adds the import entry to `tier0.dll` |
| `native/thirdparty/minhook` | [MinHook](https://github.com/TsudaKageyu/minhook) (own copy, separate from R1Delta's) |
| `installer/PilotBots.iss` | installer (Inno Setup 6) |
| `installer/payload/POScriptsIABots` | scripts → `r1delta\scripts\vscripts` |
| `installer/payload/POMenuETextos` | menus and localization → `r1delta\resource` |
| `installer/payload/POMotorNativoBots` | `pilotbots.dll` → `r1delta\bin_delta` (produced by the build) |

## Building

Requirements: Visual Studio 2022 or newer (Desktop development with C++) and [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```
build.bat
```

Produces `release\PilotBots_R1Delta_Setup_<version>.exe` and `release\pilotbots.dll`.
The version lives in `installer/PilotBots.iss` (`AppVer`) and `native/src/pilotbots.cpp` (`PILOTBOTS_VERSION`).

---

## Português

Bots pilotos controlados por script para partidas privadas no [R1Delta](https://github.com/r1delta/r1delta) (Titanfall 1).
Os bots correm, pulam, fazem wallrun, chamam e pilotam titãs e lutam usando a física real de jogador.

**Instalação:** baixe `PilotBots_R1Delta_Setup_<versão>.exe` em [Releases](../../releases), feche o jogo e o launcher,
rode o instalador e marque as versões do cliente (pastas `app-*`) que devem receber a mod. A quantidade e a
letalidade dos bots ficam no menu de configurações da partida privada. Quando o launcher atualizar o R1Delta,
rode o instalador de novo. Para remover, use "Aplicativos" do Windows; tudo volta ao original.

**Como funciona:** o código nativo dos bots fica na `pilotbots.dll`, que se liga direto aos binários do jogo.
A `tier0.dll` oficial é mantida: o instalador faz backup dela e o `pbinject.exe` só acrescenta uma entrada de
importação para o Windows carregar a `pilotbots.dll` junto, então cada atualização do R1Delta mantém as próprias
correções. Cada hook confere os bytes antes de ser instalado; problemas ficam em `r1delta\bin_delta\pilotbots.log`.

**Limitações:** só funciona ao hospedar pelo cliente (sem efeito no `R1Delta_DS.exe`). Os scripts foram feitos
sobre o R1Delta 2.14.x e substituem os arquivos oficiais equivalentes.

**Compilar:** Visual Studio 2022+ (C++ para desktop) e Inno Setup 6, depois rode `build.bat`.

## License / Licença

GPL-3.0 (see [LICENSE.md](LICENSE.md)), as this project is derived from R1Delta.
MinHook is BSD-2-Clause ([native/thirdparty/minhook/LICENSE.txt](native/thirdparty/minhook/LICENSE.txt)).
