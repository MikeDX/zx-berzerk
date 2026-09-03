; XOR blit for arcade Magic-RAM semantics (draw == erase == XOR).

; Composite ZX_VIDEO XOR ZX_MAGIC → Spectrum bitmap ($4000), 256×192.
; Arcade display = video plane + magic XOR plane; we approximate that here.
frame_blit:
    di
    push    af
    push    bc
    push    de
    push    hl
    push    ix
    ld      de,ZX_VIDEO
    ld      ix,ZX_MAGIC
    ld      c,0                     ; y
.y:
    ld      b,0
    push    de
    push    bc
    call    zx_pixel_addr
    pop     bc
    pop     de
    push    bc
    ld      b,32
.x:
    ld      a,(de)
    xor     (ix+0)
    ld      (hl),a
    inc     de
    inc     ix
    inc     hl
    djnz    .x
    pop     bc
    inc     c
    ld      a,c
    cp      192
    jr      c,.y
    pop     ix
    pop     hl
    pop     de
    pop     bc
    pop     af
    ; leave IFFs as DI — callers re-enable; avoids IM1/$0038 if entered badly
    ret

sprite_setup:
    xor     a
    ld      (draw_collide),a
    ld      a,(hl)
    inc     hl
    or      a
    jr      nz,.w
    inc     a
.w:
    ld      (spr_w),a
    ld      a,(hl)
    inc     hl
    ld      (spr_hleft),a
    ld      a,b
    and     7
    ld      (spr_shift),a
    ret

sprite_row_bits:
    xor     a
    ld      (spr_row+1),a
    ld      (spr_row+2),a
    ld      a,(hl)
    inc     hl
    ld      (spr_row),a
    ld      a,(spr_w)
    dec     a
    jr      z,.shift
    ld      a,(hl)
    inc     hl
    ld      (spr_row+1),a
.shift:
    ld      a,(spr_shift)
    or      a
    ret     z
    push    bc
    push    hl
    ld      b,a
    ld      hl,spr_row
    ld      a,(hl)
    inc     hl
    ld      e,(hl)
    inc     hl
    ld      d,(hl)
.sh:
    srl     a
    rr      e
    rr      d
    djnz    .sh
    ld      (hl),d
    dec     hl
    ld      (hl),e
    dec     hl
    ld      (hl),a
    pop     hl
    pop     bc
    ret

; HL -> (width, height, rows...), B=x, C=y — XOR onto Spectrum screen.
xor_sprite:
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    push    bc
    push    hl
    call    zx_pixel_addr
    ld      (spr_addr),hl
    pop     hl
    call    sprite_row_bits
    push    hl
    call    xor_row
    pop     hl
    pop     bc
    jr      .next
.adv:
    ld      a,(spr_w)
    ld      e,a
    ld      d,0
    add     hl,de
.next:
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

xor_row:
    ld      hl,(spr_addr)
    ld      a,(spr_row)
    or      a
    call    nz,.one
    ld      a,(spr_row+1)
    or      a
    jr      z,.r2
    inc     hl
    call    .one
    dec     hl
.r2:
    ld      a,(spr_row+2)
    or      a
    ret     z
    inc     hl
    inc     hl
.one:
    ld      b,a
    and     (hl)
    jr      z,.w
    ld      a,1
    ld      (magic_collide),a
.w:
    ld      a,b
    xor     (hl)
    ld      (hl),a
    ret

; XOR into fake Magic RAM. B=x C=y HL=pattern.
magic_xor_sprite:
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    push    bc
    push    hl
    ld      l,c
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,b
    rrca
    rrca
    rrca
    and     31
    ld      e,a
    ld      d,0
    add     hl,de
    ld      de,ZX_MAGIC
    add     hl,de
    ld      (spr_addr),hl
    pop     hl
    call    sprite_row_bits
    push    hl
    ld      hl,(spr_addr)
    ld      a,(spr_row)
    xor     (hl)
    ld      (hl),a
    ld      a,(spr_row+1)
    or      a
    jr      z,.m2
    inc     hl
    xor     (hl)
    ld      (hl),a
.m2:
    pop     hl
    pop     bc
    jr      .next
.adv:
    ld      a,(spr_w)
    ld      e,a
    ld      d,0
    add     hl,de
.next:
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row
