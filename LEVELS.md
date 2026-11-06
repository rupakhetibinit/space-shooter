# Level creation

The editor, level loader, validation, scheduling and game simulation are written in Odin. The web shell only bridges file import/download and browser storage.

## Visual editor

1. Start the game, then press **E** or use the **Level editor** button beneath the web canvas.
2. Use the sector and wave arrows to choose what to edit.
3. Click an enemy palette button, or use **1-6**. Click the blue spawn grid to place it.
4. Click an existing enemy to select it. Drag to move it; placements snap to a 20-pixel grid. Right-click an enemy or press Delete to remove it.
5. Use the selected enemy's **HP** and **DELAY** buttons. HP 0 means the enemy type's default health. Delays advance in half-second steps.
6. Adjust **BULLETS**, **FIRE GAP**, and **MOTION** per sector. A smaller fire gap means faster enemy shooting. **Variation** controls wandering and firing irregularity; **New Route Seed** generates a different reproducible set of routes. See [BEHAVIOR.md](BEHAVIOR.md).
7. Click the sector's name to rename it, then press Enter. Use **Clone sector**, **New wave**, **Clone wave**, and the delete controls to build your campaign.
8. Press **F5** or click **Playtest** to test only the selected wave with a fresh ship. Clearing it shows a test-complete screen. **E** returns to the editor.
9. **Play campaign** or E from the editor starts the campaign from sector one.
10. Use **Save locally** and **Export JSON** to preserve your work. Editing alone does not persist across reloads.

Each wave must retain at least one enemy and each sector at least one wave. A new wave starts with one Scout; add another kind and delete that Scout if desired. A wave can have at most one Boss. Clone operations create independent copies, so edits do not change the source wave/sector.

### Saving and importing on the web

- **Save locally** stores the complete campaign in this browser's localStorage under `space-shooter.campaign.v1`. It is restored automatically when you next click Play on the same origin.
- Local storage belongs to the exact site/port/browser. Clearing site data removes it. **Export JSON** gives you a portable backup.
- **Import JSON** opens a file picker. The imported campaign opens in the editor. Click Playtest or Play campaign to run it; save locally if you want it restored on your next visit.
- Invalid JSON, unsupported versions and invalid content display an error without replacing the active campaign.
- To restore the original campaign, import `assets/campaign.json` from the project (a copy is also supplied with the deliverables).

### Saving and importing on desktop

Run the executable with the project root as the working directory.

- Save locally writes `campaign.custom.json` in the project root; it is automatically loaded at the next launch.
- Export JSON writes `campaign.export.json` in that folder.
- Drop a JSON file onto the editor to import it, or copy it to `campaign.import.json` and click Import JSON.
- Removing/renaming `campaign.custom.json` restores the bundled campaign on the next launch.

## Edit JSON directly

The shipped campaign lives in `assets/campaign.json`. It contains 12 sectors and 31 waves. Each sector has its own name, hint, difficulty multipliers and array of waves. Each wave has explicit enemy placements, health overrides and spawn delays.

Start with `examples/starter-campaign.json`, a small two-wave mission with delayed reinforcements and a 12-HP boss. You can import it into an already-running game without rebuilding.

```json
{
  "version": 1,
  "sectors": [
    {
      "name": "MY SECTOR",
      "tip": "Watch for the delayed diver.",
      "bullet_speed": 1.0,
      "fire_interval": 1.0,
      "motion_scale": 1.0,
      "waves": [
        {
          "enemies": [
            {"kind": "Scout", "x": 240, "y": 140, "hp": 0, "delay": 0},
            {"kind": "Diver", "x": 560, "y": 180, "hp": 2, "delay": 3}
          ]
        }
      ]
    }
  ]
}
```

| Field | Meaning / valid values |
| --- | --- |
| version | Must be 1. |
| seed | Optional unsigned 32-bit campaign seed; missing/zero uses 1337. |
| sectors | 1-32 sectors. Progression uses the array order. |
| name | 1-32 printable ASCII characters. |
| tip | At most 85 printable ASCII characters. |
| bullet_speed | Projectile-speed multiplier, 0.5-2.0. |
| fire_interval | Enemy firing-interval multiplier, 0.5-2.0. Lower is faster. |
| motion_scale | Patrol movement-speed multiplier, 0.25-2.0. |
| variation | Optional 0-1.5; missing/zero uses 0.75. Small positive values give steadier paths. |
| waves | 1-8 waves per sector, played in order. |
| enemies | 1-64 enemies per wave; at most one Boss. |
| kind | Exact spelling: Scout, Weaver, Diver, Tank, Spitter, Boss. |
| x / y | Enemy center in game coordinates: x 80-720, y 100-260. |
| hp | 0 = default; otherwise 1-200. Defaults: Scout/Diver 1, Weaver 2, Tank 4, Spitter 3, Boss 48. |
| delay | 0-30 seconds after the wave starts. Pending enemies are not visible, cannot fire or take damage, and count toward wave completion. |

Use standard JSON (no comments or trailing commas). Total file size is limited to 256 KiB. All sector multiplier fields are required. Coordinates use the game space, not the browser's scaled canvas size.

## Validate a config with Odin

```powershell
./validate-levels.ps1
./validate-levels.ps1 -Path examples/starter-campaign.json
./validate-levels.ps1 -Path "C:/path/to/my-campaign.json"
```

The validator prints sector, wave and spawn counts on success, and exits with a descriptive error on failure. The web build runs this check automatically before compiling.

## Making a custom campaign the shipped default

Replace `assets/campaign.json`, then rebuild the desktop/web version. Odin embeds a validated fallback, and the web build preloads the JSON asset. Existing browser saves or desktop `campaign.custom.json` override the bundled default until removed or replaced.

Imported and visually edited campaigns do not require recompilation.

## New campaign encounters

| Sector | Waves | Theme |
| --- | --- | --- |
| First Contact | 2 | Formation fighting. |
| Serpent Belt | 2 | Weavers and diving attackers. |
| Iron Convoy | 2 | Armored screens. |
| Crossfire | 2 | Overlapping fan and aimed fire. |
| The Hive | 2 | First Matriarch encounter, 48 HP. |
| Shattered Relay | 3 | Timed reinforcement groups. |
| Needle Run | 3 | V-shaped diving wings. |
| Prism Gate | 3 | Ring formations and a 60-HP guardian. |
| Rust Armada | 3 | Heavy tanks screening artillery. |
| Ghost Corridor | 3 | Staggered ambush groups. |
| Broodstorm | 3 | Eighteen-enemy swarms arriving in waves. |
| Last Signal | 3 | Mixed gauntlet and an 84-HP final boss. |

As before, entering a new sector restores one shield. Clearing a wave grants a short triple-shot boost. The HUD reports how many reinforcements remain pending and when the next group arrives.
