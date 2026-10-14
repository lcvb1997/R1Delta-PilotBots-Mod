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
- **Scripts**: the bot brain (`mp/_pilotbots_ai.nut`, `mp/_pilotbots_manager.nut`), loaded by R1Delta autorun scripts
  (`autorun/sv_pilotbots*.nut`) that hook into the match without editing the game's own scripts.

Before installing each hook the DLL checks the target bytes. If anything doesn't match it leaves that part alone
and logs the reason to `r1delta\bin_delta\pilotbots.log`.

### Limitations

- Works when hosting from the game client (listen server). It has no effect on the dedicated server (`R1Delta_DS.exe`).
- A few official files are still replaced (`_death_package.nut`, `_simulation.nut`, `mp_switchback.nut`,
  `mp_wargames.nut`, `menu_mode_select.nut`, `match_settings.menu`), based on R1Delta 2.14.x. If a new R1Delta
  version changes those same files, its changes are overwritten until the mod is updated. The installer warns
  when installing into a version other than 2.14.x.

## Changelog

### 2.1.1

- Fixed the recurring "Internal Server script error" with Frontier Overhaul's Hologram: the decoy no longer
  gets an anti-titan weapon handed to it when it spots a titan (also for holograms used by human players).
- Bots no longer use the Hologram while holding an anti-titan weapon.
- Bots no longer stand still waiting for a Deployable Cover dome that didn't come up (pressed while recharging).

### 2.1.0

**Compatibility**
- Works alongside Aphelion's Frontier Overhaul mod and other script mods (Big thanks to Aphelion!):
  the bot hooks moved out of the game's scripts (`_base_gametype`, `_mapspawn_mp`, `class_titan`,
  `class_wallrun`, `_titan_health`) into R1Delta autorun scripts.
- Older copies of the bot scripts shipped by other mods are detected and replaced at match start.
- Bot scripts renamed to `_pilotbots_ai.nut` / `_pilotbots_manager.nut` so they no longer clash with same-named files.
- Menu text moved to its own localization files (`resource/pilotbots_<language>.txt`), loaded by `pilotbots.dll`.
- The private match settings are sent through a dedicated command instead of a modified `_lobby.nut`.

**Aphelion's Frontier Overhaul gear** (only used when a bot carries it)
- Throwing Knife: thrown straight at pilots and infantry up close, never at titans.
- Deployable Cover: dropped when taking fire; the bot fights from inside the dome.
- Hologram: sent at the enemy to open a fight, when losing one, or when shot from out of sight.
- AG-8 Thunderbolt: the trigger is held through the spin-up and released before the gun overheats.

**Fixes**
- Lobby menus with Frontier Overhaul: sliders showing 500, raw `#PM_...` text, stuck on the burn card tutorial.
- "Internal Server script error" when entering a private match lobby (bot scripts no longer load in the lobby).
- Bot kill replays back in third person, and bots no longer die right after spawning (team spawn fix).
- Script error when an NPC spectre rodeoed a bot's titan.
- Script errors are now written to `r1delta\bin_delta\pilotbots.log` with their callstack.

### 2.0.0

- The bots' native code moved from a modified `tier0.dll` into `pilotbots.dll`: the official `tier0.dll` is kept
  and the mod survives R1Delta updates (run the installer again after each one).
- New installer with backup and full restore on uninstall, in English, Portuguese, Russian and Chinese.

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

**Limitações:** só funciona ao hospedar pelo cliente (sem efeito no `R1Delta_DS.exe`). Alguns arquivos oficiais
ainda são substituídos (feitos sobre o R1Delta 2.14.x); o resto entra por scripts autorun, sem alterar o jogo.

**Novidades da 2.1.1:** corrigido o "Internal Server script error" recorrente com o holograma do Frontier Overhaul
(também quando usado por jogadores); os bots não lançam holograma segurando arma antitanque e não ficam mais
parados esperando um domo de cobertura que não subiu.

**Novidades da 2.1.0:**
- **Compatibilidade:** compatível com o Frontier Overhaul e outras mods de script. Os ganchos dos bots saíram dos
  scripts do jogo, cópias antigas dos scripts de bots vindas de outras mods são substituídas, e os textos e
  configurações do menu ficaram independentes.
- **Itens do FO:** os bots usam a faca, a cobertura, o holograma e a minigun do Frontier Overhaul quando os carregam.
- **Correções:**
  - menu com o FO (sliders em 500, textos `#PM_`, travado no tutorial de burn cards);
  - "Internal Server script error" no lobby;
  - replay em terceira pessoa;
  - bots morrendo logo ao nascer;
  - erro com spectres fazendo rodeo.
- **Log:** erros de script agora vão para o `pilotbots.log`.

**Compilar:** Visual Studio 2022+ (C++ para desktop) e Inno Setup 6, depois rode `build.bat`.

## License / Licença

GPL-3.0 (see [LICENSE.md](LICENSE.md)), as this project is derived from R1Delta.
MinHook is BSD-2-Clause ([native/thirdparty/minhook/LICENSE.txt](native/thirdparty/minhook/LICENSE.txt)).
