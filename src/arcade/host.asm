; Berzerk Spectrum host — remapped game + HAL veneers.
; docs/PORT.md. Built by `make` → build/berzerk.sna / .tap

    INCLUDE "tools/sjasm/BasicLib.asm"
    INCLUDE "src/arcade/mem_map.inc"

    DEVICE ZXSPECTRUM48

    ORG 23755
basic:
    LINE : db clear,val,'"24575"'            : LEND
    LINE : db load,'"bzprom"',code           : LEND
    LINE : db load,'"bzhal"',code            : LEND
    LINE : db rand,usr : NUM host_start      : LEND
basend:

; --------------------------------------------------------------------
; HAL veneers — addresses fixed by mem_map.inc / emit_spectrum_asm.py
    ORG ZX_HAL
    ASSERT $ == HOOK_DRAW_SPRITE
    jp      hook_draw_sprite          ; $DC00
    ASSERT $ == HOOK_CLEAR_SCREEN
    jp      hook_clear_screen         ; $DC03
    ASSERT $ == HOOK_RTOAX
    jp      hook_rtoax                ; $DC06
    ASSERT $ == HOOK_IN_P1
    jp      hook_in_p1                ; $DC09
    ASSERT $ == HOOK_IN_STATUS
    jp      hook_in_status            ; $DC0C
    ASSERT $ == HOOK_NMI
    jp      hook_nmi                  ; $DC0F
    ASSERT $ == HOOK_PRINT_CHAR
    jp      hook_print_char           ; $DC12
    ASSERT $ == HOOK_IN_SYSTEM
    jp      hook_in_system
    ASSERT $ == HOOK_GAME_LOOP
    jp      hook_game_loop
    ASSERT $ == HOOK_OUT_MAGIC
    jp      hook_out_magic
    ASSERT $ == HOOK_BOLT_PIXEL
    jp      hook_bolt_pixel
    ASSERT $ == HOOK_COLOUR_FILL
    jp      hook_colour_fill
    ASSERT $ == HOOK_MAZE
    jp      hook_maze

host_start:
    di
    ld      sp,ZX_STACK

    ; Clear guest RAM (scratch / video / magic / colour)
    ld      hl,ZX_SCRATCH_CMOS
    ld      de,ZX_SCRATCH_CMOS+1
    ld      bc,ZX_HAL - ZX_SCRATCH_CMOS - 1
    ld      (hl),0
    ldir

    call    zx_cls
    ld      hl,$5800
    ld      de,$5801
    ld      bc,767
    ld      (hl),%00000100              ; green ink on black
    ldir

    ; IM2: full 257-byte table at $EE00 (see im2_table). Not PROM $97xx —
    ; that page is game code and only two bytes were patched.
    ld      a,ZX_IM2_PAGE
    ld      i,a
    im      2

    jp      ARC_COLD

    INCLUDE "src/zx/screen.asm"
    INCLUDE "src/zx/input.asm"
    INCLUDE "src/arcade/blit.asm"
    INCLUDE "src/arcade/hooks.asm"

; BSS after all HAL code — never place data between routines (NOP fall-through).
magic_collide:  db 0
vblank_div:     db 0
blit_div:       db 0
rtoax_x:        db 0
rtoax_y:        db 0
magic_shift:    db 0
draw_x:         db 0
draw_y:         db 0
draw_collide:   db 0
spr_shift:      db 0
spr_hleft:      db 0
spr_w:          db 0
spr_addr:       dw 0
spr_mask:       dw 0
spr_row:        db 0,0,0
blit_save_sp:   dw 0
                ds 128
blit_stack:

host_end:
    ASSERT host_end <= $EE00

    ; 257-byte IM2 table: every word is $EEEE. ISR at $EEEE jumps to arcade IRQ.
    ORG $EE00
im2_table:
    ds      $EEEE - $, $EE
im2_isr:
    jp      ARC_IRQ
    ds      $EF01 - $, $EE
im2_end:
    ASSERT im2_end <= ZX_COLOR

; --------------------------------------------------------------------
; Remapped Berzerk (ORG'd into $6000–$9FFF by the emitter)
    DEFINE _BERZERK_MEM_MAP_INC
    INCLUDE "src/arcade/berzerk.asm"

    EMPTYTAP "build/berzerk.tap"
    SAVETAP  "build/berzerk.tap", BASIC, "berzerk", basic, basend - basic, 10
    SAVETAP  "build/berzerk.tap", CODE,  "bzprom", ZX_PROM, $4000
    SAVETAP  "build/berzerk.tap", CODE,  "bzhal",  ZX_HAL, im2_end - ZX_HAL
    SAVESNA  "build/berzerk.sna", host_start
