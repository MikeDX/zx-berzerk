# Berzerk ZX Spectrum — port strategy

This document is the source of truth for how the Spectrum port relates to the
arcade ROM. The goal is **run the original game logic**, not a rewrite that
only looks similar.

## Arcade memory map (from MAME / listing)

| Range | Size | Role |
|-------|------|------|
| `$0000–$07FF` | 2K | Program PROM 1C |
| `$0800–$0BFF` | 1K | Scratch + CMOS (partial) |
| `$1000–$37FF` | ~10K | Program PROMs 1D/3D/4D/6D/4C |
| `$3800–$3FFF` | 2K | Program PROM 3C (often unused in listing) |
| `$4000–$43FF` | 1K | Scratch pad |
| `$4400–$5FFF` | 7K | Bitmap video (256×223, 1 bpp, 32 bytes/line) |
| `$6000–$63FF` | 1K | Magic scratch |
| `$6400–$7FFF` | 7K | Magic image RAM (XOR draw + hardware collision) |
| `$8000–$87FF` | 2K | Colour LUT |

## Boot / game flow (addresses from `ref/berzerk.asm`)

```
reset / cold start
  └─ $1602  clear scratch, copy high scores, …
       └─ $164B  attract / coin loop
            ├─ $1666  job shell
            ├─ $19AC  attract UI / “insert coin”
            ├─ $1A98  print start prompts (LTABLE multilingual)
            └─ credit accepted → $18B2 / $17B8
                 ├─ DEFAULT_PLAYER_STATE ($187F)
                 ├─ clear demo flag, set MAN_X/Y = $1E,$64
                 └─ $209D  room start
                      ├─ CLEAR_SCREEN ($1A4E)
                      ├─ maze build ($2540)
                      ├─ MAN_INIT / robot spawn jobs
                      └─ job system runs MAN / ROBOT / bolts / Otto
```

Per-frame work is **not** a single `game_frame` loop. The arcade uses:

- **NMI** (`$1721`) — speech / audio / bookkeeping
- **IRQ** (`$26AB` / bottom-of-screen) — input edge detect, vector animate
- **Job list** (`CREATE_JOB` / `STOP_JOB` / `$1E78`) — cooperative coroutines
  for MAN, robots, bolts, Otto

Sprites: `ERASE_PATTERN` → `MOVE_ANIMATE_VECTOR` → `WRITE_PATTERN` →
`DRAW_SPRITE` into **Magic RAM**. Collision is hardware: write a pixel, read
status port `$4E` bit 7.

## What Spectrum must replace

| Arcade | Spectrum replacement |
|--------|----------------------|
| Magic RAM XOR + `$4E` collision | Wall-mask OR blit + software collide (`src/game/draw.asm`) |
| Video `$4400` 256×223 | Spectrum `$4000` 256×192 bitmap (+ attrs) |
| `IN $48/$4A` sticks | `input_poll` (Kempston / QAOP) |
| `IN/OUT` sound / speech / CMOS | stubs / Currah later / ignore |
| NMI + IRQ job timing | IM2 or `halt` frame + call into job head |
| Code at `$0000` | Relocated image + address rewrite (48K) or 128K paging |

## Conversion pipeline

```
ref/berzerk.asm
      │
      ▼
tools/convert_ref.py
      │
      ├─► src/arcade/rom_image.asm   byte-exact PROM ($0000–$3FFF gaps filled)
      ├─► src/arcade/symbols.asm     LABEL EQU $addr for every listing label
      ├─► src/arcade/io_map.inc      ports that must be hooked
      └─► (later) src/arcade/rom.asm mnemonic source with hooks
```

**Phase 1 (current):** hand-ported playable shell + ROM **data** tables
(`src/game/romdata.asm`) driven by Spectrum draw/input.

**Phase 2 (this work):** emit full PROM image + symbols; document hook sites
(`DRAW_SPRITE $2817`, `RTOAX $29A1`, control `IN`, collision `$4E`).

**Phase 3:** assemble arcade code at a Spectrum base (`ARCADE_BASE`), rewrite
absolute operands in the converter, and jump to arcade `$164B` / `$17B8` with
I/O traps implemented in Z80 as CALL replacements or OUT-port intercepts.

**Phase 4:** delete the hand-ported player/robot/maze once the arcade path is
feature-complete.

## Hook points (must stay 1:1 with listing)

| Label | Addr | Action on Spectrum |
|-------|------|--------------------|
| `DRAW_SPRITE` | `$2817` | blit via `or_sprite` / mask |
| `ERASE_PATTERN` | `$272D` | `restore_sprite` |
| `WRITE_PATTERN` | `$274D` | resolve pattern + draw |
| `MOVE_ANIMATE_VECTOR` | `$27A9` | keep as-is (pure logic) |
| `CALCULATE_MAGIC_IMAGE_RAM_ADDRESS` / `RTOAX` | `$29A3` / `$29A1` | map (X,Y) → Spectrum pixel addr + shift |
| `MOVE_PLAYER` stick read | `$1EEB` `IN A,($48)` | `input_poll` + invert sense (`XOR $1F`) |
| bolt plot | `$1578` `LD (HL),$80` + `$4E` | `plot_pixel` + mask test |
| `CLEAR_SCREEN` | `$1A4E` | `zx_cls` |
| maze brick `DRAW_SPRITE` | `$2656` | same as sprite hook |

## Non-goals (for now)

- Cocktail flip / bookkeeping CMOS UI
- Voice / sound board (stub OK)
- Exact 223-line Y coordinates (scale or clip to 192 with a single documented transform)
