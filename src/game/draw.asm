; Wall-mask rendering
; Maze lives in WALL_MASK ($C000) and mirrors the screen bitmap.
; Sprites OR onto the screen; erase restores their footprint from the mask.
; Collision tests the mask only, never other sprites.

WALL_MASK       EQU $C000                   ; 6144 bytes

mask_capture:
    ld      hl,$4000
    ld      de,WALL_MASK
    ld      bc,6144
    ldir
    ret

; HL screen ($4000-$57FF) -> HL mask ($C000-$D7FF)
screen_to_mask:
    ld      a,h
    add     a,$80
    ld      h,a
    ret

; -----------------------------------------------------------------------
; Single pixel ops (bolts)
; -----------------------------------------------------------------------

; B=x, C=y. Carry set if the wall mask has ink here.
pixel_hits_wall:
    push    bc
    push    hl
    ld      a,c
    cp      192
    jr      nc,.no
    call    zx_pixel_addr
    call    pixel_bitmask
    call    screen_to_mask
    and     (hl)
    pop     hl
    pop     bc
    ret     z
    scf
    ret
.no:
    pop     hl
    pop     bc
    xor     a
    ret

; B=x, C=y. OR one pixel onto the screen.
plot_pixel:
    push    bc
    push    de
    push    hl
    ld      a,c
    cp      192
    jr      nc,.out
    call    zx_pixel_addr
    call    pixel_bitmask
    or      (hl)
    ld      (hl),a
.out:
    pop     hl
    pop     de
    pop     bc
    ret

; B=x, C=y. Clear the pixel, putting back any wall underneath.
restore_pixel:
    push    bc
    push    de
    push    hl
    ld      a,c
    cp      192
    jr      nc,.out
    call    zx_pixel_addr
    call    pixel_bitmask
    ld      d,a
    push    hl
    call    screen_to_mask
    ld      a,(hl)
    and     d
    ld      c,a                             ; wall bit under the pixel
    pop     hl
    ld      a,d
    cpl
    and     (hl)
    or      c
    ld      (hl),a
.out:
    pop     hl
    pop     de
    pop     bc
    ret

; HL = screen address for (B,C). Returns A = bit mask. Clobbers B.
pixel_bitmask:
    ld      a,b
    and     7
    ld      b,a
    ld      a,%10000000
    inc     b
.rot:
    dec     b
    ret     z
    rrca
    jr      .rot

; -----------------------------------------------------------------------
; Sprite blitting. HL -> (width_bytes, height, row data...)
; Width is 1 or 2 bytes. The sprite is shifted into spr_row[3] so a 16-pixel
; sprite can touch three screen bytes when it is not byte-aligned.
; -----------------------------------------------------------------------

sprite_setup:
    xor     a
    ld      (draw_collide),a
    ld      a,(hl)                          ; width in bytes
    inc     hl
    or      a
    jr      nz,.w
    inc     a                               ; listing hole: treat 0 as 1
.w:
    ld      (spr_w),a
    ld      a,(hl)
    inc     hl
    ld      (spr_hleft),a
    ld      a,b
    and     7
    ld      (spr_shift),a
    ret

; HL -> row pixels. Fills spr_row[0..2] shifted right by spr_shift. Advances HL.
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
    push    hl                              ; sprite data pointer — must survive the shift
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

; OR spr_row onto the screen at spr_addr.
blit_row:
    ld      hl,(spr_addr)
    ld      a,(spr_row)
    or      (hl)
    ld      (hl),a
    ld      a,(spr_row+1)
    or      a
    jr      z,.b2
    inc     hl
    or      (hl)
    ld      (hl),a
    dec     hl
.b2:
    ld      a,(spr_row+2)
    or      a
    ret     z
    inc     hl
    inc     hl
    or      (hl)
    ld      (hl),a
    ret

; screen = (screen & ~sprite) | (mask & sprite) for each occupied byte
restore_row:
    ld      b,3
    ld      de,spr_row
    ld      hl,(spr_addr)
.one:
    ld      a,(de)
    or      a
    jr      z,.next
    push    bc
    push    hl
    ld      c,a                             ; sprite bits
    cpl
    and     (hl)
    ld      b,a                             ; screen with sprite cleared
    push    hl
    call    screen_to_mask
    ld      a,(hl)
    and     c                               ; wall bits under the sprite
    or      b
    pop     hl
    ld      (hl),a
    pop     hl
    pop     bc
.next:
    inc     de
    inc     hl
    djnz    .one
    ret

test_row:
    ld      b,3
    ld      de,spr_row
    ld      hl,(spr_addr)
.one:
    ld      a,(de)
    or      a
    jr      z,.next
    and     (hl)
    jr      z,.next
    ld      a,1
    ld      (draw_collide),a
.next:
    inc     de
    inc     hl
    djnz    .one
    ret

or_sprite:
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
    call    blit_row
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

restore_sprite:
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
    call    restore_row
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

collide_sprite:
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
    call    screen_to_mask
    ld      (spr_addr),hl
    pop     hl
    call    sprite_row_bits
    push    hl
    call    test_row
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
