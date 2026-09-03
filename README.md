# Berzerk for ZX Spectrum

Port of Stern's Berzerk to the ZX Spectrum 48K (128K if needed later).

Arcade reverse-engineering reference: `ref/berzerk.asm` (Scott Tunstall).

## Requirements

- **sjasmplus** — Z80 assembler at `tools/bin/sjasmplus` or on `PATH`
- **ZEsarUX** — emulator (looks for `/Applications/Games/zesarux.app` or `/Applications/zesarux.app`)
- **make**

If you have a sjasmplus binary elsewhere:

```bash
mkdir -p tools/bin
cp /path/to/sjasmplus tools/bin/
```

## Build

```bash
make          # → build/berzerk.tap  build/berzerk.sna
make run      # assemble + load .sna in ZEsarUX (48K)
make tap      # assemble + insert .tap in ZEsarUX
make clean
```

## Controls (phase-0 demo)

| Action | Keyboard | Kempston |
|--------|----------|----------|
| Up     | Q        | Up       |
| Down   | A        | Down     |
| Left   | O        | Left     |
| Right  | P        | Right    |
| Fire   | Space    | Fire     |

Keys are remappable via the `keymap` table in `src/zx/input.asm` (redefine UI later).

## Layout

```
src/main.asm       entry, BASIC loader, artefacts
src/zx/            Spectrum HAL (screen, input, …)
src/demo.asm       phase-0 smoke test
ref/berzerk.asm    arcade disassembly (reference only)
tools/sjasm/       sjasmplus helpers (BasicLib)
tools/bin/         optional local sjasmplus binary (gitignored)
build/             generated images
```
