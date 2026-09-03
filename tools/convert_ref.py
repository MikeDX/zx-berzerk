#!/usr/bin/env python3
"""Parse Scott Tunstall's Berzerk disassembly listing into structured records.

The listing mixes several line shapes:

    LABEL:
    1596: C9          ret                        ; comment
    1000:
        10 D1                                    ; bare data continuing from 1000
    ROOM_X   EQU $4345

This module reconstructs the original byte image and keeps the mnemonic text
for each instruction so the source can be re-assembled at a new origin.
"""

import re
import sys
from dataclasses import dataclass, field

REF = "ref/berzerk.asm"

RE_EQU = re.compile(r"^([A-Za-z_][\w.]*)\s+EQU\s+(\S+)", re.I)
RE_LABEL = re.compile(r"^([A-Za-z_][\w.]*):\s*(?:;.*)?$")
RE_ADDR = re.compile(r"^([0-9A-Fa-f]{4}):[ \t]*(.*)$")
RE_HEXBYTE = re.compile(r"^[0-9A-Fa-f]{2}$")

# Every Z80 mnemonic the listing can legitimately produce. Used to tell a real
# instruction line from a data line that happens to have trailing ASCII.
MNEMONICS = {
    "adc", "add", "and", "bit", "call", "ccf", "cp", "cpd", "cpdr", "cpi",
    "cpir", "cpl", "daa", "dec", "di", "djnz", "ei", "ex", "exx", "halt",
    "im", "in", "inc", "ind", "indr", "ini", "inir", "jp", "jr", "ld",
    "ldd", "lddr", "ldi", "ldir", "neg", "nop", "or", "otdr", "otir", "out",
    "outd", "outi", "pop", "push", "res", "ret", "reti", "retn", "rl",
    "rla", "rlc", "rlca", "rld", "rr", "rra", "rrc", "rrca", "rrd", "rst",
    "sbc", "scf", "set", "sla", "sll", "sra", "srl", "sub", "xor",
}


def is_instruction(text):
    if not text:
        return False
    head = re.split(r"[\s,]", text.strip(), maxsplit=1)[0].lower()
    return head in MNEMONICS


@dataclass
class Insn:
    addr: int
    data: bytes
    text: str          # mnemonic + operands, comment stripped
    comment: str = ""
    labels: list = field(default_factory=list)
    is_code: bool = True
    line: int = 0


def split_comment(s):
    """Split trailing ; comment, ignoring ; inside quotes (not used in listing)."""
    i = s.find(";")
    if i < 0:
        return s.rstrip(), ""
    return s[:i].rstrip(), s[i:].rstrip()


def leading_hex(tokens, limit=4):
    """Return the leading run of 2-char hex tokens, at most `limit` of them."""
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
    cursor = None          # address for bare-hex data continuation

    # The listing has an unbalanced "/*" (line 1672) so block comments cannot be
    # tracked by nesting. Strict line patterns plus mnemonic validation are
    # enough: prose inside comment blocks never matches them.
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
                # "1000:" alone -> just sets the cursor for following data
                cursor = addr
                continue
            tail = rest.split(by[-1], 1)[1].strip()
            code = is_instruction(tail)
            # Data rows sometimes trail an ASCII rendering ("Chute 1."); keep
            # the bytes but do not pretend it is an instruction.
            if not code:
                # a data row may list more than 4 bytes
                by = [t for t in toks if RE_HEXBYTE.match(t)]
                if len(by) != len(toks):
                    by = leading_hex(toks, limit=len(toks))
                tail = ""
            data = bytes(int(b, 16) for b in by)
            insns.append(Insn(addr, data, tail, comment, pending_labels, code, lineno))
            pending_labels = []
            cursor = addr + len(data)
            continue

        # Bare hex data line continuing from the last address
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


# The listing omits this byte. It is the width of the third player-walk-left
# frame; every other frame in that table is 1 byte wide, 16 rows tall.
PATCHES = {0x1391: 0x01}

# Regions lifted byte-for-byte from the arcade ROM. Bounds come from the
# labels in the listing; each ends where the next label begins.
REGIONS = [
    ("pat_rom",        0x1000, 0x1400, "sprite patterns + animation frame tables"),
    ("d_tab",          0x2042, 0x2053, "DURL bits -> direction table offset"),
    ("p_tab",          0x2053, 0x2067, "player walk animation tables"),
    ("sr_tab",         0x2067, 0x209D, "player shoot: pattern + bolt spawn deltas"),
    ("m_tab",          0x2519, 0x252D, "direction -> signed X/Y velocity"),
    ("robot_anim_tab", 0x252D, 0x253F, "robot direction -> animation table"),
    ("shoot_tab",      0x2944, 0x297B, "robot shoot table"),
]


def emit_data(img, out):
    w = out.write
    w("; Generated by tools/convert_ref.py -- do not edit.\n")
    w("; Byte-exact data lifted from the Berzerk arcade ROM.\n")
    w(";\n")
    w("; Pointers inside these tables are arcade addresses. Translate them with\n")
    w("; pat_translate (see src/game/pattern.asm) before dereferencing.\n\n")

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


def main():
    insns, equs = parse()
    img, clashes = image(insns)
    code = sum(1 for i in insns if i.is_code)
    print(f"records: {len(insns)} (code {code}, data {len(insns)-code})")
    print(f"equs:    {len(equs)}")
    print(f"bytes:   {len(img)}")
    print(f"clashes: {len(clashes)}")
    for c in clashes[:10]:
        print(f"  ${c[0]:04X}: had {c[1]:02X} got {c[2]:02X} (line {c[3]})")

    g = gaps(img)
    missing = sum(e - s + 1 for s, e in g)
    print(f"\nROM gaps (excluding RAM $0800-$0BFF): {len(g)} regions, {missing} bytes")
    for s, e in g:
        print(f"  ${s:04X}-${e:04X}  ({e-s+1})")

    if len(sys.argv) > 1:
        img.update(PATCHES)
        for name, lo, hi, _ in REGIONS:
            holes = [a for a in range(lo, hi) if a not in img]
            if holes:
                print(f"warning: {name} missing {len(holes)} bytes: "
                      + ", ".join(f"${a:04X}" for a in holes[:8]))
        with open(sys.argv[1], "w") as f:
            emit_data(img, f)
        print(f"\nwrote {sys.argv[1]}")


if __name__ == "__main__":
    sys.exit(main())
