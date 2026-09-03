; Berzerk arcade host — relocated PROM + Spectrum I/O hooks.
; docs/PORT.md Phase 3.

    INCLUDE "tools/sjasm/BasicLib.asm"
    INCLUDE "src/arcade/host_mem.inc"

    DEVICE ZXSPECTRUM48

    ORG 23755
basic:
    LINE : db clear,val,'"24575"'           : LEND
    LINE : db load,'"arcade"',code          : LEND
    LINE : db rand,usr : NUM host_start     : LEND
basend:

; --------------------------------------------------------------------
    ORG HOST_HOOK_BASE
; Veneers — addresses fixed for reloc_rom.py ($6000–$6017)
    jp      hook_draw_sprite          ; $6000
    jp      hook_clear_screen         ; $6003
    jp      hook_rtoax                ; $6006
    jp      hook_in_p1                ; $6009
    jp      hook_in_status            ; $600C
    jp      hook_nmi                  ; $600F
    jp      hook_print_char           ; $6012
    jp      hook_in_safe              ; $6015

host_start:
    di
    ld      sp,HOST_STACK
    ld      hl,ARC_SCRATCH_4000
    ld      de,ARC_SCRATCH_4000+1
    ld      bc,$4000-1
    ld      (hl),0
    ldir
    call    zx_cls
    ld      hl,$5800
    ld      de,$5801
    ld      bc,767
    ld      (hl),%00000100
    ldir
    ; Berzerk uses IM2 with I=$37; Spectrum bus vector is $FF.
    ; reloc_rom plants $A6AB at $37FF/$3800 so EI does not reset.
    ld      a,$37
    ld      i,a
    im      2
    ; EI is left to the arcade PROM once its vector page is ready.
    jp      ARC_COLD

    INCLUDE "src/zx/screen.asm"
    INCLUDE "src/zx/input.asm"

; draw/hook working vars (must be before blit/hooks use them)
magic_collide:  db 0
rtoax_x:        db 0
rtoax_y:        db 0
draw_x:         db 0
draw_y:         db 0
draw_collide:   db 0
spr_shift:      db 0
spr_hleft:      db 0
spr_w:          db 0
spr_addr:       dw 0
spr_mask:       dw 0
spr_row:        db 0,0,0

    INCLUDE "src/arcade/blit.asm"
    INCLUDE "src/arcade/hooks.asm"

host_end:
    ASSERT host_end <= ARCADE_BASE

; --------------------------------------------------------------------
    INCLUDE "src/arcade/rom_reloc.asm"

code_end:

    EMPTYTAP "build/arcade.tap"
    SAVETAP  "build/arcade.tap", BASIC, "arcade", basic, basend - basic, 10
    SAVETAP  "build/arcade.tap", CODE,  "arcade", HOST_HOOK_BASE, code_end - HOST_HOOK_BASE
    SAVESNA  "build/arcade.sna", host_start
