#!/usr/bin/env python3
"""Headless Berzerk on a faithful arcade memory map.

Loads the PROM from ref/berzerk.asm (via convert_ref), runs under the arcade
address space, stubs I/O, and reports which regions are actually touched.

This is the remap driver described in docs/PORT.md: observe real accesses,
then patch source / labels until writes stay inside a Spectrum-sized budget.

Usage:
  tools/.venv/bin/python tools/headless_berzerk.py
  tools/.venv/bin/python tools/headless_berzerk.py --insns 500000 --json build/arcade_access.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from z80 import Z80Machine
except ImportError:
    print(
        "error: z80 package missing.\n"
        "  python3 -m venv tools/.venv && tools/.venv/bin/pip install z80",
        file=sys.stderr,
    )
    sys.exit(1)

from convert_ref import PATCHES, image, parse  # noqa: E402

# Arcade regions (docs/PORT.md).
REGIONS = [
    ("prom_lo", 0x0000, 0x0800),
    ("scratch_cmos", 0x0800, 0x0C00),
    ("prom_gap", 0x0C00, 0x1000),
    ("prom_hi", 0x1000, 0x3800),
    ("prom_tail", 0x3800, 0x4000),
    ("scratch_pad", 0x4000, 0x4400),
    ("video", 0x4400, 0x6000),
    ("magic_scratch", 0x6000, 0x6400),
    ("magic", 0x6400, 0x8000),
    ("colour", 0x8000, 0x8800),
    ("high_junk", 0x8800, 0x10000),
]

IRQ_HANDLER = 0x26AB
NMI_HANDLER = 0x1721
COLD = 0x1602
ATTRACT = 0x164B


def region_name(addr: int) -> str:
    for name, lo, hi in REGIONS:
        if lo <= addr < hi:
            return name
    return "???"


def load_prom() -> bytearray:
    insns, _ = parse()
    img, _ = image(insns)
    img.update(PATCHES)
    mem = bytearray(65536)
    for a, b in img.items():
        if a < 0x10000:
            mem[a] = b
    return mem


class AccessReport:
    def __init__(self) -> None:
        self.write_counts: dict[str, int] = defaultdict(int)
        self.write_bytes: dict[str, int] = defaultdict(int)  # unique addrs approx via set
        self.write_addrs: dict[str, set[int]] = defaultdict(set)
        self.port_in: dict[int, int] = defaultdict(int)
        self.port_out: dict[int, int] = defaultdict(int)
        self.first_bad: list[tuple[int, int, int]] = []  # pc, addr, val
        self.pc_hits: dict[int, int] = defaultdict(int)

    def note_write(self, pc: int, addr: int, val: int) -> None:
        r = region_name(addr)
        self.write_counts[r] += 1
        self.write_addrs[r].add(addr)
        # "Bad" for Spectrum planning: writes outside guest working set we expect
        # to host. high_junk is the smoking gun for bad absolute immediates.
        if r in ("high_junk", "prom_lo", "prom_hi", "prom_tail", "prom_gap"):
            if len(self.first_bad) < 32:
                self.first_bad.append((pc, addr, val))

    def note_in(self, port: int) -> None:
        self.port_in[port & 0xFF] += 1

    def note_out(self, port: int) -> None:
        self.port_out[port & 0xFF] += 1

    def summary(self) -> dict:
        return {
            "writes_by_region": {
                r: {"ops": self.write_counts[r], "unique": len(self.write_addrs[r])}
                for r in sorted(self.write_counts.keys())
            },
            "ports_in": dict(sorted(self.port_in.items())),
            "ports_out": dict(sorted(self.port_out.items())),
            "first_bad_writes": [
                {"pc": f"${pc:04X}", "addr": f"${addr:04X}", "val": f"${val:02X}",
                 "region": region_name(addr)}
                for pc, addr, val in self.first_bad
            ],
            "hot_pcs": [
                {"pc": f"${pc:04X}", "hits": n}
                for pc, n in sorted(self.pc_hits.items(), key=lambda x: -x[1])[:20]
            ],
        }


def io_in(port: int, report: AccessReport) -> int:
    """Stub arcade ports. Low byte is the board port."""
    p = port & 0xFF
    report.note_in(p)
    if p in (0x48, 0x4A):
        return 0xFF  # active-low sticks idle
    if p == 0x4E:
        # bit0 = bottom-of-screen / vblank-ish for IRQ path
        return 0x01
    if p in (0x49, 0x60, 0x61, 0x65):
        return 0x00  # DIPs / system — stay out of test modes
    if p in (0x4C, 0x4D):
        return 0x00  # NMI enable/disable readbacks
    return 0x00


def io_out(port: int, val: int, report: AccessReport) -> None:
    report.note_out(port & 0xFF)
    # audio / magic control / irq enable — ignored


def run(insns: int, irq_every: int, json_path: Path | None) -> int:
    mem = load_prom()
    report = AccessReport()

    cpu = Z80Machine()
    cpu.set_memory_block(0, bytes(mem))

    def on_write(addr: int, val: int) -> None:
        report.note_write(cpu.pc, addr, val)
        cpu.memory[addr] = val & 0xFF

    cpu.set_write_callback(on_write)
    cpu.set_input_callback(lambda p: io_in(p, report))
    cpu.set_output_callback(lambda p, v: io_out(p, v, report))
    # Arcade IRQ acknowledge supplies $FC → word at $37FC = $26AB
    cpu.set_get_int_vector_callback(lambda: 0xFC)

    # Match board post-IRQ state early so EI is safe during boot experiments.
    setup = bytes([0x3E, 0x37, 0xED, 0x47, 0xED, 0x5E, 0xC3, COLD & 0xFF, COLD >> 8])
    # Park setup in unused PROM gap $0C00
    for i, b in enumerate(setup):
        cpu.memory[0x0C00 + i] = b

    cpu.sp = 0x4300
    cpu.pc = 0x0C00

    hits = {"attract": 0, "irq": 0, "cold": 0, "reset": 0}
    ei_ready = False

    for i in range(insns):
        pc = cpu.pc
        report.pc_hits[pc] += 1
        if pc == COLD:
            hits["cold"] += 1
        if pc == ATTRACT:
            hits["attract"] += 1
            ei_ready = True
        if pc == IRQ_HANDLER:
            hits["irq"] += 1
        if pc == 0x0000 and i > 16:
            hits["reset"] += 1
            break

        cpu.ticks_to_stop = 1
        cpu.run()

        if ei_ready and irq_every > 0 and i % irq_every == 0:
            cpu.on_handle_active_int()

    summary = report.summary()
    summary["hits"] = hits
    summary["insns"] = i + 1
    summary["final"] = {"pc": f"${cpu.pc:04X}", "sp": f"${cpu.sp:04X}"}

    # Spectrum budget check: unique working-set bytes.
    work = 0
    for r in ("scratch_cmos", "scratch_pad", "video", "magic_scratch", "magic", "colour"):
        work += len(report.write_addrs.get(r, ()))
    prom_touch = sum(
        len(report.write_addrs.get(r, ()))
        for r in ("prom_lo", "prom_hi", "prom_tail", "prom_gap")
    )
    summary["spectrum_hint"] = {
        "unique_ram_writes": work,
        "unique_prom_writes": prom_touch,
        "approx_prom_size_bytes": 0x3800 - 0x0C00 + 0x0800,  # hi + lo, ignore gaps
        "fits_40k_guest_plus_hal": work + 14_000 < 40_000,
    }

    print(f"ran {summary['insns']} insns  final PC={summary['final']['pc']} SP={summary['final']['sp']}")
    print(f"hits: cold={hits['cold']} attract={hits['attract']} irq={hits['irq']} reset={hits['reset']}")
    print("writes by region:")
    for r, info in summary["writes_by_region"].items():
        print(f"  {r:16s}  ops={info['ops']:8d}  unique={info['unique']:5d}")
    if summary["first_bad_writes"]:
        print("first writes into PROM / high junk (remap bugs or self-mod):")
        for w in summary["first_bad_writes"][:12]:
            print(f"  PC={w['pc']} -> ({w['region']}) {w['addr']} = {w['val']}")
    print("ports IN :", ", ".join(f"${p:02X}×{n}" for p, n in list(summary["ports_in"].items())[:16]))
    print("ports OUT:", ", ".join(f"${p:02X}×{n}" for p, n in list(summary["ports_out"].items())[:16]))
    hint = summary["spectrum_hint"]
    print(
        f"spectrum hint: unique RAM writes={hint['unique_ram_writes']}  "
        f"prom writes={hint['unique_prom_writes']}  "
        f"fits≈{hint['fits_40k_guest_plus_hal']}"
    )

    if json_path:
        json_path.parent.mkdir(parents=True, exist_ok=True)
        # sets -> lists for JSON
        dump = dict(summary)
        dump["write_addr_samples"] = {
            r: sorted(f"${a:04X}" for a in sorted(report.write_addrs[r])[:64])
            for r in report.write_addrs
        }
        json_path.write_text(json.dumps(dump, indent=2) + "\n")
        print(f"wrote {json_path}")

    if hits["reset"]:
        return 1
    if hits["attract"] == 0:
        return 2
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--insns", type=int, default=200_000, help="instruction budget")
    ap.add_argument("--irq-every", type=int, default=256, help="inject IM2 every N insns after attract (0=off)")
    ap.add_argument("--json", type=Path, help="write access report JSON")
    args = ap.parse_args()
    return run(args.insns, args.irq_every, args.json)


if __name__ == "__main__":
    sys.exit(main())
