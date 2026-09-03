; Pixel / sprite XOR draw with soft collision

; XOR pixel B=x, C=y. Carry set on collision with existing ink.
xor_pixel:
    push    bc
    push    de
    push    hl
    ld      a,c
    cp      192
    jr      nc,.off
    call    zx_pixel_addr
    ld      a,b
    and     7
    ld      b,a
    ld      a,%10000000
    inc     b
.rot:
    dec     b
    jr      z,.mask
    rrca
    jr      .rot
.mask:
    ld      b,a
    ld      a,(hl)
    ld      c,a
    and     b
    ld      d,a
    ld      a,c
    xor     b
    ld      (hl),a
    ld      a,d
    pop     hl
    pop     de
    pop     bc
    or      a
    ret     z
    scf
    ret
.off:
    pop     hl
    pop     de
    pop     bc
    xor     a
    ret

; HL→sprite (w,h,data), B=x, C=y — width must be 1
xor_sprite:
    xor     a
    ld      (draw_collide),a
    inc     hl
    ld      a,(hl)
    inc     hl
    ld      (spr_hleft),a
    ld      a,b
    and     7
    ld      (spr_shift),a
    ld      a,b
    and     %11111000
    ld      (spr_xbyte),a

.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv

    push    bc
    push    hl
    ld      a,(spr_xbyte)
    ld      b,a
    call    zx_pixel_addr                   ; HL = screen
    ld      (.scr),hl
    pop     hl                              ; sprite ptr
    ld      a,(hl)
    ld      e,a                             ; bits
    ld      d,0                             ; overflow
    ld      a,(spr_shift)
    or      a
    jr      z,.put
    ld      b,a
.shl:
    srl     e
    rr      d
    djnz    .shl
.put:
    push    hl
    ld      hl,0
.scr:   equ $-2
    ld      a,(hl)
    and     e
    call    nz,.hit
    ld      a,(hl)
    xor     e
    ld      (hl),a
    ld      a,d
    or      a
    jr      z,.done
    inc     hl
    ld      a,(hl)
    and     d
    call    nz,.hit
    ld      a,(hl)
    xor     d
    ld      (hl),a
.done:
    pop     hl
    pop     bc

.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

.hit:
    push    af
    ld      a,1
    ld      (draw_collide),a
    pop     af
    ret
