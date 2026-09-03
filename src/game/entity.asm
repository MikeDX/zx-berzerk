; Shared entity move / draw / erase

entity_move:
    ld      a,(ix+V_TIME)
    dec     a
    ld      (ix+V_TIME),a
    ret     nz
    ld      a,(ix+V_TPRIME)
    ld      (ix+V_TIME),a
    ld      a,(ix+V_PX)
    add     a,(ix+V_VX)
    ld      (ix+V_PX),a
    ld      a,(ix+V_PY)
    add     a,(ix+V_VY)
    ld      (ix+V_PY),a
    ret

; Restore old sprite footprint from wall mask
entity_erase:
    ld      a,(ix+V_STATUS)
    bit     0,a
    ret     z
    ld      b,(ix+V_OLDX)
    ld      c,(ix+V_OLDY)
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    jp      restore_sprite

; Collide against wall mask; OR onto screen only if clear.
entity_draw:
    ld      b,(ix+V_PX)
    ld      c,(ix+V_PY)
    ld      (ix+V_OLDX),b
    ld      (ix+V_OLDY),c
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    push    hl
    push    bc
    call    collide_sprite
    pop     bc
    pop     hl
    ld      a,(draw_collide)
    or      a
    ret     nz                              ; leave undrawn; caller sets HIT
    jp      or_sprite

; True if sprite at IX overlaps wall (no draw)
entity_hits_wall:
    ld      b,(ix+V_PX)
    ld      c,(ix+V_PY)
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    call    collide_sprite
    ld      a,(draw_collide)
    or      a
    ret
