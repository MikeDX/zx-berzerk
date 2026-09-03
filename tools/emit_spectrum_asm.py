#!/usr/bin/env python3
"""Emit Spectrum-targeted Berzerk assembly from ref/berzerk.asm.

Reads Scott Tunstall's arcade listing and writes a recompilable sjasmplus
source whose absolute addresses follow the Spectrum memory map in
docs/PORT.md.

Layout is preserved: every arcade address maps to ZX_PROM+offset (or BSS
for scratch). Instruction sizes stay the same as the arcade ROM so absolute
placement via ORG remains valid. IN ports that need a CALL use trampoline
islands in the $0C00 gap.

  python3 tools/emit_spectrum_asm.py
  python3 tools/emit_spectrum_asm.py -o src/arcade/berzerk.asm
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from convert_ref import PATCHES, image, parse  # noqa: E402
from reloc_rom import insn_len  # noqa: E402

# ---------------------------------------------------------------------------
# Spectrum memory map (must match docs/PORT.md)
# ---------------------------------------------------------------------------

ZX_PROM = 0x6000  # arcade $0000–$3FFF → $6000–$9FFF
ZX_SCRATCH_CMOS = 0xA000  # arcade $0800–$0BFF
ZX_SCRATCH_PAD = 0xA400  # arcade $4000–$43FF
# Video holds full arcade bitmap height so ld bc,$1BFF fills do not overrun.
ZX_VIDEO = 0xA800  # arcade $4400… — 224 lines × 32 = $1C00 → ends $C400
ZX_MAGIC = 0xC400  # arcade $6400 — 192 visible lines × 32 = $1800 → ends $DC00
ZX_MAGIC_SCRATCH = 0xDC00  # arcade $6000–$0BFF; absorbs magic row overrun
ZX_HAL = 0xE000  # host hooks / blit / input
ZX_COLOR = 0xF000  # arcade $8000–$87FF
ZX_STACK = 0xFFFE

# IM2: arcade I=$37 (ACK $FC → $37FC). Spectrum bus is usually $FF, sometimes
# not — a 2-byte vector in PROM at $97FF misses. Host fills page $EE (HAL tail)
# with $EE so any bus byte vectors to $EEEE → ARC_IRQ. `ld a,$37` in the IRQ
# epilogue is rewritten to this page.
ZX_IM2_PAGE = 0xEE

VIDEO_LINES = 224  # storage (arcade 223 + pad); Spectrum shows top 192
VIDEO_STRIDE = 32
VIDEO_SIZE = VIDEO_LINES * VIDEO_STRIDE  # $1C00
MAGIC_LINES = 192
MAGIC_SIZE = MAGIC_LINES * VIDEO_STRIDE  # $1800

HOOK_DRAW_SPRITE = ZX_HAL + 0x00
HOOK_CLEAR_SCREEN = ZX_HAL + 0x03
HOOK_RTOAX = ZX_HAL + 0x06
HOOK_IN_P1 = ZX_HAL + 0x09
HOOK_IN_STATUS = ZX_HAL + 0x0C
HOOK_NMI = ZX_HAL + 0x0F
HOOK_PRINT_CHAR = ZX_HAL + 0x12
HOOK_IN_SYSTEM = ZX_HAL + 0x15
HOOK_GAME_LOOP = ZX_HAL + 0x18
HOOK_OUT_MAGIC = ZX_HAL + 0x1B
HOOK_BOLT_PIXEL = ZX_HAL + 0x1E

ENTRY_HOOKS = {
    0x2817: "HOOK_DRAW_SPRITE",
    0x1A4E: "HOOK_CLEAR_SCREEN",
    # RTOAX at $29A1 is `ld b,$90` then falls into CALCULATE at $29A3.
    0x29A3: "HOOK_RTOAX",
    0x1721: "HOOK_NMI",
    0x29DB: "HOOK_PRINT_CHAR",
    # Room loop: `bit 2,(ix+0); ret z` with MAN_PTR=0 reads Spectrum ROM $0000
    # and leaves the room (clears vectors). Arcade $0000 is NOP — same trap.
    0x2157: "HOOK_GAME_LOOP",
    # `ld (hl),$80` after RTOAX: one shifted XOR pixel, not a raw byte store.
    # Skip ld + IN $4E + rlca (5) so the hook can return carry to the caller.
    0x1578: ("HOOK_BOLT_PIXEL", 5),
}

# Ports → HAL. Active-low inputs idle as $FF. SYSTEM has coin/start keys.
IN_HOOKS = {
    0x48: "HOOK_IN_P1",
    0x4A: "HOOK_IN_P1",
    0x4E: "HOOK_IN_STATUS",
    0x49: "HOOK_IN_SYSTEM",
    0x60: "IDLE_00",  # F3: input/crosshair tests OFF
    0x61: "DIP_F2",   # F2: bonus life $C0, color test off
    0x65: "IDLE_00",  # SW2 free-game bit0 active-HIGH → idle 0
}

# Force-emit ranges as remapped little-endian data words.
DATA_WORD_RANGES = [
    (0x1D31, 0x1D51),  # bytecode opcode → handler jump table
    (0x2053, 0x2067),  # P.TAB — player direction → pattern table
    (0x252D, 0x253F),  # ROBOT_ANIMATION_TABLES
]

# Strided LE pointer tables: remap word at offset 0 of each stride-byte entry.
# (SR.TAB / S.TAB: PatternPtr, XDelta, YDelta, Dir, pad)
DATA_STRIDED_WORD_RANGES = [
    (0x2067, 0x209D, 6),  # SR.TAB — player shoot
    (0x2944, 0x297A, 6),  # S.TAB — robot shoot
]

# Extra pattern-table roots not reachable from the index tables above.
PATTERN_TABLE_SEEDS = [
    0x103B,  # robot explosion (ld bc,$103B in BLAM)
    0x120B,  # Evil Otto animation list
]

# LTABLE ($1AED) pops its return address as a 4-language pointer table.
LTABLE_ADDR = 0x1AED
LTABLE_TABLE_BYTES = 8


def discover_ltable_ranges(rom: bytes) -> list[tuple[int, int]]:
    """Every `call LTABLE` is followed by 8 bytes of code pointers."""
    out: list[tuple[int, int]] = []
    lo, hi = LTABLE_ADDR & 0xFF, (LTABLE_ADDR >> 8) & 0xFF
    for a in range(len(rom) - 3):
        if rom[a] == 0xCD and rom[a + 1] == lo and rom[a + 2] == hi:
            t = a + 3
            out.append((t, t + LTABLE_TABLE_BYTES))
    return out


def is_arcade_prom_ptr(w: int) -> bool:
    """True for still-arcade PROM pointers (not already Spectrum-remapped)."""
    return 0x1000 <= w < 0x4000


def coalesce_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    if not ranges:
        return []
    ranges = sorted(ranges)
    out = [ranges[0]]
    for lo, hi in ranges[1:]:
        plo, phi = out[-1]
        if lo <= phi:
            out[-1] = (plo, max(phi, hi))
        else:
            out.append((lo, hi))
    return out


def remap_strided_le_words(rom: bytearray) -> int:
    """Remap LE pointer at the start of each fixed-stride table entry."""
    n = 0
    for start, end, stride in DATA_STRIDED_WORD_RANGES:
        for a in range(start, end, stride):
            if a + 1 >= end:
                break
            w = rom[a] | (rom[a + 1] << 8)
            if not is_arcade_prom_ptr(w):
                continue
            nw = map_addr(w)
            if nw != w:
                rom[a] = nw & 0xFF
                rom[a + 1] = (nw >> 8) & 0xFF
                n += 1
    return n


def pattern_table_seeds(rom: bytes) -> set[int]:
    seeds = set(PATTERN_TABLE_SEEDS)
    for a in range(0x2053, 0x2067, 2):
        seeds.add(rom[a] | (rom[a + 1] << 8))
    for a in range(0x252D, 0x253F, 2):
        seeds.add(rom[a] | (rom[a + 1] << 8))
    for start, end, stride in DATA_STRIDED_WORD_RANGES:
        for a in range(start, end, stride):
            seeds.add(rom[a] | (rom[a + 1] << 8))
    return {s for s in seeds if is_arcade_prom_ptr(s)}


def remap_pattern_animation_tables(rom: bytearray) -> tuple[int, list[tuple[int, int]]]:
    """Remap sprite pattern tables: BE frame ptrs, then LE restart after $00.

    WRITE_PATTERN / COLLISION load frame pointers as big-endian
    (`ld a,(hl); ld l,(hl+1); ld h,a`). Animation advance treats a lone $00
    as end-of-list and the next two bytes as a little-endian restart pointer.
    """
    n = 0
    covered: list[tuple[int, int]] = []
    visited: set[int] = set()
    queue = list(pattern_table_seeds(rom))

    while queue:
        pc = queue.pop()
        if pc in visited or not is_arcade_prom_ptr(pc):
            continue
        visited.add(pc)
        p = pc
        while p + 1 < 0x4000:
            if rom[p] == 0:
                # End marker; following word is LE restart (may overlap prior frame).
                if p + 2 < 0x4000:
                    w = rom[p + 1] | (rom[p + 2] << 8)
                    if is_arcade_prom_ptr(w):
                        nw = map_addr(w)
                        if nw != w:
                            rom[p + 1] = nw & 0xFF
                            rom[p + 2] = (nw >> 8) & 0xFF
                            n += 1
                        if w not in visited:
                            queue.append(w)
                covered.append((pc, p + 3))
                break
            # Big-endian frame pointer → sprite bitmap
            w = (rom[p] << 8) | rom[p + 1]
            if is_arcade_prom_ptr(w):
                nw = map_addr(w)
                if nw != w:
                    rom[p] = (nw >> 8) & 0xFF
                    rom[p + 1] = nw & 0xFF
                    n += 1
            p += 2
        else:
            covered.append((pc, p))

    return n, coalesce_ranges(covered)

RE_HEX_ADDR = re.compile(r"\$([0-9A-Fa-f]{4})\b")
RE_IN_PORT = re.compile(
    r"^\s*in\s+a\s*,\s*\(\s*\$([0-9A-Fa-f]{2})\s*\)\s*$", re.I
)
RE_OUT_PORT = re.compile(
    r"^\s*out\s+\(\s*\$([0-9A-Fa-f]{2})\s*\)\s*,\s*a\s*$", re.I
)


def map_addr(a: int) -> int:
    """Arcade absolute address → Spectrum address."""
    if a < 0x0800:
        return ZX_PROM + a
    if a < 0x0C00:
        return ZX_SCRATCH_CMOS + (a - 0x0800)
    if a < 0x4000:
        return ZX_PROM + a
    if a < 0x4400:
        return ZX_SCRATCH_PAD + (a - 0x4000)
    if a < 0x4400 + VIDEO_SIZE:
        return ZX_VIDEO + (a - 0x4400)
    if a < 0x6000:
        # Arcade lines past our buffer → last stored line
        return ZX_VIDEO + VIDEO_SIZE - VIDEO_STRIDE + (a & 0x1F)
    if a < 0x6400:
        return ZX_MAGIC_SCRATCH + (a - 0x6000)
    if a < 0x6400 + MAGIC_SIZE:
        return ZX_MAGIC + (a - 0x6400)
    if a < 0x8000:
        return ZX_MAGIC + MAGIC_SIZE - VIDEO_STRIDE + (a & 0x1F)
    if a < 0x8800:
        return ZX_COLOR + (a - 0x8000)
    return a


def is_pointer_imm(nn: int) -> bool:
    if nn < 0x0800:
        return False
    # Packed (X=L, Y=H) for RTOAX — not magic addresses. Remapping $641E
    # (MAN at X=$1E,Y=$64) to $C41E parked the player at Y=$C4 (off-screen).
    if nn in NEVER_REMAP_IMMS:
        return False
    if nn < 0x8800:
        return True
    return False


# ld hl,nn packs used as coordinates (H=Y, L=X), not pointers.
NEVER_REMAP_IMMS = {
    0x641E,  # $1807 set MAN_X/MAN_Y
    0x4438,  # $258B maze generator start (X=$38,Y=$44), not video ptr
}


_REGISH = {
    "a", "b", "c", "d", "e", "h", "l", "i", "r",
    "ix", "iy", "sp", "af", "bc", "de", "hl",
    "ixh", "ixl", "iyh", "iyl",
    "nz", "z", "nc", "po", "pe", "p", "m",
}


def _tok(w: str) -> str:
    return w.lower().strip("()'\"")


def clean_mnemonic(text: str) -> str:
    """Strip English comments glued onto the mnemonic without a ';'."""
    text = text.split(";", 1)[0].rstrip()
    # Corrupted rows: `jr z,$078C               l jump if FIRE...`
    m = re.search(r"^(.*\$[0-9A-Fa-f]{2,4})\s{2,}([A-Za-z].*)$", text)
    if m:
        words = m.group(2).replace(",", " ").split()
        if words:
            w0 = _tok(words[0])
            if w0 not in _REGISH:
                return m.group(1).strip()
            if len(words) >= 2 and _tok(words[1]).isalpha() and _tok(words[1]) not in _REGISH:
                return m.group(1).strip()
    # Normalise `ld hl, -24` → `ld hl,-24` for sjasmplus.
    text = re.sub(r",\s+", ",", text)
    return text.strip()


def rewrite_text_addrs(text: str) -> tuple[str, int]:
    """Rewrite $XXXX in a mnemonic.

    JP/CALL/JR/DJNZ targets always remap across the arcade map (including
    PROM $0000–$07FF). LD-style immediates only remap when they look like
    pointers (>= $0800), so counts like ld bc,$0400 stay put.
    """
    first = text.strip().split(None, 1)[0].lower() if text.strip() else ""
    # jp nz / jr z / call c — first token is the opcode
    ctrl = first in ("jp", "call", "jr", "djnz")
    n = 0

    def repl(m: re.Match) -> str:
        nonlocal n
        old = int(m.group(1), 16)
        if ctrl:
            if old >= 0x8800:
                return m.group(0)
        elif not is_pointer_imm(old):
            return m.group(0)
        new = map_addr(old)
        if new == old:
            return m.group(0)
        n += 1
        return f"${new:04X}"

    # Only rewrite the mnemonic proper; strip a trailing inline comment first.
    code, sep, trail = text.partition(";")
    rewritten = RE_HEX_ADDR.sub(repl, code)
    if sep:
        rewritten = rewritten + sep + trail
    return rewritten, n


def sanitize_label(name: str) -> str:
    out = re.sub(r"[^\w.]", "_", name)
    if out[0].isdigit():
        out = "_" + out
    return out


def emit_mem_inc(path: Path) -> None:
    path.write_text(
        f"""; Generated by tools/emit_spectrum_asm.py — do not edit.
; Spectrum memory map for remapped Berzerk (docs/PORT.md).

ZX_PROM              EQU ${ZX_PROM:04X}
ZX_SCRATCH_CMOS      EQU ${ZX_SCRATCH_CMOS:04X}
ZX_SCRATCH_PAD       EQU ${ZX_SCRATCH_PAD:04X}
ZX_VIDEO             EQU ${ZX_VIDEO:04X}
ZX_MAGIC_SCRATCH     EQU ${ZX_MAGIC_SCRATCH:04X}
ZX_MAGIC             EQU ${ZX_MAGIC:04X}
ZX_HAL               EQU ${ZX_HAL:04X}
ZX_COLOR             EQU ${ZX_COLOR:04X}
ZX_STACK             EQU ${ZX_STACK:04X}
ZX_IM2_PAGE          EQU ${ZX_IM2_PAGE:04X}

HOOK_DRAW_SPRITE     EQU ${HOOK_DRAW_SPRITE:04X}
HOOK_CLEAR_SCREEN    EQU ${HOOK_CLEAR_SCREEN:04X}
HOOK_RTOAX           EQU ${HOOK_RTOAX:04X}
HOOK_IN_P1           EQU ${HOOK_IN_P1:04X}
HOOK_IN_STATUS       EQU ${HOOK_IN_STATUS:04X}
HOOK_NMI             EQU ${HOOK_NMI:04X}
HOOK_PRINT_CHAR      EQU ${HOOK_PRINT_CHAR:04X}
HOOK_IN_SYSTEM       EQU ${HOOK_IN_SYSTEM:04X}
HOOK_GAME_LOOP       EQU ${HOOK_GAME_LOOP:04X}
HOOK_OUT_MAGIC       EQU ${HOOK_OUT_MAGIC:04X}
HOOK_BOLT_PIXEL      EQU ${HOOK_BOLT_PIXEL:04X}

ARC_COLD             EQU ${map_addr(0x1602):04X}
ARC_ATTRACT          EQU ${map_addr(0x164B):04X}
ARC_START_GAME       EQU ${map_addr(0x17B8):04X}
ARC_ROOM_START       EQU ${map_addr(0x209D):04X}
ARC_ROOM_MOVE        EQU ${map_addr(0x2160):04X}
ARC_ROOM_JOBS        EQU ${map_addr(0x21A3):04X}
ARC_IRQ              EQU ${map_addr(0x26AB):04X}
"""
    )


def rewrite_insn_immediates(buf: bytearray) -> int:
    """Remap absolute immediates inside one instruction's bytes."""
    if not buf:
        return 0
    n = 0
    op = buf[0]

    def patch(off: int, require_pointer=False) -> None:
        nonlocal n
        if off + 1 >= len(buf):
            return
        old = buf[off] | (buf[off + 1] << 8)
        if require_pointer and not is_pointer_imm(old):
            return
        new = map_addr(old)
        if new != old:
            buf[off] = new & 0xFF
            buf[off + 1] = (new >> 8) & 0xFF
            n += 1

    if op in (0xC3, 0xCD) or (op >= 0xC0 and (op & 0xC7) in (0xC2, 0xC4)):
        patch(1)
    elif op in (0x01, 0x11, 0x21, 0x31):
        patch(1, require_pointer=True)
    elif op in (0x22, 0x2A, 0x32, 0x3A):
        patch(1)
    elif op == 0xED and len(buf) >= 4:
        patch(2)
    elif op in (0xDD, 0xFD) and len(buf) >= 4 and buf[1] in (0x21, 0x22, 0x2A):
        patch(2, require_pointer=(buf[1] == 0x21))
    return n


def remap_data_words(data: bytearray, *, code_ptrs: bool = False) -> int:
    """Remap aligned pointer words in data tables (even offsets only).

    code_ptrs=True: treat any non-zero word below $8800 as a code/data
    pointer (needed for LTABLE / jump tables that target PROM $0000–$07FF).
    """
    n = 0
    for i in range(0, len(data) - 1, 2):
        w = data[i] | (data[i + 1] << 8)
        if code_ptrs:
            if w == 0 or w >= 0x8800:
                continue
        elif not is_pointer_imm(w):
            continue
        nw = map_addr(w)
        if nw != w:
            data[i] = nw & 0xFF
            data[i + 1] = (nw >> 8) & 0xFF
            n += 1
    return n


def emit_berzerk_asm(path: Path) -> dict:
    insns, equs = parse()
    img, clashes = image(insns)
    img.update(PATCHES)
    rom = bytearray(img.get(a, 0) for a in range(0x4000))
    for a, b in PATCHES.items():
        if a < 0x4000:
            rom[a] = b

    lines: list[str] = []
    a = lines.append

    a("; Generated by tools/emit_spectrum_asm.py — do not edit.")
    a("; Remapped Berzerk from ref/berzerk.asm → Spectrum memory map.")
    a("; See docs/PORT.md.")
    a("")
    a('    IFNDEF _BERZERK_MEM_MAP_INC')
    a("    INCLUDE \"src/arcade/mem_map.inc\"")
    a("    ENDIF")
    a("")
    a("; --- Listing EQUs (address-like values remapped) ---")
    reserved = {
        "ZX_PROM", "ZX_SCRATCH_CMOS", "ZX_SCRATCH_PAD", "ZX_VIDEO",
        "ZX_MAGIC_SCRATCH", "ZX_MAGIC", "ZX_HAL", "ZX_COLOR", "ZX_STACK",
        "HOOK_DRAW_SPRITE", "HOOK_CLEAR_SCREEN", "HOOK_RTOAX", "HOOK_IN_P1",
        "HOOK_IN_STATUS", "HOOK_NMI", "HOOK_PRINT_CHAR", "HOOK_IN_SYSTEM",
        "HOOK_GAME_LOOP", "HOOK_OUT_MAGIC", "HOOK_BOLT_PIXEL",
        "ARC_COLD", "ARC_ATTRACT", "ARC_START_GAME", "ARC_ROOM_START", "ARC_IRQ",
        "ARC_ROOM_MOVE", "ARC_ROOM_JOBS",
    }
    # Collect code labels so EQUs that share a name don't collide.
    code_labels = {sanitize_label(lab) for i in insns for lab in i.labels}
    for name, val in sorted(equs.items(), key=lambda x: x[0].lower()):
        lab = sanitize_label(name)
        if lab in reserved or lab in code_labels:
            a(f"; EQU skipped (name clash): {lab} EQU {val}")
            continue
        vs = val.strip()
        if vs.startswith("$") and len(vs) >= 5:
            try:
                num = int(vs[1:], 16)
                if is_pointer_imm(num):
                    vs = f"${map_addr(num):04X}"
            except ValueError:
                pass
        a(f"{lab:40s} EQU {vs}")
    a("")

    by_addr = {i.addr: i for i in insns if i.addr < 0x4000}
    skip_until = -1
    island_pc = 0x0C00
    islands: list[str] = []
    seen_labels: dict[str, int] = {}

    ltable_ranges = discover_ltable_ranges(rom)
    # Pattern tables before LE index remaps so seeds still see arcade addrs.
    pat_n, pattern_ranges = remap_pattern_animation_tables(rom)
    strided_n = remap_strided_le_words(rom)
    # Already remapped in-place — emit as raw bytes (do not LE-word remap again).
    raw_ranges = coalesce_ranges(
        pattern_ranges
        + [(lo, hi) for lo, hi, _ in DATA_STRIDED_WORD_RANGES]
    )
    word_ranges = list(DATA_WORD_RANGES) + ltable_ranges
    word_ranges.sort()

    stats = {
        "insns": 0,
        "data_records": 0,
        "hooks": 0,
        "in_hooks": 0,
        "rewrites": 0,
        "clashes": len(clashes),
        "ltable_tables": len(ltable_ranges),
        "pattern_ptrs": pat_n,
        "strided_ptrs": strided_n,
    }

    a("; --- Program image @ ZX_PROM (layout-preserving) ---")
    a("    ORG ZX_PROM")
    a("berzerk_prom:")
    a("")

    addr = 0x0000
    while addr < 0x4000:
        if addr < skip_until:
            addr += 1
            continue

        if 0x0800 <= addr < 0x0C00:
            addr = 0x0C00
            continue

        # Reserve arcade $0C00–$0FFF for I/O trampoline islands.
        if 0x0C00 <= addr < 0x1000:
            addr = 0x1000
            continue

        zx = map_addr(addr)
        insn = by_addr.get(addr)

        # Raw ranges already pointer-fixed in `rom` (pattern / strided tables).
        raw = None
        for lo, hi in raw_ranges:
            if lo <= addr < hi:
                raw = (lo, hi)
                break
        if raw is not None:
            lo, hi = raw
            if addr == lo:
                a(f"    ORG ${map_addr(lo):04X}            ; pattern/strided arcade ${lo:04X}-${hi-1:04X}")
                data = rom[lo:hi]
                for base in range(0, len(data), 16):
                    row = ",".join(f"${b:02X}" for b in data[base:base + 16])
                    a(f"    db  {row}")
                stats["data_records"] += 1
            addr = hi
            skip_until = hi
            continue

        # Force word tables the listing mis-disassembled as code.
        forced = None
        for lo, hi in word_ranges:
            if lo <= addr < hi:
                forced = (lo, hi)
                break
        if forced is not None:
            lo, hi = forced
            if addr == lo:
                a(f"    ORG ${map_addr(lo):04X}            ; data words arcade ${lo:04X}-${hi-1:04X}")
                data = bytearray(rom[lo:hi])
                # Jump / LTABLE words may target PROM $0000–$07FF.
                stats["rewrites"] += remap_data_words(data, code_ptrs=True)
                for base in range(0, len(data), 16):
                    row = ",".join(f"${b:02X}" for b in data[base:base+16])
                    a(f"    db  {row}")
                stats["data_records"] += 1
            addr = hi
            skip_until = hi
            continue

        if insn is None:
            # Unlisted PROM byte
            a(f"    ORG ${zx:04X}")
            a(f"    db  ${rom[addr]:02X}")
            addr += 1
            stats["data_records"] += 1
            continue

        for lab in insn.labels:
            base = sanitize_label(lab)
            if base in seen_labels:
                base = f"{base}_{addr:04X}"
            seen_labels[base] = addr
            a(f"{base}:")

        # Entry hooks: JP veneer (3 bytes). Must not let the next listing
        # record overwrite the JP operand (common when the first opcode is 1 byte).
        if addr in ENTRY_HOOKS:
            spec = ENTRY_HOOKS[addr]
            if isinstance(spec, tuple):
                name, skip = spec
            else:
                name = spec
                skip = max(len(insn.data), 3)
            a(f"    ORG ${zx:04X}")
            a(f"    jp  {name}              ; arcade ${addr:04X} hooked")
            stats["hooks"] += 1
            skip_until = insn.addr + skip
            addr = skip_until
            continue

        # IN A,(n)
        if insn.is_code and insn.text:
            m_in = RE_IN_PORT.match(insn.text.strip())
            if m_in:
                port = int(m_in.group(1), 16)
                hook = IN_HOOKS.get(port)
                if hook == "IDLE_FF":
                    a(f"    ORG ${zx:04X}")
                    a(f"    ld  a,$FF               ; was IN (${port:02X}) idle (active-low)")
                    stats["in_hooks"] += 1
                    addr = insn.addr + 2
                    continue
                if hook == "IDLE_00":
                    a(f"    ORG ${zx:04X}")
                    a(f"    ld  a,0                 ; was IN (${port:02X})")
                    stats["in_hooks"] += 1
                    addr = insn.addr + 2
                    continue
                if hook == "DIP_F2":
                    a(f"    ORG ${zx:04X}")
                    a(f"    ld  a,$C0               ; F2 DIPs: bonus 5k+10k")
                    stats["in_hooks"] += 1
                    addr = insn.addr + 2
                    continue
                if hook:
                    next_pc = insn.addr + 2
                    nlen = insn_len(rom, next_pc)
                    stolen = bytearray(rom[next_pc : next_pc + nlen])
                    stats["rewrites"] += rewrite_insn_immediates(stolen)
                    cont = next_pc + nlen
                    isl = island_pc
                    island_pc += 3 + nlen + 3
                    if island_pc > 0x1000:
                        raise SystemExit("I/O island space exhausted in $0C00-$0FFF")

                    stolen_asm = ",".join(f"${b:02X}" for b in stolen)
                    islands.append(
                        f"    ORG ${map_addr(isl):04X}    ; IN (${port:02X}) island "
                        f"from ${addr:04X}\n"
                        f"    call {hook}\n"
                        f"    db  {stolen_asm}\n"
                        f"    jp  ${map_addr(cont):04X}"
                    )
                    a(f"    ORG ${zx:04X}")
                    a(f"    jp  ${map_addr(isl):04X}      ; IN (${port:02X}) → {hook}")
                    # NOP out stolen tail beyond the JP's 3rd byte
                    for i in range(1, nlen):
                        pass  # not emitted; next ORG jumps past via skip
                    skip_until = cont
                    stats["in_hooks"] += 1
                    addr = cont
                    continue

            m_out = RE_OUT_PORT.match(insn.text.strip())
            if m_out and int(m_out.group(1), 16) == 0x4B:
                # Magic control latch (pixel shift in bits 0–2). 2-byte OUT.
                next_pc = insn.addr + 2
                nlen = insn_len(rom, next_pc)
                stolen = bytearray(rom[next_pc : next_pc + nlen])
                stats["rewrites"] += rewrite_insn_immediates(stolen)
                cont = next_pc + nlen
                isl = island_pc
                island_pc += 3 + nlen + 3
                if island_pc > 0x1000:
                    raise SystemExit("I/O island space exhausted in $0C00-$0FFF")
                stolen_asm = ",".join(f"${b:02X}" for b in stolen)
                islands.append(
                    f"    ORG ${map_addr(isl):04X}    ; OUT ($4B) island "
                    f"from ${addr:04X}\n"
                    f"    call HOOK_OUT_MAGIC\n"
                    f"    db  {stolen_asm}\n"
                    f"    jp  ${map_addr(cont):04X}"
                )
                a(f"    ORG ${zx:04X}")
                a(f"    jp  ${map_addr(isl):04X}      ; OUT ($4B) → HOOK_OUT_MAGIC")
                skip_until = cont
                stats["in_hooks"] += 1
                addr = cont
                continue

            rewritten, n = rewrite_text_addrs(clean_mnemonic(insn.text))
            stats["rewrites"] += n
            # Arcade IM2 page $37 → Spectrum page holding remapped table.
            if re.match(r"ld\s+a\s*,\s*\$37\s*$", rewritten, re.I):
                rewritten = f"ld   a,${ZX_IM2_PAGE:02X}"
                stats["rewrites"] += 1
            cmt = insn.comment.strip().lstrip(";").strip()
            raw = insn.text.split(";", 1)[0]
            glue = re.match(r"^.*?\S\s{2,}([A-Za-z].*)$", raw)
            if glue and not cmt:
                g = glue.group(1).strip()
                # Don't treat real operands (`af,af'`, `nz,$1234`) as comments.
                g0 = _tok(g.replace(",", " ").split()[0]) if g else ""
                if g0 and g0 not in _REGISH and not g.startswith("$") and not g.startswith("("):
                    cmt = g
            comment = f" ; {cmt}" if cmt else ""
            a(f"    ORG ${zx:04X}")
            a(f"    {rewritten}{comment}")
            stats["insns"] += 1
            addr = insn.addr + len(insn.data)
            continue

        # Data
        data = bytearray(insn.data)
        # Parser used to drop `ld iy,nn` when a hex byte repeated; still remap
        # those 4-byte IX/IY loads if a record lands here.
        if len(data) == 4 and data[0] in (0xDD, 0xFD) and data[1] == 0x21:
            w = data[2] | (data[3] << 8)
            if is_pointer_imm(w):
                nw = map_addr(w)
                if nw != w:
                    data[2] = nw & 0xFF
                    data[3] = (nw >> 8) & 0xFF
                    stats["rewrites"] += 1
        # Do NOT remap arbitrary data records as pointer words — ASCII strings
        # like "Hi" ($6948) look like magic-RAM addresses and get corrupted.
        # Jump tables are handled via DATA_WORD_RANGES / LTABLE discovery above.
        a(f"    ORG ${zx:04X}            ; arcade ${addr:04X} data")
        for base in range(0, len(data), 16):
            row = ",".join(f"${b:02X}" for b in data[base : base + 16])
            a(f"    db  {row}")
        stats["data_records"] += 1
        addr = insn.addr + len(insn.data)

    if islands:
        a("")
        a("; --- I/O trampoline islands (arcade $0C00 gap) ---")
        for block in islands:
            a(block)

    a("")

    irq = map_addr(0x26AB)
    a("; --- IM2 vectors (I=$37; Spectrum bus $FF, arcade $FC) ---")
    a(f"    ORG ${map_addr(0x37FC):04X}")
    a(f"    dw  ${irq:04X}")
    a(f"    ORG ${map_addr(0x37FF):04X}")
    a(f"    dw  ${irq:04X}")
    a("")
    a("berzerk_prom_end:")
    a(f"    ASSERT berzerk_prom_end <= ZX_SCRATCH_CMOS")
    a("")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    stats["rewrites"] += pat_n + strided_n
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("src/arcade/berzerk.asm"),
        help="Spectrum-targeted assembly output",
    )
    ap.add_argument(
        "--map-inc",
        type=Path,
        default=Path("src/arcade/mem_map.inc"),
        help="Shared EQU include for host + game",
    )
    args = ap.parse_args()

    emit_mem_inc(args.map_inc)
    stats = emit_berzerk_asm(args.output)

    print(f"wrote {args.map_inc}")
    print(f"wrote {args.output}")
    print(
        f"insns={stats['insns']} data={stats['data_records']} "
        f"entry_hooks={stats['hooks']} in_hooks={stats['in_hooks']} "
        f"rewrites={stats['rewrites']} clashes={stats['clashes']} "
        f"ltables={stats['ltable_tables']} "
        f"pattern_ptrs={stats['pattern_ptrs']} "
        f"strided_ptrs={stats['strided_ptrs']}"
    )
    print(f"ARC_COLD=${map_addr(0x1602):04X}  ARC_IRQ=${map_addr(0x26AB):04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
