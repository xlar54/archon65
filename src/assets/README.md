Game assets
===========

Everything the game is built from lives here. The build (`tools/build_assets.py` and
64tass) compiles it. Edit any of it.

Sprites (`sprites/`)
--------------------

Each sheet is a PNG grid of 24 × 21 pixel cells, with no gaps. A pixel with alpha below 128 is
transparent. Any colour is allowed: the build quantises all the art into 176 palette
entries (80-255), so the fewer distinct colours you use overall, the more exact they stay.

| File | Contents |
|---|---|
| `static.png` + `static.txt` | The sprites always in memory, 16 cells a row. `static.txt` names them in the same order; the names become `SPR_<name>` in the code, so keep the order and the names unless you change the code too. |
| `combat_NN_<type>.png` | One icon type's 31 combat sprites, 8 cells a row |

`static.png`, in order:

| Cells | Contents |
|---|---|
| 0-19 | The board pieces, by type (Dark faces left) |
| 20, 21 | The power point and the prison chains |
| 22-63 | Barriers: 3 groups × 7 colours (luminance 1-7), each solid then faded. The pillar is 14 × 20 at the cell's top left (from x = 1); the arena draws it 4 rows above its 16 × 16 box, so it stands on the box's bottom edge. |
| 64-69 | The Phoenix's fire: 2 frames, then the doubled frame as 4 tiles |
| 70-85 | The Banshee's wail: 4 rings, each doubled as 4 tiles |
| 86-107 | The title logo, 11 × 2 tiles |

The logo keeps its own seven palette entries (40-46) so the title can make them glint. Pixels
in exactly the colours of `LOGO_PAL` (`tools/build_assets.py`) use those entries; any other
colour is ordinary art.

`combat_NN_<type>.png`, in cell order:

| Cells | Frames |
|---|---|
| 0-3 | Walk right |
| 4-7 | Walk down (6 is a repeat of 4) |
| 8-11 | Walk up (10 is a repeat of 8) |
| 12-16 | Attack: up, up-right, right, down-right, down |
| 17-20 | Walk left |
| 21-23 | Attack: up-left, left, down-left |
| 24-30 | The missile, drawn from the cell's top left: right, vertical, up-right, down-right, left, up-left, down-left. Animated missiles (boulders, fireballs, whirlwinds) cycle cells 24-27 instead. |

Notes:
- A fighter's top-left is its position in the arena. Hits are pixel-exact, so the shapes
  matter for the game.
- The Shapeshifter (type 12) is never drawn as itself in a fight. It copies its foe's
  sheet, tinted to its own colour at run time.
- Phoenix and Banshee have no missile cells.

Spell effects (`effects/`)
--------------------------

`effects.png` holds one row per effect of 32 × 32 frames, and `effects.txt` gives each row
`NAME FRAMES DELAY` (DELAY = game frames per animation frame). A pixel with alpha below 128
is transparent.
- The build gives each effect its own 15 colours, so use few colours per row.
- A frame stands on a board square: its bottom row is the square's bottom row, centred.
- The four `SUMMON_*` rows must stay in elemental order (air, fire, earth, water).
- `TELEPORT` is played backwards for the arrival. `ORB` loops while it flies.
- At most about 108 frames fit (`$12000`-`$1F7FF`).

Data (`*.asm`)
--------------

| File | Contents |
|---|---|
| `font.asm` | The 8 × 8 font: 64 glyphs in C64 screen-code order, 8 bytes each, bit 7 = left |
| `tables.asm` | See below |
| `sound.asm` | See below |

`tables.asm`:
- icon stats per type (lifespan, force, reload, move, attack kind);
- slot to type, the starting board, square kinds, power points, square neighbours;
- the AI tables;
- every message. Messages are upper case, at most 40 characters a line; 13 starts a new
  line and 0 ends the message.

`sound.asm`:
- **Effect streams:** 6-byte steps `DUR AD SR FREQLO FREQHI CTRL`. `$00` is gate off, `$FE`
  loops back to the walker's sound and `$FF` ends.
- **Per-type sound choices:** which walking and attack sound each type uses.
- **The two songs:** per voice, notes of `DUR FREQHI FREQLO GATE`. `FREQHI` 0 is a rest; `DUR` 0
  ends the voice.
