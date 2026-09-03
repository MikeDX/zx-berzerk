; Arcade ↔ Spectrum I/O hook implementations.
; Veneer JP table lives in host.asm at ZX_HAL.

hook_clear_screen:
    push    af
    push    bc
    push    de
    push    hl
    call    zx_cls
    ld      hl,ZX_VIDEO
    ld      de,ZX_VIDEO+1
    ld      bc,$1800-1
    ld      (hl),0
    ldir
    ld      hl,ZX_MAGIC
    ld      de,ZX_MAGIC+1
    ld      bc,$1800-1
    ld      (hl),0
    ldir
    xor     a
    ld      (magic_collide),a
    pop     hl
    pop     de
    pop     bc
    pop     af
    ret

hook_rtoax:
    push    bc
    ld      a,l
    ld      (rtoax_x),a
    ld      a,h
    cp      192
    jr      c,.yok
    ld      a,191
.yok:
    ld      (rtoax_y),a
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(rtoax_x)
    rrca
    rrca
    rrca
    and     31
    ld      c,a
    ld      b,0
    add     hl,bc
    ld      bc,ZX_MAGIC
    add     hl,bc
    pop     bc
    ld      a,$90
    ret

hook_draw_sprite:
    push    af
    push    bc
    push    de
    push    hl
    push    ix
    push    hl
    pop     ix
    call    magic_dest_xy
    ld      a,b
    ld      (draw_x),a
    ld      a,c
    ld      (draw_y),a
    push    ix
    pop     hl
    ld      a,(draw_x)
    ld      b,a
    ld      a,(draw_y)
    ld      c,a
    call    xor_sprite
    push    ix
    pop     hl
    ld      a,(draw_x)
    ld      b,a
    ld      a,(draw_y)
    ld      c,a
    call    magic_xor_sprite
    pop     ix
    pop     hl
    pop     de
    pop     bc
    pop     af
    ret

magic_dest_xy:
    push    de
    pop     hl
    ld      a,h
    cp      ZX_MAGIC >> 8
    jr      nc,.magic
    cp      ZX_MAGIC_SCRATCH >> 8
    jr      c,.video
    ld      bc,ZX_MAGIC_SCRATCH
    jr      .sub
.magic:
    ld      bc,ZX_MAGIC
    jr      .sub
.video:
    ld      bc,ZX_VIDEO
.sub:
    or      a
    sbc     hl,bc
    ld      a,l
    and     31
    add     a,a
    add     a,a
    add     a,a
    ld      b,a
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    ld      c,l
    ret

hook_in_p1:
    push    bc
    push    de
    push    hl
    call    input_poll
    xor     $1F
    pop     hl
    pop     de
    pop     bc
    ret

hook_in_status:
    ; Bottom-of-screen (bit0) only when MAN_PTR looks like a guest RAM pointer.
    ; Junk values (e.g. $1100) must not enable ERASE_PATTERN or we reset.
    ; Must preserve HL — IRQ samples this port before pushing HL.
    push    hl
    ld      hl,ZX_SCRATCH_CMOS + ($0876 - $0800)  ; MAN_PTR @ arcade $0876
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a
    ld      a,h
    cp      ZX_SCRATCH_CMOS >> 8
    jr      c,.idle
    ld      a,h
    cp      ZX_HAL >> 8
    jr      nc,.idle
    ld      a,(magic_collide)
    or      a
    jr      z,.vblank
    xor     a
    ld      (magic_collide),a
    ld      a,%10000001
    pop     hl
    ret
.vblank:
    ld      a,(vblank_div)
    inc     a
    ld      (vblank_div),a
    and     7
    ld      a,%00000001
    jr      z,.vblank_out
    xor     a
.vblank_out:
    pop     hl
    ret
.idle:
    ld      a,(magic_collide)
    or      a
    jr      z,.zero
    xor     a
    ld      (magic_collide),a
    ld      a,%10000000
    pop     hl
    ret
.zero:
    xor     a
    pop     hl
    ret

; Cold start CALLs NMI as a subroutine; use RET not RETN.
hook_nmi:
    ret

hook_in_safe:
    xor     a
    ret

hook_print_char:
    push    af
    push    bc
    push    de
    push    hl
    ld      a,c
    and     $7F
    cp      32
    jr      c,.out
    push    af
    call    magic_dest_xy
    ld      a,b
    rrca
    rrca
    rrca
    and     31
    ld      b,a
    ld      a,c
    rrca
    rrca
    rrca
    and     31
    ld      c,a
    pop     af
    call    zx_print_char
.out:
    pop     hl
    pop     de
    pop     bc
    pop     af
    xor     a
    ret
