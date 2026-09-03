# Berzerk for ZX Spectrum

Port of Stern's Berzerk to the ZX Spectrum 48K (128K if needed later).

Arcade reverse-engineering reference: `ref/berzerk.asm` (Scott Tunstall).

**Port goal:** run the original arcade logic with Spectrum I/O, not a lookalike rewrite.
See [docs/PORT.md](docs/PORT.md).

## Requirements

- **sjasmplus** — Z80 assembler at `tools/bin/sjasmplus` or on `PATH`
- **ZEsarUX** — emulator (looks for `/Applications/Games/zesarux.app` or `/Applications/zesarux.app`)
- **Python 3** — listing converter
- **make**

## Build

```bash
make convert  # ref/berzerk.asm → src/arcade/* + src/game/romdata.asm
make          # → build/berzerk.tap  build/berzerk.sna
make run      # assemble + load .sna in ZEsarUX (48K)
```

## Controls

| Action | Keyboard | Kempston |
|--------|----------|----------|
| Up     | Q        | Up       |
| Down   | A        | Down     |
| Left   | O        | Left     |
| Right  | P        | Right    |
| Fire   | Space    | Fire     |

Attract: push fire to start. Hold fire + direction to shoot.

## Layout

```
docs/PORT.md           arcade flow, memory map, hook plan
ref/berzerk.asm        arcade disassembly (input to converter)
tools/convert_ref.py   listing → ROM image / symbols / I/O map
src/arcade/            generated PROM image + hook stubs (Phase 2)
src/game/              hand-ported shell (Phase 1 — to be retired)
src/zx/                Spectrum HAL (screen, input)
```
