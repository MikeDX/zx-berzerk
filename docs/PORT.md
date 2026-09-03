# Berzerk ZX Spectrum — port strategy

This document is the source of truth for how the Spectrum port relates to the
arcade ROM. The goal is **run the original game logic**, not a rewrite that
only looks similar.

## Method (current)

Do **not** blindly rewrite every absolute operand in a PROM blob and hope it
boots on a Spectrum. That path resets the machine (wrong `ld bc,nn` counts,
IM2 `$FF` → `$0000`, broken I/O islands, etc.).

Instead:

1. **Headless arcade run** — load the PROM image from `ref/berzerk.asm` into a
   faithful arcade memory map; stub I/O; drive NMI/IRQ like the board.
2. **Trace** — log every memory read/write (and I/O). Classify ranges that are
   actually touched: PROM, scratch, video, magic, colour, junk.
3. **Remap from evidence** — assign Spectrum addresses only for ranges that
   matter; patch **source** (labels / `EQU` / call targets) until the headless
   guest no longer writes outside the allowed Spectrum map.
4. **Ship** — assemble the remapped listing + thin ZX HAL (blit, input, frame)
   into `build/arcade.sna`.

Binary `reloc_rom.py` heuristics stay around as a scratch experiment only.
The durable artefact is a **recompilable, remapped** assembly image plus a
generated address map.

```bash
make                 # emit Spectrum asm + build build/berzerk.sna/.tap
make run             # boot SNA in ZEsarUX
make spectrum-asm    # ref/berzerk.asm → src/arcade/berzerk.asm only
make headless        # arcade-map trace (validation)
make shell           # Phase-1 hand-ported shell → build/shell.sna
```

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

## Spectrum 48K budget (target layout)

Roughly **40K** usable above the ROM/sysvars (`$6000–$FFFF`), minus what we
keep for the host. Arcade working set that must live in RAM:

| Guest region | ≈Size | Notes |
|--------------|------:|-------|
| PROM (used) | ~14K | layout-preserving at `ZX_PROM` |
| Scratch `$0800`+`$4000` | 2K | `$A000` / `$A400` |
| Video | 6K | 256×192 shadow (clip from 223) |
| Magic | 6K+1K | scratch + image shadow |
| Colour | 2K | stub |
| **Subtotal** | **~28–30K** | fits with room for HAL + stack |

Locked map (`tools/emit_spectrum_asm.py` / `mem_map.inc`):

| Spectrum | Role |
|----------|------|
| `$6000–$9FFF` | Remapped PROM (`ZX_PROM` + arcade offset) |
| `$A000–$A3FF` | Scratch / CMOS (`$0800`) |
| `$A400–$A7FF` | Scratch pad (`$4000`) |
| `$A800–$BFFF` | Video shadow 192×32 |
| `$C000–$C3FF` | Magic scratch (`$6000`) |
| `$C400–$DBFF` | Magic image 192×32 |
| `$DC00–$EFFF` | ZX HAL (hooks, blit, input) |
| `$F000–$F7FF` | Colour stub |
| `$F800–$FFFF` | Stack / host vars |

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

## What Spectrum must replace (HAL)

| Arcade | Spectrum replacement |
|--------|----------------------|
| Magic RAM XOR + `$4E` collision | Shadow magic + software collide on write |
| Video `$4400` 256×223 | Shadow then blit to `$4000` 256×192 (+ attrs) |
| `IN $48/$4A` sticks | `input_poll` (Kempston / QAOP) |
| `IN/OUT` sound / speech / CMOS | stubs / Currah later / ignore |
| NMI + IRQ job timing | Headless: inject; ZX: IM2 → remapped `$26AB` |
| Code at `$0000` | Remapped ORG + source patches (48K) |

## Conversion pipeline

```
ref/berzerk.asm
      │
      ▼
tools/emit_spectrum_asm.py → src/arcade/berzerk.asm + mem_map.inc
tools/headless_berzerk.py  → access report (validate arcade behaviour)
      │
      ▼
src/arcade/host + HAL     → build/arcade.sna
```

**Phase 1:** hand-ported playable shell (`make run`) — still available.

**Phase 2:** PROM image + symbols + I/O map (`convert_ref`).

**Phase 3 (now):** `make` / `make run` build and boot the remapped host
(`src/arcade/host.asm` + `berzerk.asm` + HAL at `$DC00`).

**Phase 4:** harden HAL (frame blit of video shadow, job timing); delete
`src/game/*` hand port when playable.

## Hook points (must stay 1:1 with listing)

| Label | Addr | Action on Spectrum |
|-------|------|--------------------|
| `DRAW_SPRITE` | `$2817` | blit via HAL / magic shadow |
| `ERASE_PATTERN` | `$272D` | erase previous pattern |
| `WRITE_PATTERN` | `$274D` | resolve + draw current pattern |
| `MOVE_ANIMATE_VECTOR` | `$27A9` | keep as-is (pure logic) |
| `RTOAX` / magic addr | `$29A1` / `$29A3` | map (X,Y) → shadow addr |
| `MOVE_PLAYER` stick | `$1EEB` `IN A,($48)` | `input_poll` |
| `CLEAR_SCREEN` | `$1A4E` | clear shadow + `zx_cls` |
| `IRQ_HANDLER` | `$26AB` | frame driver |

## Non-goals (for now)

- Cocktail flip / bookkeeping CMOS UI
- Voice / sound board (stub OK)
- Exact 223-line Y coordinates (scale or clip to 192 with a single documented transform)
