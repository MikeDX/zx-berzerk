; Player humanoid — MOVE_PLAYER / FIRE / CDIR / MAN_INIT

player_init:
    ld      ix,player_vec
    call    vec_clear
    ld      a,KIND_PLAYER
    ld      (ix+V_KIND),a
    ld      a,ST_MOVE|ST_WRITE
    ld      (ix+V_STATUS),a
    ld      a,2
    ld      (ix+V_TPRIME),a
    ld      a,1
    ld      (ix+V_TIME),a
    ld      a,$FF
    ld      (player_dir),a                  ; force CDIR on first stick read
    xor     a
    ld      (player_fire_cd),a
    call    cdir                            ; still pose, velocity 0
    jp      player_place

; Place at man_x/man_y, nudging until the resolved sprite is clear of walls.
player_place:
    ld      a,(man_x)
    ld      (ix+V_PX),a
    ld      a,(man_y)
    ld      (ix+V_PY),a
    call    vec_resolve_sprite

    ld      d,8
.xtry:
    ld      a,(man_y)
    ld      (ix+V_PY),a
    ld      e,10
.ytry:
    call    entity_draw_pos
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    push    de
    call    collide_sprite
    pop     de
    ld      a,(draw_collide)
    or      a
    jr      z,.placed
    ld      a,(ix+V_PY)
    add     a,8
    cp      170
    jr      c,.keepy
    ld      a,16
.keepy:
    ld      (ix+V_PY),a
    dec     e
    jr      nz,.ytry
    ld      a,(ix+V_PX)
    add     a,12
    cp      230
    jr      c,.keepx
    ld      a,12
.keepx:
    ld      (ix+V_PX),a
    dec     d
    jr      nz,.xtry

.placed:
    ld      a,(ix+V_PX)
    ld      (man_x),a
    ld      (ix+V_OLDX),a
    ld      a,(ix+V_PY)
    ld      (man_y),a
    ld      (ix+V_OLDY),a
    ret

player_update:
    ld      ix,player_vec
    ld      a,(ix+V_KIND)
    or      a
    ret     z

    bit     7,(ix+V_STATUS)
    jp      nz,player_die

    ld      a,(player_fire_cd)
    or      a
    jr      z,.cdok
    dec     a
    ld      (player_fire_cd),a
.cdok:
    ld      e,0                             ; E != 0 means need a blit
    ld      a,(ix+V_PX)
    ld      h,(ix+V_PY)
    ld      l,a
    push    hl
    ld      a,(ix+V_DP_L)
    ld      h,(ix+V_DP_H)
    ld      l,a
    push    hl
    call    input_poll
    ld      d,a
    and     FIRE
    jr      z,.nofire
    ld      a,d
    call    player_try_fire
    jr      .tick

.nofire:
    ld      a,d
    and     $0F
    ld      hl,player_dir
    cp      (hl)
    jr      z,.tick
    ld      (hl),a
    call    cdir

.tick:
    call    entity_move
    call    player_touch_robots
    pop     hl                              ; previous D.P
    ld      a,(ix+V_DP_L)
    cp      l
    jr      nz,.changed
    ld      a,(ix+V_DP_H)
    cp      h
    jr      nz,.changed
    pop     hl                              ; previous P.X/P.Y
    ld      a,(ix+V_PX)
    cp      l
    jr      nz,.blit
    ld      a,(ix+V_PY)
    cp      h
    ret     z
    jr      .blit
.changed:
    pop     hl
.blit:
    set     1,(ix+V_STATUS)
    ret

player_die:
    ld      a,(deaths)
    or      a
    jr      z,.gameover
    dec     a
    ld      (deaths),a
    ld      a,1
    ld      (hud_dirty),a
    ld      a,2
    out     ($FE),a
    call    room_restart_life
    xor     a
    out     ($FE),a
    ret
.gameover:
    jp      game_over

player_draw:
    ld      ix,player_vec
    bit     1,(ix+V_STATUS)
    ret     z
    call    vec_resolve_sprite
    call    entity_draw_pos
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    push    bc
    call    collide_sprite
    pop     bc
    ld      a,(draw_collide)
    or      a
    jr      z,.paint
    ; Wall: undo the step, leave the last good sprite on screen (arcade
    ; electrocutes; we refuse the move until the maze is pixel-exact).
    ld      a,(ix+V_OLDX)
    ld      (ix+V_PX),a
    ld      a,(ix+V_OLDY)
    ld      (ix+V_PY),a
    xor     a
    ld      (ix+V_VX),a
    ld      (ix+V_VY),a
    res     1,(ix+V_STATUS)
    ret
.paint:
    call    entity_erase
    call    entity_draw_pos
    ld      l,(ix+V_SPR_L)
    ld      h,(ix+V_SPR_H)
    call    or_sprite
    call    entity_stash_old
    res     1,(ix+V_STATUS)
    set     0,(ix+V_STATUS)
    ret

; Touching a live robot kills the player (arcade Magic RAM intercept).
player_touch_robots:
    ld      ix,robot_vecs
    ld      b,MAX_ROBOTS
.lp:
    push    bc
    ld      a,(ix+V_KIND)
    cp      KIND_ROBOT
    jr      nz,.nx
    bit     7,(ix+V_STATUS)
    jr      nz,.nx
    ld      a,(player_vec+V_PX)
    sub     (ix+V_PX)
    jr      nc,.dx
    neg
.dx:
    cp      8
    jr      nc,.nx
    ld      a,(player_vec+V_PY)
    sub     (ix+V_PY)
    jr      nc,.dy
    neg
.dy:
    cp      12
    jr      nc,.nx
    pop     bc
    ld      ix,player_vec
    set     7,(ix+V_STATUS)
    ret
.nx:
    ld      de,VEC_SIZE
    add     ix,de
    pop     bc
    djnz    .lp
    ret
