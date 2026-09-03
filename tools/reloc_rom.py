#!/usr/bin/env python3
"""Relocate Berzerk PROM absolute addresses for the ZX Spectrum host.

Memory map (48K host — see docs/PORT.md):

  $5B00–$5FFF   host stack / vars
  $6000–$7FFF   host code (hooks, ZX HAL)
  $8000–$BFFF   relocated PROM  (ARCADE_BASE = $8000)
  $C000–$C3FF   arcade scratch $4000–$43FF
  $C400–$C7FF   arcade scratch $0800–$0BFF
  $C800–$DFFF   fake video     $4400–$5BFF (192 lines × 32)
  $E000–$F7FF   fake magic     $6000–$77FF
  $F800–$FFFF   colour stub / spare

Walks the PROM with a Z80 length table and rewrites 16-bit absolute
operands that land in remapped ranges. Then plants JP hooks at known
routine entry points.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

# Allow `from convert_ref import ...` when run as a script.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from convert_ref import PATCHES, parse, image  # noqa: E402

ARCADE_BASE = 0x8000
SCRATCH_4000 = 0xC000
SCRATCH_0800 = 0xC400
VIDEO_BASE = 0xC800
MAGIC_BASE = 0xE000
COLOR_BASE = 0xF800

# Hook trampoline slots inside the host (filled at assemble time via symbols).
# We patch PROM entry points to `JP nn` and emit a reloc table the host fills,
# OR we patch to fixed host addresses once known.
#
# Fixed host hook addresses (must match src/arcade/host_mem.inc):
HOOK_DRAW_SPRITE = 0x6000
HOOK_CLEAR_SCREEN = 0x6003
HOOK_RTOAX = 0x6006
HOOK_IN_P1 = 0x6009
HOOK_IN_STATUS = 0x600C
HOOK_NMI = 0x600F
HOOK_PRINT_CHAR = 0x6012
HOOK_IN_SAFE = 0x6015          # IN ports that should return 0

# PROM entry points (arcade addresses) replaced with JP hook.
ENTRY_PATCHES = [
    (0x2817, HOOK_DRAW_SPRITE),     # DRAW_SPRITE
    (0x1A4E, HOOK_CLEAR_SCREEN),    # CLEAR_SCREEN
    (0x29A1, HOOK_RTOAX),           # RTOAX
    (0x29A3, HOOK_RTOAX),           # CALCULATE_MAGIC…
    (0x1721, HOOK_NMI),             # NMI_HANDLER (also CALLed from cold start!)
    (0x29DB, HOOK_PRINT_CHAR),      # PRINT_CHAR
]

# Ports diverted to hooks. Unlisted INs float and can jump into test modes.
IN_PORT_HOOKS = {
    0x48: HOOK_IN_P1,
    0x4A: HOOK_IN_P1,
    0x4E: HOOK_IN_STATUS,
    0x49: HOOK_IN_SAFE,   # SYSTEM
    0x60: HOOK_IN_SAFE,   # F3 / crosshair DIP
    0x65: HOOK_IN_SAFE,   # SW2
}

# IN A,(n) → RST 8 / or replace with CALL. We rewrite DB nn (IN A,(n))
# to CD lo hi CALL hook. IN A,(n) is 2 bytes; CALL is 3 — need space.
# Instead: replace IN A,($48) with RST $28 (1 byte) + NOP, vector at $28
# points into host. Spectrum ROM owns $00-$3FFF though — our PROM is at
# $8000, so RST won't work from relocated code (RST still jumps to $0028!).
#
# Use illegal/unused FD CB prefix? Simplest: scan for DB 48 and rewrite
# the preceding/surrounding to CALL by overwriting a nearby NOP, or
# replace three-byte sequences.
#
# Pattern at MOVE_PLAYER: DB 48 = IN A,($48). Previous bytes vary.
# Replace IN A,($48) [DB 48] with CALL HOOK_IN_P1 by expanding:
# We patch specific known sites with CALL (3 bytes) overwriting IN+next
# when next is safe, else JP to a stub island inside PROM gaps.
#
# PROM gap $0C00-$0FFF and $3800-$3FFF are free islands after relocate.

IO_IN_SITES = {
    # addr of the IN opcode → port
}


def map_addr(a: int) -> int:
    """Translate an arcade absolute address to the Spectrum host map."""
    if a < 0x0800:
        return ARCADE_BASE + a
    if a < 0x0C00:
        return SCRATCH_0800 + (a - 0x0800)
    if a < 0x4000:
        return ARCADE_BASE + a
    if a < 0x4400:
        return SCRATCH_4000 + (a - 0x4000)
    if a < 0x5C00:  # video clipped to 192 lines (6K)
        return VIDEO_BASE + (a - 0x4400)
    if a < 0x6000:
        # remainder of arcade video (lines 192–223) → clamp into last line
        return VIDEO_BASE + 0x17E0 + (a & 0x1F)
    if a < 0x7800:
        return MAGIC_BASE + (a - 0x6000)
    if a < 0x8000:
        return MAGIC_BASE + 0x17E0 + (a & 0x1F)
    if a < 0x8800:
        return COLOR_BASE + (a - 0x8000)
    # Pointers into high RAM that the game uses as working storage — leave
    # unchanged only if already in host space; otherwise wrap into scratch.
    return a


# ---- Z80 instruction length (undocumented opcodes approximated) ----

def _xx_len(op: int) -> int:
    """Length of instruction given first opcode byte (no CB/DD/ED/FD)."""
    # ld r,r' / alu r / etc 1 byte
    if op < 0x40:
        # 00 000 xxx etc
        row, col = op >> 3, op & 7
        if op in (0x00, 0x07, 0x0F, 0x17, 0x1F, 0x27, 0x2F, 0x37, 0x3F):
            return 1
        if op in (0x02, 0x0A, 0x12, 0x1A, 0x22, 0x2A, 0x32, 0x3A):
            # ld (bc),a / ld a,(bc) / ld (de),a / ld a,(de) /
            # ld (nn),hl / ld hl,(nn) / ld (nn),a / ld a,(nn)
            if op in (0x22, 0x2A, 0x32, 0x3A):
                return 3
            return 1
        if (op & 0xC7) == 0x06:  # ld r,n
            return 2
        if (op & 0xCF) == 0x01:  # ld rr,nn
            return 3
        if (op & 0xC7) == 0x04 or (op & 0xC7) == 0x05:  # inc/dec r
            return 1
        if (op & 0xCF) == 0x03 or (op & 0xCF) == 0x0B:  # inc/dec rr
            return 1
        if (op & 0xCF) == 0x09:  # add hl,rr
            return 1
        if op in (0x08,):
            return 1
        if (op & 0xC7) == 0x00 and op != 0:  # nop already, djnz/jr
            pass
        if op in (0x10, 0x18, 0x20, 0x28, 0x30, 0x38):  # jr*
            return 2
        return 1
    if op < 0x80:
        return 1  # ld r,r' / halt
    if op < 0xC0:
        return 1  # alu
    # C0–FF
    if op in (0xC3, 0xC2, 0xCA, 0xD2, 0xDA, 0xE2, 0xEA, 0xF2, 0xFA):  # jp*
        return 3
    if op in (0xCD, 0xC4, 0xCC, 0xD4, 0xDC, 0xE4, 0xEC, 0xF4, 0xFC):  # call*
        return 3
    if op in (0xC9, 0xC0, 0xC8, 0xD0, 0xD8, 0xE0, 0xE8, 0xF0, 0xF8,
              0xC1, 0xC5, 0xD1, 0xD5, 0xE1, 0xE5, 0xF1, 0xF5,
              0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF,
              0xD9, 0xEB, 0xF3, 0xFB, 0xE3, 0xF9, 0x08):
        return 1
    if op in (0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE, 0xDB, 0xD3):
        return 2  # alu n / in a,(n) / out (n),a
    if op == 0xCB:
        return 2
    if op == 0xED:
        return 2  # most; some 4 — handled specially
    if op in (0xDD, 0xFD):
        return 2  # most; some 3/4 — handled specially
    if (op & 0xC7) == 0xC7:
        return 1  # rst
    return 1


def insn_len(rom: bytearray, pc: int) -> int:
    if pc >= len(rom):
        return 1
    op = rom[pc]
    if op == 0xCB:
        return 2
    if op == 0xED:
        if pc + 1 >= len(rom):
            return 2
        op2 = rom[pc + 1]
        # ld rr,(nn) / ld (nn),rr / etc
        if op2 in (0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B):
            return 4
        return 2
    if op in (0xDD, 0xFD):
        if pc + 1 >= len(rom):
            return 2
        op2 = rom[pc + 1]
        if op2 == 0xCB:
            return 4
        if op2 in (0x21, 0x22, 0x2A, 0x36, 0x34, 0x35):
            # ld ix,nn / ld (nn),ix / ld ix,(nn) / ld (ix+d),n
            if op2 == 0x36:
                return 4
            if op2 in (0x21, 0x22, 0x2A):
                return 4
            return 3
        if op2 in (0x34, 0x35) or (0x70 <= op2 <= 0x77) or (op2 & 0xC7) == 0x46:
            return 3  # (ix+d)
        if op2 in (0x09, 0x19, 0x29, 0x39, 0x23, 0x2B, 0xE1, 0xE3, 0xE5, 0xE9, 0xF9):
            return 2
        if (op2 & 0xC7) == 0x06:  # ld r,(ix+d) already / ld (ix+d),r
            return 3
        # fallback
        if op2 in (0x22, 0x2A, 0x21):
            return 4
        return 2
    return _xx_len(op)


def is_pointer_imm(nn: int) -> bool:
    """Reject small immediates (counts, bitmasks) that are not addresses."""
    if nn < 0x0800:
        return False
    # Likely pointer into scratch / video / magic / colour / PROM
    if nn < 0x4000:
        return True  # PROM code/data pointer
    if nn < 0x8800:
        return True
    return False


def rewrite_abs(rom: bytearray) -> int:
    """Rewrite absolute address operands in-place. Returns count.

    LD rr,nn only rewrites when nn looks like a pointer (>= $0800). Otherwise
    constants like ld bc,$0400 become $8400 and cold-start wipes the host.
    """
    n = 0
    pc = 0
    while pc < 0x4000:
        if 0x0800 <= pc < 0x0C00:
            pc = 0x0C00
            continue
        ln = insn_len(rom, pc)
        if pc + ln > 0x4000:
            break
        op = rom[pc]

        def patch_at(off: int, require_pointer=False):
            nonlocal n
            old = rom[pc + off] | (rom[pc + off + 1] << 8)
            if require_pointer and not is_pointer_imm(old):
                return
            new = map_addr(old)
            if new != old:
                rom[pc + off] = new & 0xFF
                rom[pc + off + 1] = (new >> 8) & 0xFF
                n += 1

        # JP nn / CALL nn / JP cc,nn / CALL cc,nn — always (code pointers)
        if op in (0xC3, 0xCD):
            if ln == 3:
                patch_at(1)
        elif op >= 0xC0 and (op & 0xC7) in (0xC2, 0xC4) and ln == 3:
            patch_at(1)
        # LD BC/DE/HL/SP,nn — only real pointers
        elif op in (0x01, 0x11, 0x21, 0x31):
            patch_at(1, require_pointer=True)
        # LD (nn),HL / LD HL,(nn) / LD (nn),A / LD A,(nn)
        elif op in (0x22, 0x2A, 0x32, 0x3A):
            patch_at(1)
        # ED: LD (nn),rr / LD rr,(nn)
        elif op == 0xED and ln == 4:
            patch_at(2)
        # DD/FD LD IX/IY,nn / LD (nn),IX / LD IX,(nn)
        elif op in (0xDD, 0xFD) and ln == 4 and rom[pc + 1] in (0x21, 0x22, 0x2A):
            # LD IX,nn needs pointer check; LD (nn),IX always
            if rom[pc + 1] == 0x21:
                patch_at(2, require_pointer=True)
            else:
                patch_at(2)

        pc += max(ln, 1)
    return n


def rewrite_imm_in_bytes(buf: bytearray, base_op_off: int = 0) -> None:
    """Rewrite absolute immediates inside a small instruction blob (stolen bytes)."""
    if not buf:
        return
    op = buf[0]
    def patch(off: int, require_pointer=False):
        if off + 1 >= len(buf):
            return
        old = buf[off] | (buf[off + 1] << 8)
        if require_pointer and not is_pointer_imm(old):
            return
        new = map_addr(old)
        buf[off] = new & 0xFF
        buf[off + 1] = (new >> 8) & 0xFF

    if op in (0xC3, 0xCD) or (op >= 0xC0 and (op & 0xC7) in (0xC2, 0xC4)):
        patch(1)
    elif op in (0x01, 0x11, 0x21, 0x31):
        patch(1, require_pointer=True)
    elif op in (0x22, 0x2A, 0x32, 0x3A):
        patch(1)
    elif op == 0xED and len(buf) >= 4:
        patch(2)
    elif op in (0xDD, 0xFD) and len(buf) >= 4 and buf[1] in (0x21, 0x22, 0x2A):
        if buf[1] == 0x21:
            patch(2, require_pointer=True)
        else:
            patch(2)


def plant_im2_vectors(rom: bytearray) -> None:
    """Point Berzerk's IM2 vector page at the relocated IRQ handler.

    Arcade sets I=$37; the board supplies vector $FC → word at $37FC = $26AB.
    On a Spectrum the ULA floats $FF, so the CPU reads the word at $37FF which
    was $0000 — reset the moment the PROM executes EI. Plant $A6AB for both the
    arcade vector ($FC) and the Spectrum default ($FF).
    """
    handler = ARCADE_BASE + 0x26AB  # $A6AB
    lo, hi = handler & 0xFF, (handler >> 8) & 0xFF
    # Aligned fill covers vector $FC ($37FC/$37FD) and friends.
    for i in range(0x3700, 0x3800, 2):
        rom[i] = lo
        rom[i + 1] = hi
    # Vector $FF reads odd address $37FF:$3800 — overwrite to match.
    rom[0x37FF] = lo
    if 0x3800 < len(rom):
        rom[0x3800] = hi


def plant_hooks(rom: bytearray) -> None:
    for src, dest in ENTRY_PATCHES:
        if src >= 0x4000:
            continue
        # JP dest
        rom[src] = 0xC3
        rom[src + 1] = dest & 0xFF
        rom[src + 2] = (dest >> 8) & 0xFF


def plant_io_islands(rom: bytearray) -> list:
    """Replace hooked IN A,(n) sites.

    Safe ports become `ld a,0` (exact 2-byte fit). Dynamic ports JP to an
    island that CALLs the hook, re-executes the full instruction that the
    3-byte JP stole into, then JP continues past that instruction.

    (A plain CALL/RET island is wrong: JP does not push a return address, and
    stealing only the first byte of a CB-prefixed insn leaves a broken stream.)
    """
    insns, _ = parse()
    sites = []
    for insn in insns:
        if not insn.is_code:
            continue
        t = insn.text.lower().strip()
        if not t.startswith("in "):
            continue
        m = re.search(r"\(\$([0-9a-f]{2})\)", t)
        if not m:
            continue
        port = int(m.group(1), 16)
        if port not in IN_PORT_HOOKS:
            continue
        sites.append((insn.addr, port))

    island = 0x0C00
    out = []
    for addr, port in sites:
        if addr >= 0x4000 or rom[addr] != 0xDB:
            continue
        hook = IN_PORT_HOOKS[port]

        # ld a,0 — no control-flow surgery
        if hook == HOOK_IN_SAFE:
            rom[addr] = 0x3E
            rom[addr + 1] = 0x00
            out.append((addr, port, None, b"\x3e\x00"))
            continue

        next_pc = addr + 2
        nlen = insn_len(rom, next_pc)
        if next_pc + nlen > 0x4000:
            continue
        stolen = bytes(rom[next_pc:next_pc + nlen])
        continue_pc = next_pc + nlen
        # Island: CALL hook / <stolen> / JP continue  (3+nlen+3)
        need = 3 + nlen + 3
        if island + need > 0x1000:
            break

        rom[addr] = 0xC3
        rom[addr + 1] = island & 0xFF
        rom[addr + 2] = (island >> 8) & 0xFF
        # Bytes of the stolen insn beyond the JP's third byte must not run.
        for i in range(1, nlen):
            rom[next_pc + i] = 0x00

        rom[island] = 0xCD
        rom[island + 1] = hook & 0xFF
        rom[island + 2] = (hook >> 8) & 0xFF
        rom[island + 3:island + 3 + nlen] = stolen
        j = island + 3 + nlen
        rom[j] = 0xC3
        rom[j + 1] = continue_pc & 0xFF
        rom[j + 2] = (continue_pc >> 8) & 0xFF

        out.append((addr, port, island, stolen))
        island += need
    return out


def emit_asm(rom: bytearray, path: Path, io_sites: list) -> None:
    lines = []
    a = lines.append
    a("; Generated by tools/reloc_rom.py — do not edit.")
    a(f"; Relocated Berzerk PROM. ORG ARCADE_BASE (see host_mem.inc).")
    a("")
    a("; IN-port patch sites (arcade addr → island or ld a,0).")
    for addr, port, island, stolen in io_sites:
        if island is None:
            a(f"; IN (${port:02X}) at ${addr:04X} -> ld a,0")
        else:
            hx = stolen.hex()
            a(f"; IN (${port:02X}) at ${addr:04X} -> island ${island:04X}, stolen {hx}")
    a("")
    a("    ORG ARCADE_BASE")
    a("arcade_prom:")
    for base in range(0, 0x4000, 16):
        row = ",".join(f"${rom[base + i]:02X}" for i in range(16))
        a(f"    db  {row}".ljust(76) + f"; ${ARCADE_BASE + base:04X} (arc ${base:04X})")
    a("arcade_prom_end:")
    a("    ASSERT arcade_prom_end - arcade_prom == $4000")
    path.write_text("\n".join(lines) + "\n")


def emit_mem_inc(path: Path) -> None:
    path.write_text(
        f"""; Shared memory map — host + relocator must agree.
ARCADE_BASE          EQU ${ARCADE_BASE:04X}
ARC_SCRATCH_4000     EQU ${SCRATCH_4000:04X}
ARC_SCRATCH_0800     EQU ${SCRATCH_0800:04X}
ARC_VIDEO            EQU ${VIDEO_BASE:04X}
ARC_MAGIC            EQU ${MAGIC_BASE:04X}
ARC_COLOR            EQU ${COLOR_BASE:04X}
HOST_HOOK_BASE       EQU $6000
HOST_STACK           EQU $5FFE
HOOK_DRAW_SPRITE     EQU ${HOOK_DRAW_SPRITE:04X}
HOOK_CLEAR_SCREEN    EQU ${HOOK_CLEAR_SCREEN:04X}
HOOK_RTOAX           EQU ${HOOK_RTOAX:04X}
HOOK_IN_P1           EQU ${HOOK_IN_P1:04X}
HOOK_IN_STATUS       EQU ${HOOK_IN_STATUS:04X}
HOOK_NMI             EQU ${HOOK_NMI:04X}
HOOK_PRINT_CHAR      EQU ${HOOK_PRINT_CHAR:04X}
HOOK_IN_SAFE         EQU ${HOOK_IN_SAFE:04X}
ARC_ATTRACT          EQU ARCADE_BASE + $164B
ARC_START_GAME       EQU ARCADE_BASE + $17B8
ARC_ROOM_START       EQU ARCADE_BASE + $209D
ARC_COLD             EQU ARCADE_BASE + $1602
"""
    )


def main():
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "src/arcade")
    out_dir.mkdir(parents=True, exist_ok=True)

    insns, _ = parse()
    img, clashes = image(insns)
    img.update(PATCHES)
    rom = bytearray(0x4000)
    for a, b in img.items():
        if a < 0x4000:
            rom[a] = b

    # I/O islands first (need original opcodes), then abs rewrite, then entry JP hooks.
    io_sites = plant_io_islands(rom)
    n = rewrite_abs(rom)
    plant_hooks(rom)

    # Re-fix dynamic I/O islands after rewrite_abs:
    # - site JP must target relocated island ($8Cxx)
    # - island CALL hook must stay at host $60xx (map_addr would send $6000→MAGIC)
    # - island continue JP must target relocated continue PC
    for addr, port, island, stolen in io_sites:
        hook = IN_PORT_HOOKS[port]
        if island is None:
            rom[addr] = 0x3E
            rom[addr + 1] = 0x00
            continue
        stolen_b = bytearray(stolen)
        rewrite_imm_in_bytes(stolen_b)
        nlen = len(stolen_b)
        continue_pc = addr + 2 + nlen
        rel_island = ARCADE_BASE + island
        rel_continue = ARCADE_BASE + continue_pc

        rom[addr] = 0xC3
        rom[addr + 1] = rel_island & 0xFF
        rom[addr + 2] = (rel_island >> 8) & 0xFF
        for i in range(1, nlen):
            rom[addr + 2 + i] = 0x00

        rom[island] = 0xCD
        rom[island + 1] = hook & 0xFF
        rom[island + 2] = (hook >> 8) & 0xFF
        rom[island + 3:island + 3 + nlen] = stolen_b
        j = island + 3 + nlen
        rom[j] = 0xC3
        rom[j + 1] = rel_continue & 0xFF
        rom[j + 2] = (rel_continue >> 8) & 0xFF

    # Re-plant entry hooks after rewrite (rewrite may have touched nothing there).
    plant_hooks(rom)
    # IM2 table last — must not be chewed by the code walker, and must use
    # relocated IRQ address for Spectrum's $FF bus vector.
    plant_im2_vectors(rom)

    emit_asm(rom, out_dir / "rom_reloc.asm", io_sites)
    emit_mem_inc(out_dir / "host_mem.inc")

    print(f"rewrote {n} absolute operands")
    print(f"I/O patches: {len(io_sites)}")
    print(f"clashes: {len(clashes)}")
    print(f"wrote {out_dir / 'rom_reloc.asm'}")
    print(f"wrote {out_dir / 'host_mem.inc'}")
    # sanity: attract entry
    off = 0x164B
    print(f"attract ${ARCADE_BASE+off:04X}: {rom[off:off+6].hex()}")
    print(f"DRAW_SPRITE patch: {rom[0x2817:0x281A].hex()} -> JP ${HOOK_DRAW_SPRITE:04X}")
    # Cold-start clear uses ld bc,$0400 — must NOT become $8400.
    cold = bytes(rom[0x1602:0x1620])
    print(f"cold ${ARCADE_BASE+0x1602:04X}: {cold.hex()}")
    if bytes([0x01, 0x00, 0x84]) in cold:
        print("ERROR: ld bc,$0400 was wrongly relocated to $8400", file=sys.stderr)
        sys.exit(1)
    irq = ARCADE_BASE + 0x26AB
    print(
        f"IM2 $37FC: {rom[0x37FC]:02X}{rom[0x37FD]:02X}  "
        f"$37FF: {rom[0x37FF]:02X}{(rom[0x3800] if 0x3800 < len(rom) else 0):02X}  "
        f"(want ${irq:04X})"
    )


if __name__ == "__main__":
    main()
