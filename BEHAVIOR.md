# Procedural enemy behavior

The implementation remains Odin and uses a C99-like procedural organization: plain structs, explicit enums, small named functions, and direct loops. Simulation and drawing are separate.

- `noise.odin`: integer hashing, scalar value noise, quintic interpolation, two weighted noise layers, vector limits, cubic Bezier evaluation.
- `behavior.odin`: movement profiles, bounded steering, local separation, diver state transitions, firing schedules and attack telegraphs.
- `main.odin`: shared game loop, collisions, player input and rendering.

## What changed

Previously each enemy's position was assigned from a short, repeating sine curve. Now a low-frequency, seeded noise field proposes a target near the enemy's spawn anchor. Velocity and acceleration limits steer the enemy toward that target. Small nearby-neighbor separation keeps formations from behaving like one rigid object.

This is **value noise with a quintic interpolant**, not Perlin gradient noise. Two weighted frequency bands add broad movement and smaller deviations without per-frame random jitter. The quintic blend has zero first and second derivatives at cell boundaries.

Targets remain bounded around their anchors. This prevents the unbounded drift of a random walk. Each enemy kind has explicit radius, noise frequency, speed and acceleration settings. Tanks turn more slowly; weavers take wider paths; scouts retain a compact formation; the boss has a broad patrol envelope.

The behavior loop uses at-most-1/120-second substeps. Neighbor separation reads a position snapshot, and random choices use stable seeds and event counters rather than frame counts. Drawing never advances random state.

## Fair attacks

- Every enemy shot gets at least **0.70 seconds of warning**. An interval cannot be reduced below the warning plus a 0.25-second gap, even at extreme editor settings.
- Aimed enemies lock the player's position at the start of the tell. Dashed lines show that locked destination. Subsequent player movement does not change it.
- Enemies slow their patrol during aiming, and projectiles keep their original velocity after launch.
- Firing intervals vary within a bounded range, so enemies do not repeat one synchronized firing cycle.
- Spitter and boss fans retain recognizable shot counts and spacing, with a small smooth lateral variation.
- Divers use explicit **Patrol -> Windup -> Dive -> Return** states. They display a destination marker and **0.85-second windup**, then commit to a curved path lasting 2.0-2.35 seconds. They cannot track the player or fire while diving/recovering.

## Editor and JSON controls

The editor's **Variation** control changes how far enemies wander and how much firing intervals vary:

- `0.01`: almost fixed anchor positions, with smooth settling and neighbor separation.
- `0.75`: bundled default.
- `1.50`: wider, less regular routes.

**New Route Seed** changes the campaign seed. Press Playtest to see the new routes; save/export to retain the seed. A fixed seed gives reproducible behavior for the same enemy layout and player inputs. Player-dependent aiming and separation still react to the game state.

JSON fields:

```json
{
  "version": 1,
  "seed": 1337,
  "sectors": [
    {
      "name": "EXAMPLE",
      "tip": "Read the warning, then move.",
      "bullet_speed": 1.0,
      "fire_interval": 1.0,
      "motion_scale": 1.0,
      "variation": 0.75,
      "waves": [
        {"enemies": [{"kind": "Weaver", "x": 400, "y": 160, "hp": 2, "delay": 0}]}
      ]
    }
  ]
}
```

`seed` is an unsigned 32-bit integer. Missing/zero uses 1337. `variation` accepts 0-1.5; missing/zero uses 0.75 for backward compatibility. Patrol motion speed remains controlled by `motion_scale`; warning times and committed dive durations retain their safety floors.

## Verification

`./test-game.ps1` covers all 31 waves plus noise bounds and determinism, lattice continuity, 30-vs-120-FPS trajectory consistency, per-enemy route variation, velocity limits, frozen aim, committed dive destinations, warning timing, and arena bounds under maximum editor settings.

A real-browser check sampled 661 animation frames and verified independent paths, warning states and the complete diver state cycle. The browser editor regression checks also pass. Desktop and web builds compile. Difficulty still needs human playtesting.

## Research and design references

- Ken Perlin, Improved Noise reference (2002): https://mrl.cs.nyu.edu/~perlin/noise/ . Used as a reference for quintic interpolation; the hash-based value-noise implementation here is different from his gradient-noise algorithm.
- Craig Reynolds, Steering Behaviors for Autonomous Characters (GDC 1999): https://www.red3d.com/cwr/steer/gdc99/ . Informed separation of desired motion from bounded velocity/acceleration.
- Craig Reynolds, Wander: https://www.red3d.com/cwr/steer/Wander.html . Informed temporally correlated variation rather than a new random direction every frame.
