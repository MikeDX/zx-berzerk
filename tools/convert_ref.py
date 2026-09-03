#!/usr/bin/env python3
"""Parse Scott Tunstall's Berzerk disassembly and emit Spectrum port artefacts.

Outputs (see docs/PORT.md):

  romdata.asm     — sprite/anim tables for the hand-ported shell (legacy)
  rom_image.asm   — full PROM byte image $0000–$3FFF for the arcade host
  symbols.asm     — LABEL EQU $addr for every listing label
  io_map.inc      — IN/OUT ports touched by the ROM (hook checklist)

Usage:
  python3 tools/convert_ref.py                 # coverage report only
  python3 tools/convert_ref.py --emit src/arcade
  python3 tools/convert_ref.py src/game/romdata.asm   # legacy single-file data
"""

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REF = "ref/berzerk.asm"

RE_EQU = re.compile(r"^([A-Za-z_][\w.]*)\s+EQU\s+(\S+)", re.I)
RE_LABEL = re.compile(r"^([A-Za-z_][\w.]*):\s*(?:;.*)?$")
RE_ADDR = re.compile(r"^([0-9A-Fa-f]{4}):[ \t]*(.*)$")
RE_HEXBYTE = re.compile(r"^[0-9A-Fa-f]{2}$")
RE_PORT = re.compile(r"\((\$[0-9A-Fa-f]{2}|[0-9A-Fa-f]{2}h?)\)", re.I)

MNEMONICS = {
    "adc", "add", "and", "bit", "call", "ccf", "cp", "cpd", "cpdr", "cpi",
    "cpir", "cpl", "daa", "dec", "di", "djnz", "ei", "ex", "exx", "halt",
    "im", "in", "inc", "ind", "indr", "ini", "inir", "jp", "jr", "ld",
    "ldd", "lddr", "ldi", "ldir", "neg", "nop", "or", "otdr", "otir", "out",
    "outd", "outi", "pop", "push", "res", "ret", "reti", "retn", "rl",
    "rla", "rlc", "rlca", "rld", "rr", "rra", "rrc", "rrca", "rrd", "rst",
    "sbc", "scf", "set", "sla", "sll", "sra", "srl", "sub", "xor",
}

# Listing hole: third left-walk frame width.
PATCHES = {0x1391: 0x01}

# Hand-port data slices (legacy).
REGIONS = [
    ("pat_rom",        0x1000, 0x1400, "sprite patterns + animation frame tables"),
    ("d_tab",          0x2042, 0x2053, "DURL bits -> direction table offset"),
    ("p_tab",          0x2053, 0x2067, "player walk animation tables"),
    ("sr_tab",         0x2067, 0x209D, "player shoot: pattern + bolt spawn deltas"),
    ("m_tab",          0x2519, 0x252D, "direction -> signed X/Y velocity"),
    ("robot_anim_tab", 0x252D, 0x253F, "robot direction -> animation table"),
    ("shoot_tab",      0x2944, 0x297B, "robot shoot table"),
]

# Sites the Spectrum host must intercept (docs/PORT.md).
HOOKS = [
    (0x2817, "DRAW_SPRITE", "blit width/height pattern at Magic RAM ptr"),
    (0x272D, "ERASE_PATTERN", "erase previous pattern"),
    (0x274D, "WRITE_PATTERN", "resolve + draw current pattern"),
    (0x27A9, "MOVE_ANIMATE_VECTOR", "TIME/pos/anim advance (keep)"),
    (0x29A1, "RTOAX", "pixel -> Magic address, XOR mode"),
    (0x29A3, "CALCULATE_MAGIC_IMAGE_RAM_ADDRESS", "X,Y -> Magic address"),
    (0x1A4E, "CLEAR_SCREEN", "clear bitmap + colour"),
    (0x2540, "MAZE_BUILD", "room maze (keep logic, hook draws)"),
    (0x164B, "ATTRACT_LOOP", "coin/attract entry"),
    (0x17B8, "START_GAME", "after credit / start"),
    (0x209D, "ROOM_START", "clear + maze + spawn"),
    (0x1721, "NMI_HANDLER", "audio/speech; stub on ZX"),
    (0x26AB, "IRQ_HANDLER", "bottom-of-screen; drive from halt/IM2"),
]


@dataclass
class Insn:
    addr: int
    data: bytes
    text: str
    comment: str = ""
    labels: list = field(default_factory=list)
    is_code: bool = True
    line: int = 0


def is_instruction(text):
    if not text:
        return False
    head = re.split(r"[\s,]", text.strip(), maxsplit=1)[0].lower()
    return head in MNEMONICS


def split_comment(s):
    i = s.find(";")
    if i < 0:
        return s.rstrip(), ""
    return s[:i].rstrip(), s[i:].rstrip()


def leading_hex(tokens, limit=4):
    out = []
    for t in tokens[:limit]:
        if RE_HEXBYTE.match(t):
            out.append(t)
        else:
            break
    return out


def parse(path=REF):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    insns = []
    equs = {}
    pending_labels = []
    cursor = None

    for lineno, raw in enumerate(lines, 1):
        s = raw.rstrip()
        st = s.strip()

        if not st or st.startswith(";") or st.startswith("/*") or st.startswith("*/"):
            continue

        m = RE_EQU.match(st)
        if m:
            equs[m.group(1)] = m.group(2)
            continue

        m = RE_LABEL.match(st)
        if m:
            pending_labels.append(m.group(1))
            continue

        m = RE_ADDR.match(s)
        if m:
            addr = int(m.group(1), 16)
            rest, comment = split_comment(m.group(2))
            toks = rest.split()
            by = leading_hex(toks)
            if not by:
                cursor = addr
                continue
            tail = rest.split(by[-1], 1)[1].strip()
            code = is_instruction(tail)
            if not code:
                by = [t for t in toks if RE_HEXBYTE.match(t)]
                if len(by) != len(toks):
                    by = leading_hex(toks, limit=len(toks))
                tail = ""
            data = bytes(int(b, 16) for b in by)
            insns.append(Insn(addr, data, tail, comment, pending_labels, code, lineno))
            pending_labels = []
            cursor = addr + len(data)
            continue

        if cursor is not None:
            rest, comment = split_comment(st)
            toks = rest.split()
            if toks and all(RE_HEXBYTE.match(t) for t in toks):
                data = bytes(int(t, 16) for t in toks)
                insns.append(Insn(cursor, data, "", comment, pending_labels, False, lineno))
                pending_labels = []
                cursor += len(data)
                continue

    return insns, equs


def image(insns):
    img = {}
    clashes = []
    for i in insns:
        for k, b in enumerate(i.data):
            a = i.addr + k
            if a in img and img[a] != b:
                clashes.append((a, img[a], b, i.line))
            img[a] = b
    return img, clashes


def gaps(img, lo=0x0000, hi=0x4000, skip=((0x0800, 0x0C00),)):
    out = []
    start = None
    for a in range(lo, hi):
        if any(s <= a < e for s, e in skip):
            if start is not None:
                out.append((start, a - 1))
                start = None
            continue
        if a not in img:
            if start is None:
                start = a
        elif start is not None:
            out.append((start, a - 1))
            start = None
    if start is not None:
        out.append((start, hi - 1))
    return out


def label_map(insns):
    """addr -> [labels]"""
    m = defaultdict(list)
    for i in insns:
        for lab in i.labels:
            m[i.addr].append(lab)
    return m


def collect_io(insns):
    ports = defaultdict(list)
    for i in insns:
        if not i.is_code:
            continue
        t = i.text.lower()
        if not (t.startswith("in ") or t.startswith("out ")):
            continue
        m = RE_PORT.search(i.text)
        if not m:
            continue
        raw = m.group(1)
        if raw.startswith("$"):
            port = int(raw[1:], 16)
        else:
            port = int(raw.rstrip("hH"), 16)
        ports[port].append((i.addr, i.text.strip(), i.comment))
    return ports


def emit_data(img, out):
    w = out.write
    w("; Generated by tools/convert_ref.py -- do not edit.\n")
    w("; Byte-exact data lifted from the Berzerk arcade ROM.\n\n")
    for name, lo, hi, desc in REGIONS:
        w(f"; {desc}\n")
        w(f"{name.upper()}_ORG    EQU ${lo:04X}\n")
        w(f"{name}:\n")
        for base in range(lo, hi, 16):
            row = []
            for a in range(base, min(base + 16, hi)):
                b = img.get(a)
                row.append("$00" if b is None else f"${b:02X}")
            w(f"    db  {','.join(row)}".ljust(76) + f"; ${base:04X}\n")
        w(f"{name}_end:\n")
        w(f"    ASSERT {name}_end - {name} == {hi - lo}\n\n")


def emit_rom_image(img, out):
    w = out.write
    w("; Generated by tools/convert_ref.py -- do not edit.\n")
    w("; Full Berzerk program PROM image ($0000-$3FFF).\n")
    w("; Scratch/CMOS $0800-$0BFF is omitted (runtime RAM on host).\n")
    w("; Missing listing bytes are 0; see PATCHES in convert_ref.py.\n\n")
    w("    MODULE arcade_rom\n\n")
    w("arcade_rom_base:\n")
    for base in range(0x0000, 0x4000, 16):
        if 0x0800 <= base < 0x0C00:
            if base == 0x0800:
                w(f"    ; $0800-$0BFF: scratch/CMOS — not in PROM image\n")
                w(f"    ds  1024\n")
            continue
        row = []
        for a in range(base, base + 16):
            row.append(f"${img.get(a, 0):02X}")
        w(f"    db  {','.join(row)}".ljust(76) + f"; ${base:04X}\n")
    w("arcade_rom_end:\n")
    w("    ASSERT arcade_rom_end - arcade_rom_base == $4000\n")
    w("    ENDMODULE\n")


def emit_symbols(insns, equs, out):
    w = out.write
    w("; Generated by tools/convert_ref.py -- do not edit.\n")
    w("; Arcade listing labels and EQUs (addresses are original ROM).\n")
    w("; When relocating, add ARCADE_BASE to code/data symbols in $0000-$3FFF.\n\n")
    w("; --- EQUs from listing ---\n")
    for name, val in sorted(equs.items(), key=lambda x: x[0]):
        w(f"{name:40s} EQU {val}\n")
    w("\n; --- Code/data labels ---\n")
    labs = label_map(insns)
    for addr in sorted(labs):
        for lab in labs[addr]:
            # Avoid clashing with sjasmplus BasicLib (s_tab etc.) by prefixing.
            safe = lab if not lab.lower().startswith("s_tab") else "ARC_" + lab
            w(f"{safe:40s} EQU ${addr:04X}\n")
    w("\n; --- Required Spectrum hook sites ---\n")
    for addr, name, note in HOOKS:
        w(f"; ${addr:04X}  {name}: {note}\n")
        w(f"HOOK_{name:36s} EQU ${addr:04X}\n")


def emit_io_map(ports, out):
    w = out.write
    w("; Generated by tools/convert_ref.py -- do not edit.\n")
    w("; I/O ports referenced by the arcade ROM. Implement or stub each.\n\n")
    notes = {
        0x44: "VOICE_PORT",
        0x48: "P1 controls (active-low DURL+FIRE) — map to input_poll",
        0x49: "SYSTEM / coin / cabinet",
        0x4A: "P2 controls / DIP",
        0x4C: "NMI enable",
        0x4E: "Magic collision / screen status — map to wall-mask test",
        0x60: "F3 switches",
        0x65: "SW2 bookkeeping / coin",
    }
    for port in sorted(ports):
        note = notes.get(port, "")
        w(f"; ${port:02X}  {note}\n")
        for addr, text, cmt in ports[port][:8]:
            w(f";   ${addr:04X}: {text}  {cmt}\n")
        if len(ports[port]) > 8:
            w(f";   ... {len(ports[port]) - 8} more\n")
        w("\n")


def emit_hooks_stub(out):
    w = out.write
    w("; Spectrum I/O hooks for the arcade host.\n")
    w("; These replace Magic RAM / ports. Wire from a relocated ROM or CALL patches.\n")
    w("; See docs/PORT.md.\n\n")
    w("; Placeholder: the hand-ported shell still owns gameplay.\n")
    w("; Next step: jump into HOOK_ATTRACT_LOOP / HOOK_START_GAME with\n")
    w("; DRAW_SPRITE / RTOAX / IN $48 intercepted.\n\n")
    w("arcade_hooks_ready:\n")
    w("    xor     a\n")
    w("    ret\n")


def report(insns, equs, img, clashes):
    code = sum(1 for i in insns if i.is_code)
    print(f"records: {len(insns)} (code {code}, data {len(insns)-code})")
    print(f"equs:    {len(equs)}")
    print(f"labels:  {sum(len(i.labels) for i in insns)}")
    print(f"bytes:   {len(img)}")
    print(f"clashes: {len(clashes)}")
    for c in clashes[:10]:
        print(f"  ${c[0]:04X}: had {c[1]:02X} got {c[2]:02X} (line {c[3]})")
    g = gaps(img)
    missing = sum(e - s + 1 for s, e in g)
    print(f"\nROM gaps (excl. $0800-$0BFF): {len(g)} regions, {missing} bytes")
    for s, e in g:
        print(f"  ${s:04X}-${e:04X}  ({e-s+1})")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("legacy_out", nargs="?", help="legacy romdata.asm path")
    ap.add_argument("--emit", metavar="DIR", help="write arcade artefacts into DIR")
    ap.add_argument("--ref", default=REF)
    args = ap.parse_args()

    insns, equs = parse(args.ref)
    img, clashes = image(insns)
    report(insns, equs, img, clashes)

    filled = dict(img)
    filled.update(PATCHES)

    if args.legacy_out:
        with open(args.legacy_out, "w") as f:
            emit_data(filled, f)
        print(f"\nwrote {args.legacy_out}")

    if args.emit:
        d = Path(args.emit)
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "rom_image.asm", "w") as f:
            emit_rom_image(filled, f)
        with open(d / "symbols.asm", "w") as f:
            emit_symbols(insns, equs, f)
        with open(d / "io_map.inc", "w") as f:
            emit_io_map(collect_io(insns), f)
        with open(d / "hooks.asm", "w") as f:
            emit_hooks_stub(f)
        print(f"\nwrote {d}/rom_image.asm symbols.asm io_map.inc hooks.asm")

    return 0


if __name__ == "__main__":
    sys.exit(main())
