; Shared entity move / draw / erase
; MOVE_ANIMATE_VECTOR ($27A9) + WRITE_PATTERN ($274D), minus Magic RAM.

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
    jp      vec_next_frame

; Restore the sprite that was actually drawn last frame.
entity_erase:
    bit     0,(ix+V_STATUS)
    ret     z
    ld      a,(ix+V_OSPR_H)
    or      (ix+V_OSPR_L)
    ret     z
    ld      a,(ix+V_OLDX)
    add     a,(ix+V_ODX)
    ld      b,a
    ld      a,(ix+V_OLDY)
    add     a,(ix+V_ODY)
    ld      c,a
    ld      l,(ix+V_OSPR_L)
    ld      h,(ix+V_OSPR_H)
    jp      restore_sprite

; B,C = draw position of the current sprite (PX+DX, PY+DY)
entity_draw_pos:
    ld      a,(ix+V_PX)
    add     a,(ix+V_DX)
    ld      b,a
    ld      a,(ix+V_PY)
    add     a,(ix+V_DY)
    ld      c,a
    ret

entity_stash_old:
    ld      a,(ix+V_PX)
    ld      (ix+V_OLDX),a
    ld      a,(ix+V_PY)
    ld      (ix+V_OLDY),a
    ld      a,(ix+V_DX)
    ld      (ix+V_ODX),a
    ld      a,(ix+V_DY)
    ld      (ix+V_ODY),a
    ld      a,(ix+V_SPR_L)
    ld      (ix+V_OSPR_L),a
    ld      a,(ix+V_SPR_H)
    ld      (ix+V_OSPR_H),a
    ret

; Collide against the wall mask; OR onto the screen only if clear.
entity_draw:
    call    vec_resolve_sprite
    call    entity_draw_pos
    call    entity_stash_old
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    push    hl
    push    bc
    call    collide_sprite
    pop     bc
    pop     hl
    ld      a,(draw_collide)
    or      a
    ret     nz
    jp      or_sprite

; Draw with no wall test (Otto, explosions).
entity_draw_noclip:
    call    vec_resolve_sprite
    call    entity_draw_pos
    call    entity_stash_old
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    jp      or_sprite
