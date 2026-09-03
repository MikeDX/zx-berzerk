; Arcade ↔ Spectrum I/O hook implementations.
; Veneer JP table lives in host.asm at HOST_HOOK_BASE.

hook_clear_screen:
    push    af
    push    bc
    push    de
    push    hl
    call    zx_cls
    ld      hl,ARC_VIDEO
    ld      de,ARC_VIDEO+1
    ld      bc,$1800-1
    ld      (hl),0
    ldir
    ld      hl,ARC_MAGIC
    ld      de,ARC_MAGIC+1
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
    ld      bc,ARC_MAGIC
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
    cp      ARC_MAGIC >> 8
    ld      bc,ARC_MAGIC
    jr      nc,.sub
    ld      bc,ARC_VIDEO
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
    ld      a,(magic_collide)
    or      a
    jr      z,.nc
    xor     a
    ld      (magic_collide),a
    ld      a,%10000001
    ret
.nc:
    ld      a,%00000001
    ret

; Cold start CALLs $1721 as a subroutine; RETN would corrupt IFF.
hook_nmi:
    ret

; Safe stub for arcade ports that must not float into test/DIP modes.
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
