; Shared entity move / draw / erase

; IX = vector. Apply velocity when TIME hits 0.
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

entity_erase:
    ld      a,(ix+V_STATUS)
    bit     0,a
    ret     z
    ld      b,(ix+V_OLDX)
    ld      c,(ix+V_OLDY)
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    ld      a,(draw_collide)
    push    af
    call    xor_sprite
    pop     af
    ld      (draw_collide),a
    ret

entity_draw:
    ld      b,(ix+V_PX)
    ld      c,(ix+V_PY)
    ld      (ix+V_OLDX),b
    ld      (ix+V_OLDY),c
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    jp      xor_sprite
