; Robots — SEEK / SETPAT / BLAM

robots_clear:
    ld      ix,robot_vecs
    ld      b,MAX_ROBOTS
.cl:
    push    bc
    call    vec_clear
    ld      de,VEC_SIZE
    add     ix,de
    pop     bc
    djnz    .cl
    xor     a
    ld      (rcount),a
    ld      (rsaved),a
    ret

robots_spawn:
    call    robots_clear
    ld      hl,robot_spawns
    ld      b,NUM_SPAWNS
.try:
    push    bc
    push    hl
    call    random
    ld      c,a
    ld      a,(spawn_thresh)
    cp      c
    jr      c,.skip

    ld      b,(hl)
    inc     hl
    ld      c,(hl)
    call    random
    and     $1F
    add     a,b
    ld      b,a
    call    random
    and     $1F
    add     a,c
    ld      c,a
    ld      a,c
    cp      168
    jr      c,.yok
    ld      c,150
.yok:
    push    bc
    ld      a,b
    add     a,4
    ld      b,a
    ld      a,c
    add     a,5
    ld      c,a
    call    pixel_hits_wall
    pop     bc
    jr      c,.skip
    call    robot_create
.skip:
    pop     hl
    inc     hl
    inc     hl
    pop     bc
    djnz    .try

    ld      a,(rcount)
    ld      (rsaved),a
    ld      a,(robot_speed)
    ld      c,a
    ld      a,(rsaved)
    add     a,c
    add     a,50
    ld      (otto_timer),a
    xor     a
    ld      (otto_active),a
    ret

robot_create:
    ld      ix,robot_vecs
    ld      e,MAX_ROBOTS
.find:
    ld      a,(ix+V_KIND)
    or      a
    jr      z,.use
    push    de
    ld      de,VEC_SIZE
    add     ix,de
    pop     de
    dec     e
    ret     z
    jr      .find
.use:
    push    bc
    call    vec_clear
    pop     bc
    ld      a,KIND_ROBOT
    ld      (ix+V_KIND),a
    ld      a,ST_MOVE|ST_WRITE
    ld      (ix+V_STATUS),a
    ld      (ix+V_PX),b
    ld      (ix+V_PY),c
    ld      (ix+V_OLDX),b
    ld      (ix+V_OLDY),c
    ld      a,$FF
    ld      (ix+V_LAST),a
    xor     a
    call    robot_setpat
    ld      a,(robot_speed)
    ld      (ix+V_TPRIME),a
    ld      a,1
    ld      (ix+V_TIME),a
    ld      hl,rcount
    inc     (hl)
    ret

robots_update:
    ld      ix,robot_vecs
    ld      b,MAX_ROBOTS
.loop:
    push    bc
    ld      a,(ix+V_KIND)
    cp      KIND_ROBOT
    call    z,.one
    ld      de,VEC_SIZE
    add     ix,de
    pop     bc
    djnz    .loop
    ret

.one:
    call    entity_erase
    bit     7,(ix+V_STATUS)
    jp      nz,robot_exploding

    ld      a,(player_vec+V_PX)
    sub     (ix+V_PX)
    ld      d,0
    jr      z,.vert
    ld      d,LEFT
    jr      c,.vert
    ld      d,RIGHT
.vert:
    ld      a,(player_vec+V_PY)
    add     a,2
    sub     (ix+V_PY)
    ld      e,0
    jr      z,.dirs
    ld      e,UP
    jr      c,.dirs
    ld      e,DOWN
.dirs:
    ld      a,d
    or      e
    push    af
    ld      a,d
    or      a
    jr      z,.aligned
    ld      a,e
    or      a
    jr      nz,.noshoot
.aligned:
    call    random
    cp      16
    jr      nc,.noshoot
    pop     af
    push    af
    call    robot_try_fire
.noshoot:
    pop     af
    call    robot_setpat
    call    entity_move
    set     0,(ix+V_STATUS)
    set     1,(ix+V_STATUS)
    ret

; HIT is set: start or continue the $103B explosion, then remove.
robot_exploding:
    ld      a,(ix+V_TAB_L)
    cp      PAT_EXPLOSION & $FF
    jr      nz,.start
    ld      a,(ix+V_TAB_H)
    cp      PAT_EXPLOSION >> 8
    jr      z,.run
.start:
    xor     a
    ld      (ix+V_VX),a
    ld      (ix+V_VY),a
    ld      a,(ix+V_PX)
    sub     4
    ld      (ix+V_PX),a
    ld      a,(ix+V_PY)
    sub     6
    ld      (ix+V_PY),a
    ld      hl,PAT_EXPLOSION
    call    vec_set_pattern
    ld      a,1
    ld      (ix+V_TIME),a
    ld      (ix+V_TPRIME),a
    ld      b,1
    ld      c,5
    call    add_score
    ld      hl,otto_timer
    inc     (hl)
    inc     (hl)
    set     0,(ix+V_STATUS)
    set     1,(ix+V_STATUS)
    ret
.run:
    call    entity_move
    ld      a,(ix+V_DP_L)
    cp      $41
    jr      nz,.keep
    ld      a,(ix+V_DP_H)
    cp      $10
    jp      z,robot_remove
.keep:
    set     0,(ix+V_STATUS)
    set     1,(ix+V_STATUS)
    ret

robot_remove:
    xor     a
    ld      (ix+V_KIND),a
    ld      (ix+V_STATUS),a
    ld      hl,rcount
    ld      a,(hl)
    or      a
    jr      z,.nob
    dec     (hl)
.nob:
    ld      a,(rcount)
    or      a
    ret     nz
    ld      a,(rsaved)
    or      a
    ret     z
    ld      b,a
.bonus:
    push    bc
    ld      b,1
    ld      c,1
    call    add_score
    pop     bc
    djnz    .bonus
    ret

robots_draw:
    ld      ix,robot_vecs
    ld      b,MAX_ROBOTS
.dl:
    push    bc
    ld      a,(ix+V_KIND)
    cp      KIND_ROBOT
    jr      nz,.dn
    bit     1,(ix+V_STATUS)
    jr      z,.dn
    bit     7,(ix+V_STATUS)
    jr      nz,.blast
    call    entity_draw
    ld      a,(draw_collide)
    or      a
    jr      z,.dn
    set     7,(ix+V_STATUS)
    jr      .dn
.blast:
    call    entity_draw_noclip
.dn:
    ld      de,VEC_SIZE
    add     ix,de
    pop     bc
    djnz    .dl
    ret
