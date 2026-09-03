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
; Sprite blitting: HL -> (width, height, rows...), B=x, C=y
; Width must be 1 byte. Sprites are shifted to any pixel column, so each
; row can touch two screen bytes.
; -----------------------------------------------------------------------

sprite_setup:
    xor     a
    ld      (draw_collide),a
    inc     hl                              ; skip width
    ld      a,(hl)
    inc     hl
    ld      (spr_hleft),a
    ld      a,b
    and     7
    ld      (spr_shift),a
    ret

; HL -> row byte. Returns E = bits for first byte, D = bits spilling right.
sprite_row_bits:
    ld      a,(hl)
    ld      e,a
    ld      d,0
    ld      a,(spr_shift)
    or      a
    ret     z
    push    bc
    ld      b,a
.sh:
    srl     e
    rr      d
    djnz    .sh
    pop     bc
    ret

; OR E/D at spr_addr. Clobbers HL, A, B.
blit_row:
    ld      hl,(spr_addr)
    ld      a,(hl)
    or      e
    ld      (hl),a
    ld      a,d
    or      a
    ret     z
    inc     hl
    ld      a,(hl)
    or      d
    ld      (hl),a
    ret

; screen = (screen & ~sprite) | (mask & sprite)
restore_row:
    ld      hl,(spr_addr)
    ld      a,e
    cpl
    and     (hl)
    ld      b,a
    push    hl
    ld      hl,(spr_mask)
    ld      a,(hl)
    and     e
    or      b
    pop     hl
    ld      (hl),a
    ld      a,d
    or      a
    ret     z
    inc     hl
    ld      a,d
    cpl
    and     (hl)
    ld      b,a
    push    hl
    ld      hl,(spr_mask)
    inc     hl
    ld      a,(hl)
    and     d
    or      b
    pop     hl
    ld      (hl),a
    ret

; Test E/D against the mask at spr_addr.
test_row:
    ld      hl,(spr_addr)
    ld      a,(hl)
    and     e
    call    nz,.hit
    ld      a,d
    or      a
    ret     z
    inc     hl
    ld      a,(hl)
    and     d
    call    nz,.hit
    ret
.hit:
    ld      a,1
    ld      (draw_collide),a
    ret

; Draw sprite (no collision test)
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
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

; Erase sprite footprint, restoring walls
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
    call    screen_to_mask
    ld      (spr_mask),hl
    pop     hl
    call    sprite_row_bits
    push    hl
    call    restore_row
    pop     hl
    pop     bc
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

; Test sprite against walls; sets (draw_collide). Draws nothing.
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
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row
