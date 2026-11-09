# Asset organization

The repository keeps downloaded packs in their original directories so their
source files, editable Aseprite files, and license documents stay together.

- `map_1/`: curated, game-ready exports used by Map 1.
- `itch.io/`: original third-party packs downloaded from itch.io.
- `FreeCharactersAnimationsAssetPack/`: original character source pack.
- `IconGodotNode/`: generic Godot-style icons; not part of the Map 1 art style.
- `Runner1-Updated/`: original runner-game UI and environment pack.
- `background/`: standalone background candidates.
- `font/`: shared font candidates.

Do not reference files inside a source pack directly from a gameplay scene.
Export or copy the selected sprite into the relevant `assets/map_<number>/`
folder first and record its source in that map's README.
