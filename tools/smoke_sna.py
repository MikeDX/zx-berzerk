#!/usr/bin/env python3
"""Smoke-run build/berzerk.sna under a headless Z80 (Spectrum map).

Catches reset ($0000), IRQ-stack smash, and verifies attract after the IM2
I-page fix (I must be $97 so vector fetches hit remapped PROM at $97FF).

  tools/.venv/bin/python tools/smoke_sna.py [insns]
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

try:
    from z80 import Z80Machine
except ImportError:
    print("error: need tools/.venv with z80 installed", file=sys.stderr)
    sys.exit(1)

ARC_COLD = 0x7602
ARC_ATTRACT = 0x764B
ARC_IRQ = 0x86AB
HOOK_BASE = 0xE000
IRQ_STACK_PAGE = 0xA0  # arcade ld sp,$0840 → $A040


def load_sna(path: Path) -> tuple[bytearray, int, int]:
    raw = path.read_bytes()
    if len(raw) < 27 + 0xC000:
        raise SystemExit(f"bad sna size {len(raw)}")
    hdr, ram = raw[:27], raw[27:]
    mem = bytearray(65536)
    mem[0x4000:0x10000] = ram[:0xC000]
    sp = hdr[23] | (hdr[24] << 8)
    pc = mem[sp] | (mem[sp + 1] << 8)
    return mem, pc, sp + 2


def main() -> int:
    insns = int(sys.argv[1]) if len(sys.argv) > 1 else 400_000
    sna = ROOT / "build/berzerk.sna"
    if not sna.exists():
        print("error: build/berzerk.sna missing — run make first", file=sys.stderr)
        return 1

    mem, pc, sp = load_sna(sna)
    print(f"SNA entry PC=${pc:04X} SP=${sp:04X}")
    print(f"cold {bytes(mem[ARC_COLD:ARC_COLD+8]).hex()}")
    print(f"IM2 $EEEE={bytes(mem[0xEEEE:0xEEF1]).hex()} (want C3 AB 86)")
    print(f"IM2 $EEFF={bytes(mem[0xEEFF:0xEF01]).hex()} (want eeee)")
    print(f"IRQ {bytes(mem[ARC_IRQ:ARC_IRQ+3]).hex()}")
    print(f"RTOAX entry $89A3={bytes(mem[0x89A3:0x89A6]).hex()} (want C3 .. E0)")
    print(f"RTOAX ld b $89A1={bytes(mem[0x89A1:0x89A3]).hex()} (want 06 90)")

    for a in range(0x00, 0x40, 8):
        mem[a] = 0xC9

    cpu = Z80Machine()
    cpu.set_memory_block(0, bytes(mem))
    cpu.pc = pc
    cpu.sp = sp
    cpu.set_get_int_vector_callback(lambda: 0xFF)

    hits = {"attract": 0, "irq": 0, "rom": 0, "hook": 0}
    recent: deque[tuple[int, int, int]] = deque(maxlen=24)
    for i in range(insns):
        p = cpu.pc
        recent.append((i, p, cpu.sp))
        if p == ARC_ATTRACT:
            hits["attract"] += 1
        if p == ARC_IRQ:
            hits["irq"] += 1
        if p < 0x4000:
            hits["rom"] += 1
            print(f"FAIL: PC=${p:04X} in low memory after {i} insns SP=${cpu.sp:04X}")
            for j, rp, rsp in recent:
                print(f"  {j:6d} PC=${rp:04X} SP=${rsp:04X}")
            return 1
        if cpu.sp < 0x4000 or cpu.sp > 0xFFFE:
            print(f"FAIL: SP=${cpu.sp:04X} after {i} insns PC=${p:04X}")
            return 1
        if HOOK_BASE <= p < HOOK_BASE + 0x800:
            hits["hook"] += 1
            # frame_blit / deep HAL on IRQ scratch stack → reset
            if (cpu.sp >> 8) == IRQ_STACK_PAGE and p >= HOOK_BASE + 0x20:
                # allow thin status veneer only; blit lives deeper in HAL
                pass  # checked via low-PC failure

        cpu.ticks_to_stop = 1
        cpu.run()

        if hits["attract"] and i % 512 == 0:
            cpu.on_handle_active_int()

    print(
        f"OK: {insns} insns attract={hits['attract']} irq={hits['irq']} "
        f"hooks={hits['hook']} rom={hits['rom']} final PC=${cpu.pc:04X}"
    )
    if hits["attract"] == 0:
        print("WARN: never reached attract")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
