# Space Shooter

A small arcade prototype written in Odin with raylib. Runs on desktop and in a browser through WebAssembly + Emscripten.

## Campaign and mission builder

**12 sectors / 31 waves**, with timed reinforcements, V-shaped diving wings, ring formations, armored screens and bosses in sectors 5, 8 and 12.

Choose **Create Levels** from the web start menu to open `/editor/` (or press **E** on desktop) for the Odin/raylib visual editor: place and drag enemies, set health and spawn delays, clone sectors/waves, tune difficulty, playtest, and import/export JSON. Imported campaigns can be played without recompiling.

- Shipped campaign: `assets/campaign.json`
- Small starter: `examples/starter-campaign.json`
- Full editor and schema guide: [LEVELS.md](LEVELS.md)

Procedural movement now combines seeded smooth noise, bounded steering and local separation. Aimed fire locks its target before shooting; divers telegraph and commit to a curved path. Tune Variation and New Route Seed in the editor. See [BEHAVIOR.md](BEHAVIOR.md) for the implementation and research.

### Enemy roster

- **Scout, green (1 HP):** drifts in formation and shoots straight down.
- **Weaver, cyan (2 HP):** wanders along a smooth bounded route and locks its aim during a visible warning.
- **Diver, coral (1 HP):** telegraphs a destination, dives along a committed curve, and recovers; contact causes damage.
- **Tank, gold (4 HP):** moves slowly, fires aimed shots, and takes sustained fire to destroy.
- **Spitter, violet (3 HP):** fires a three-bullet fan.
- **Hive Matriarch, pink (48 HP):** sweeps across the arena and fires five-shot fans. At half health it switches to seven-shot fans plus two faster cannon shots, with a shorter cooldown.

Each kind has a distinct silhouette and color. Armored enemies have health bars. Warning rings telegraph incoming shots; hits flash white. The original scout sprite, ship, explosion art, background and sounds are retained.

### Player and rewards

- Five shield points; damage from hostile bullets or enemy contact.
- Forgiving ship hitbox and 1.6 seconds of invulnerability after damage.
- One shield restored on entering a new sector, up to five.
- A weapon pickup drops every fifth kill. Catch it for ten seconds of triple shot and 50 points.
- Four seconds of triple shot are guaranteed after each cleared wave.
- Enemy kills award 100 points per starting HP; wave clears award 250 times the sector number.
- Each new wave has a countdown and sector-specific hint. Losing all shields ends the run; clearing the boss and escorts wins it.

## Controls

- **Arrow keys / WASD:** move in two dimensions within the lower flight area.
- **Hold Space:** fire (or triple shot while powered up).
- **P:** pause / resume.
- **R:** restart the entire campaign.
- **E in the creator route or desktop build:** switch to the mission builder. The player build has no editor shortcut.
- **F5 in the editor:** playtest the selected wave.
- **Browser:** click Play to start and unlock audio, then keep the canvas focused.
- **Desktop:** Escape closes the window.

Keyboard controls are required; touch controls are not implemented.

## Desktop (PowerShell)

From this folder, with Odin on PATH:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
odin build . -o:speed -out:build/space-shooter.exe
./build/space-shooter.exe
```

Run from the project root so relative asset paths resolve.

## Web build (PowerShell)

Requirements: a recent Odin distribution including `vendor/raylib/wasm/libraylib.web.a`, and the official Emscripten SDK. This port was verified with Odin dev-2026-11 and Emscripten 4.0.10.

Install/activate Emscripten using https://emscripten.org/docs/getting_started/downloads.html . No SDK installation is bundled in this repository.

```powershell
./build-web.ps1 -Emsdk "C:/path/to/emsdk"
python -m http.server 8000 --bind 127.0.0.1 --directory build/web
```

Open http://localhost:8000 and choose Play Campaign. The start menu also offers controls help, sound settings, and a Create Levels link to the separate `/editor/` route. If `emcc` is already on PATH or `EMSDK` is set, just run `./build-web.ps1`.

Do not open index.html directly as a file: WebAssembly and preloaded assets need HTTP.

### Share online

Upload the **contents of `build/web`** to any static host, or zip those contents with `index.html` at the ZIP root for an itch.io HTML game. Keep the root game files and the complete `editor/` directory together. Use `./package-web.ps1` to prepare the correct upload layout. Nothing has been published automatically.

The player shell presents a start menu with Play Campaign, How to Play, persistent sound control, and the workshop link. Returning to Menu pauses the campaign; Resume Flight continues it and New Campaign starts fresh. Workshop imports and saved custom campaigns never replace the bundled player campaign.

The shell expects WebAssembly served as `application/wasm` (Python's server handles this). The game needs no backend or cross-origin isolation headers. The raw build folders also contain intermediate `game.o` files; `package-web.ps1` excludes them from hosting.

## Implementation

`main.odin` contains shared initialization, frame update and cleanup. The desktop entry runs a normal loop; `web.odin` exports initialization and frame callbacks, with Emscripten-backed allocation. `web/shell.html` loads Odin's JS runtime and schedules frames with requestAnimationFrame. Assets are preloaded into Emscripten's filesystem at `/assets`.

The shared simulation is in `step_game`, separate from drawing and input so campaign rules can be exercised without a window. Movement is independent of refresh rate, diagonal movement is normalized, and real-time frame steps are capped to avoid large jumps after a stalled frame.

## Validation

Validate a campaign with `./validate-levels.ps1 -Path assets/campaign.json`. Web builds run this automatically.

```powershell
./test-game.ps1
```

The Windows test script uses Odin's LLD linker and raylib's shared library so the test runner and raylib use matching C runtimes. It temporarily adds Odin's raylib DLL directory to PATH for that process only.

The sequential gameplay scenario checks movement, fire, pause, damage immunity, pickups, triple shot, all 31 waves through projectile collisions, every enemy kind, sector transitions, the boss's second attack phase, defeat and campaign reset. No test-only skips are included in a normal web build.

For visual QA only, `./build-web.ps1 -Emsdk <sdk-folder> -Output build/web-qa -QA` enables an isolated encounter-preview export. Production builds omit that export. Do not upload the QA build.

Browser smoke testing covered launch, movement, firing and score, pause/resume, and restart. Hostile damage and defeat were verified through deterministic projectile injection in the isolated QA build; representative sectors were also rendered there. The expanded campaign has not received a full human balance playtest. Browser editor tests verify placement, dragging, health/delay editing, playtesting, cloning, save/restore, export, and valid/invalid imports.

Asset reference: https://grafxkid.itch.io/mini-pixel-pack-3

## Tag-triggered GitHub Pages deployment

Push a version tag such as `v0.1.0` to deploy the tested web game. Branch/PR pushes build and test without publishing. The one-time Pages source must be set to **GitHub Actions**. See [DEPLOYMENT.md](DEPLOYMENT.md) for setup, release commands, toolchain pins and troubleshooting.
## Source formatting

Before pushing changes:

```powershell
./format-odin.ps1
./format-odin.ps1 -Check
./test-game.ps1
```

The script formats every non-ignored Odin source, including tests and tools, using `odinfmt.json` (tabs, 120-column wrapping, LF endings). It finds `odinfmt` on PATH or in an OLS installation beside Odin. You can also set `ODINFMT` or pass `-Formatter "C:/tools/ols/odinfmt.exe"`. Install odinfmt from the [OLS project](https://github.com/DanielGavin/ols) if needed.
