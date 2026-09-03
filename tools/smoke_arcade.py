#!/usr/bin/env python3
"""Headless smoke-run of relocated Berzerk PROM (no ZEsarUX debugger needed).

Uses the `z80` package from tools/.venv. Stubs host hooks at $6000 so we can
see whether cold-start / attract survive without wiping memory or jumping into
Spectrum ROM reset.

  tools/.venv/bin/python tools/smoke_arcade.py [max_instructions]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from z80 import Z80Machine
except ImportError:
    print(
        "error: z80 package missing. Create venv:\n"
        "  python3 -m venv tools/.venv && tools/.venv/bin/pip install z80",
        file=sys.stderr,
    )
    sys.exit(1)

from reloc_rom import (  # noqa: E402
    ARCADE_BASE,
    HOOK_CLEAR_SCREEN,
    HOOK_DRAW_SPRITE,
    HOOK_IN_P1,
    HOOK_IN_SAFE,
    HOOK_IN_STATUS,
    HOOK_NMI,
    HOOK_PRINT_CHAR,
    HOOK_RTOAX,
)


def load_reloc_rom() -> bytearray:
    """Return 16K relocated PROM image (arcade $0000..$3FFF → host $8000)."""
    asm = ROOT / "src/arcade/rom_reloc.asm"
    text = asm.read_text()
    rom = bytearray()
    for line in text.splitlines():
        m = re.match(r"\s*db\s+(.+?)(?:;|$)", line, re.I)
        if not m:
            continue
        for part in m.group(1).split(","):
            part = part.strip()
            if part.startswith("$"):
                rom.append(int(part[1:], 16))
    if len(rom) != 0x4000:
        raise SystemExit(f"rom_reloc.asm parsed to {len(rom)} bytes, expected 16384")
    return rom


def plant_hook_stubs(mem: bytearray) -> None:
    """Minimal host veneers: IN stubs return safe values; everything else RET."""

    def jp(addr: int, dest: int) -> None:
        mem[addr] = 0xC3
        mem[addr + 1] = dest & 0xFF
        mem[addr + 2] = (dest >> 8) & 0xFF

    stub = 0x6100

    def emit(bytes_: list[int]) -> int:
        nonlocal stub
        start = stub
        for b in bytes_:
            mem[stub] = b
            stub += 1
        return start

    ret = emit([0xC9])
    in_zero = emit([0xAF, 0xC9])  # xor a; ret
    in_status = emit([0x3E, 0x01, 0xC9])  # ld a,1; ret (vblank-ish)

    jp(HOOK_DRAW_SPRITE, ret)
    jp(HOOK_CLEAR_SCREEN, ret)
    jp(HOOK_RTOAX, ret)
    jp(HOOK_IN_P1, in_zero)
    jp(HOOK_IN_STATUS, in_status)
    jp(HOOK_NMI, ret)
    jp(HOOK_PRINT_CHAR, ret)
    jp(HOOK_IN_SAFE, in_zero)


def fingerprint(mem, base: int, n: int = 16) -> bytes:
    return bytes(mem[base : base + n])


def main() -> int:
    max_insns = int(sys.argv[1]) if len(sys.argv) > 1 else 200_000
    prom = load_reloc_rom()

    mem = bytearray(65536)
    # zero-fill; PROM + stubs overwrite what they need
    mem[ARCADE_BASE : ARCADE_BASE + 0x4000] = prom
    plant_hook_stubs(mem)

    # Sanity: IM2 vector for Spectrum $FF bus byte (table lives in relocated PROM)
    irq = ARCADE_BASE + 0x26AB
    vec = mem[ARCADE_BASE + 0x37FF] | (mem[ARCADE_BASE + 0x3800] << 8)
    if vec != irq:
        print(f"FAIL: IM2 $37FF vector ${vec:04X}, want ${irq:04X}")
        return 1

    prom_fp = fingerprint(mem, ARCADE_BASE + 0x1602)
    host_fp = fingerprint(mem, 0x6000)

    # Prepend IM2 setup (ld a,$37 / ld i,a / im 2) then jump into cold start.
    setup = 0x6200
    cold = ARCADE_BASE + 0x1602
    mem[setup : setup + 9] = bytes(
        [0x3E, 0x37, 0xED, 0x47, 0xED, 0x5E, 0xC3, cold & 0xFF, cold >> 8]
    )
    assert len(mem) == 65536

    cpu = Z80Machine()
    cpu.set_memory_block(0, bytes(mem))
    cpu.sp = 0xC300
    cpu.pc = setup
    cpu.set_get_int_vector_callback(lambda: 0xFF)

    attract = ARCADE_BASE + 0x164B
    hits = {"attract": 0, "irq": 0, "reset": 0, "hooks": 0}
    pcs: list[int] = []
    ei_seen = False

    for i in range(max_insns):
        pc = cpu.pc
        if i < 48:
            pcs.append(pc)
        if pc == attract:
            hits["attract"] += 1
            ei_seen = True
        if pc == irq:
            hits["irq"] += 1
        if pc == 0x0000:
            hits["reset"] += 1
            print(f"FAIL: PC hit reset $0000 after {i} insns")
            print("recent PCs:", " ".join(f"${p:04X}" for p in pcs[-16:]))
            return 1
        if 0x6000 <= pc < 0x6300:
            hits["hooks"] += 1

        cpu.ticks_to_stop = 1
        cpu.run()

        # Spectrum frame interrupt once boot has reached attract / EI path.
        if ei_seen and i % 512 == 0:
            cpu.on_handle_active_int()

        if i % 5000 == 4999 or i == max_insns - 1:
            cur = cpu.memory
            if fingerprint(cur, ARCADE_BASE + 0x1602) != prom_fp:
                print(f"FAIL: PROM cold-start wiped at insn {i}")
                return 1
            if fingerprint(cur, 0x6000) != host_fp:
                print(f"FAIL: host hook veneers wiped at insn {i}")
                return 1

    print(f"OK: ran {max_insns} instructions")
    print(f"  attract hits: {hits['attract']}")
    print(f"  irq hits:     {hits['irq']}")
    print(f"  hook hits:    {hits['hooks']}")
    print(f"  final PC:     ${cpu.pc:04X} SP=${cpu.sp:04X}")
    print("  first PCs:   ", " ".join(f"${p:04X}" for p in pcs[:24]))
    if hits["attract"] == 0:
        print("WARN: never reached ARC_ATTRACT ($964B) — boot path may be stuck")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
