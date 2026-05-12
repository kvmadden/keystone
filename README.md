# Keystone — a beaver game

> *Build a dam. Raise a wetland. Let the ecosystem return.*

You play a beaver. Chew trees, drop logs at the narrow point in the stream, raise the water, and a wetland slowly takes shape. Willow takes root, then frogs arrive, then fish, ducks, heron, otter. Hold all six species together for three in-game days — that's a stable keystone ecosystem.

## Win condition

All six species (**willow · frog · fish · duck · heron · otter**) coexist for 3 consecutive in-game days.

## Lose condition

Stamina hits zero — or every dam segment breaks during a drought.

## Controls

| Key | Action |
|---|---|
| `WASD` / arrows | Move |
| `Space` | Chew tree · pick up log · place at dam · repair |
| `Shift` | Sprint (drains stamina faster) |
| `E` | Sleep in lodge (skip to dawn, full stamina) |
| `Esc` | Pause |

## Threats

- **Coyotes** prowl at night. Get back to the lodge.
- **Drought** strikes every few days. A dam of seven or more segments holds.
- **Decay.** Every segment loses 25% integrity per in-game day. Repair often.

## The species ladder

| Species | Spawn condition |
|---|---|
| Willow | ≥3 wetland tiles |
| Frog | ≥2 willows AND ≥3 shallow water |
| Fish | ≥4 deep water |
| Duck | ≥3 shallow AND ≥2 willows |
| Heron | ≥3 fish OR ≥4 frogs |
| Otter | ≥5 fish AND ≥6 deep water |

## Run it

Open `project.godot` in Godot 4.4+ and press F5, or double-click the exported `Keystone.app`.

## Build it

```bash
# Re-generate sprites (optional — needs PIXELLAB_API_KEY)
PIXELLAB_API_KEY=... node tools/generate_sprites.mjs

# Export the macOS app (uses tools/export_macos.sh)
./tools/export_macos.sh
```

## Tech

- **Engine** Godot 4.6 (GDScript, GL Compatibility renderer for macOS)
- **Sprites** PixelLab pixflux API · 32×32 / 16×16
- **Font** IBM Plex Sans
- **Color palette** dark forest green base, water blues, accent gold

## Repo layout

```
keystone/
├── project.godot
├── scenes/             ; .tscn scene files
├── scripts/            ; .gd game logic
│   ├── game.gd         ; singleton: shared state + signals
│   ├── world.gd        ; tilemap + draw
│   ├── water_sim.gd    ; flood-fill + wetland aging
│   ├── dam.gd          ; segments + decay + repair + drought
│   ├── day_cycle.gd    ; dawn/day/dusk/night lighting + day ticks
│   ├── beaver.gd       ; player controller
│   ├── species_spawner.gd ; ecosystem ladder
│   ├── species_entity.gd  ; per-creature procedural wander + draw
│   ├── coyote.gd
│   ├── threats.gd      ; coyote spawning + drought rolls
│   └── hud.gd
├── assets/
│   ├── sprites/        ; PixelLab pngs (auto-generated, cached)
│   └── fonts/          ; IBM Plex Sans
└── tools/
    ├── generate_sprites.mjs
    └── export_macos.sh
```

---

*Made in two days as a gift for a PhD ecologist.*
*Beavers are textbook ecosystem engineers — they're the keystone species
because so much else cannot persist without what they build.*
