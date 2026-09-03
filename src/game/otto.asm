; Evil Otto

otto_clear:
    ld      ix,otto_vec
    jp      vec_clear

otto_update:
    ld      a,(otto_active)
    or      a
    jr      nz,.chase
    ; countdown
    ld      a,(otto_timer)
    or      a
    ret     z
    dec     a
    ld      (otto_timer),a
    ret     nz
    ; appear opposite player
    ld      ix,otto_vec
    call    vec_clear
    ld      a,KIND_OTTO
    ld      (ix+V_KIND),a
    ld      a,ST_MOVE|ST_WRITE|ST_ERASE
    ld      (ix+V_STATUS),a
    ld      a,(player_vec+V_PX)
    cp      128
    ld      b,16
    jr      nc,.ox
    ld      b,232
.ox:
    ld      (ix+V_PX),b
    ld      a,(player_vec+V_PY)
    cp      96
    ld      c,16
    jr      nc,.oy
    ld      c,160
.oy:
    ld      (ix+V_PY),c
    ld      a,3
    ld      (ix+V_TPRIME),a
    ld      (ix+V_TIME),a
    ld      hl,spr_otto
    ld      (ix+V_SPR_L),l
    ld      (ix+V_SPR_H),h
    ld      a,1
    ld      (otto_active),a
    ret

.chase:
    ld      ix,otto_vec
    call    entity_erase
    ; seek player (ignores walls — no collision kill)
    ld      a,(player_vec+V_PX)
    sub     (ix+V_PX)
    ld      d,0
    jr      z,.v
    ld      d,LEFT
    jr      c,.v
    ld      d,RIGHT
.v:
    ld      a,(player_vec+V_PY)
    sub     (ix+V_PY)
    ld      e,0
    jr      z,.d
    ld      e,UP
    jr      c,.d
    ld      e,DOWN
.d:
    ld      a,d
    or      e
    call    set_velocity
    call    entity_move
    set     0,(ix+V_STATUS)
    set     1,(ix+V_STATUS)

    ; touch player?
    ld      a,(ix+V_PX)
    ld      b,a
    ld      a,(player_vec+V_PX)
    sub     b
    jr      nc,.dxp
    neg
.dxp:
    cp      10
    ret     nc
    ld      a,(ix+V_PY)
    ld      b,a
    ld      a,(player_vec+V_PY)
    sub     b
    jr      nc,.dyp
    neg
.dyp:
    cp      12
    ret     nc
    ld      ix,player_vec
    set     7,(ix+V_STATUS)
    ret

otto_draw:
    ld      a,(otto_active)
    or      a
    ret     z
    ld      ix,otto_vec
    bit     1,(ix+V_STATUS)
    ret     z
    ; OR only — Otto walks through walls
    ld      b,(ix+V_PX)
    ld      c,(ix+V_PY)
    ld      (ix+V_OLDX),b
    ld      (ix+V_OLDY),c
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    jp      or_sprite
