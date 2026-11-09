# Map 1 curated assets

Map 1 uses one primary visual family: **Legacy Fantasy - High Forest 2.3**.
Current UI uses the original code-native rustic SVG theme in `assets/shared/ui/rustic/`.
The previous Kenney UI has been archived; its license remains available under `assets/shared/ui/`.

## Historical curated image inventory (not an exhaustive runtime dependency list)

| File | Purpose | Original source |
| --- | --- | --- |
| `environment/background_sky.png` | Static sky layer | `Legacy-Fantasy - High Forest 2.3/Background/Background.png` |
| `environment/forest_far.png` | Repeating distant forest layer | `Legacy-Fantasy - High Forest 2.3/Trees/Background.png` |
| `environment/forest_near.png` | Repeating foreground bushes | `Legacy-Fantasy - High Forest 2.3/Assets/Tree-Assets.png` |
| `environment/ground_grass_tile.png` | Ground surface tile | `Legacy-Fantasy - High Forest 2.3/Assets/Tiles.png` |
| `environment/ground_rock_tile.png` | Ground fill tile | `Legacy-Fantasy - High Forest 2.3/Assets/Tiles.png` |
| `obstacles/rock_base.png` | Map 1 obstacle | `Legacy-Fantasy - High Forest 2.3/Assets/Props-Rocks.png` |
| `goal/cave_entrance.png` | End-of-map cave entrance | `Legacy-Fantasy - High Forest 2.3/Assets/Tree-Assets.png` |


The exported images are cropped copies. Keep the original packs unchanged when
creating further variants.

> License checkpoint: the repository currently contains the Kenney CC0 license,
> but no separate license file for the High Forest pack. Verify and archive its
> original itch.io license before distributing a public or commercial build.

## Current implementation — 2026-10-16

- Shared MK2 gameplay actor and two-view joint guides are integrated.
- Rock-break effects are implemented in code.
- Placeholder music and SFX are integrated from `assets/audio_placeholder/`.
- Original source/extraction tools are archived outside the project.
- See the root README for backend gaps, audio limitations and remaining work.

## Import rules

- Use nearest-neighbor filtering for pixel art.
- Keep sprite scale on whole-number steps where possible.
- Use bottom-center pivots for the player, obstacle, and cave.
- Gameplay collision remains independent from visual sprite bounds.
