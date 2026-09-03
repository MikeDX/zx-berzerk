; Wall-mask rendering
; Maze lives in WALL_MASK ($C000) and on screen.
; Sprites OR onto screen; erase restores sprite bits from the mask.
; Collision tests against the mask only (never against other sprites).

WALL_MASK       EQU $C000                   ; 6144 bytes — mirror of bitmap

mask_capture:
    ld      hl,$4000
    ld      de,WALL_MASK
    ld      bc,6144
    ldir
    ret

screen_to_mask:
    ld      a,h
    add     a,$80
    ld      h,a
    ret

; -----------------------------------------------------------------------
; Pixel ops (bolts)
; -----------------------------------------------------------------------

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

restore_pixel:
    push    bc
    push    de
    push    hl
    ld      a,c
    cp      192
    jr      nc,.out2
    call    zx_pixel_addr
    call    pixel_bitmask
    ld      d,a
    push    hl
    call    screen_to_mask
    ld      a,(hl)
    and     d
    ld      c,a
    pop     hl
    ld      a,d
    cpl
    and     (hl)
    or      c
    ld      (hl),a
.out2:
    pop     hl
    pop     de
    pop     bc
    ret

; HL=screen addr for (B,C). Returns A=bit mask. Clobbers B.
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
; Sprite helpers
; HL→sprite (w,h,data), B=x, C=y — width must be 1 byte
; -----------------------------------------------------------------------

sprite_setup:
    xor     a
    ld      (draw_collide),a
    inc     hl
    ld      a,(hl)
    inc     hl
    ld      (spr_hleft),a
    ret

; Read row byte; E=primary screen byte, D=overflow into next byte
; Shift=0: entity sprites (data already positioned within the byte)
sprite_row_raw:
    ld      e,(hl)
    ld      d,0
    ret

; Shift= spr_shift: left-aligned tiles (wall bricks at $F0…)
sprite_row_shift:
    ld      a,(hl)
    ld      e,a
    ld      d,0
    ld      a,(spr_shift)
    or      a
    ret     z
    ld      b,a
.sh:
    srl     e
    rr      d
    djnz    .sh
    ret

; OR two bytes onto screen at spr_addr
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

; Restore two bytes from mask at spr_addr using sprite bits E/D
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

; Test E/D against mask at spr_addr
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

; Shared row loop body: HL=row ptr, B=x, C=y
; Caller sets spr_shift before call for shifted blits (walls)
draw_row:
    push    bc
    push    hl
    call    zx_pixel_addr
    ld      (spr_addr),hl
    pop     hl
    ld      a,(spr_shift)
    or      a
    jr      nz,.sh
    call    sprite_row_raw
    jr      .blit
.sh:
    call    sprite_row_shift
.blit:
    call    blit_row
    pop     bc
    ret

restore_row_setup:
    push    bc
    push    hl
    call    zx_pixel_addr
    ld      (spr_addr),hl
    call    screen_to_mask
    ld      (spr_mask),hl
    pop     hl
    ld      a,(spr_shift)
    or      a
    jr      nz,.sh
    call    sprite_row_raw
    jr      .rest
.sh:
    call    sprite_row_shift
.rest:
    call    restore_row
    pop     bc
    ret

test_row_setup:
    push    bc
    push    hl
    call    zx_pixel_addr
    call    screen_to_mask
    ld      (spr_addr),hl
    pop     hl
    ld      a,(spr_shift)
    or      a
    jr      nz,.sh
    call    sprite_row_raw
    jr      .test
.sh:
    call    sprite_row_shift
.test:
    call    test_row
    pop     bc
    ret

; Entity sprites — data already aligned to (x,y) pixel within the byte
or_sprite:
    xor     a
    ld      (spr_shift),a
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    call    draw_row
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

; Wall bricks — left-aligned $F0 nibble, shift by x mod 8
or_sprite_shifted:
    ld      a,b
    and     7
    ld      (spr_shift),a
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    call    draw_row
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

restore_sprite:
    xor     a
    ld      (spr_shift),a
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    call    restore_row_setup
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row

collide_sprite:
    xor     a
    ld      (spr_shift),a
    call    sprite_setup
.row:
    ld      a,(spr_hleft)
    or      a
    ret     z
    ld      a,c
    cp      192
    jr      nc,.adv
    call    test_row_setup
.adv:
    inc     hl
    inc     c
    ld      a,(spr_hleft)
    dec     a
    ld      (spr_hleft),a
    jr      .row
