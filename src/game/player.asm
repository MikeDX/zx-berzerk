; Player humanoid

player_init:
    ld      ix,player_vec
    call    vec_clear
    ld      a,KIND_PLAYER
    ld      (ix+V_KIND),a
    ld      a,ST_MOVE|ST_WRITE
    ld      (ix+V_STATUS),a
    ld      a,(man_x)
    ld      (ix+V_PX),a
    ld      a,(man_y)
    ld      (ix+V_PY),a
    ld      a,2
    ld      (ix+V_TPRIME),a
    ld      (ix+V_TIME),a
    ld      hl,spr_player
    ld      (ix+V_SPR_L),l
    ld      (ix+V_SPR_H),h
    xor     a
    ld      (player_firing),a
    ret

; Erase then update then prepare draw
player_update:
    ld      ix,player_vec
    ld      a,(ix+V_KIND)
    or      a
    ret     z

    ; erase old
    ld      a,(ix+V_STATUS)
    bit     0,a                             ; ERASE?
    call    nz,entity_erase
    res     0,(ix+V_STATUS)

    ; hit?
    bit     7,(ix+V_STATUS)
    jp      nz,player_die

    call    input_poll
    ld      c,a
    ld      a,c
    and     FIRE
    jr      z,.nofire
    ld      a,1
    ld      (player_firing),a
    ld      a,c
    and     $0F
    jr      z,.aim_only
    ld      (player_dir),a
.aim_only:
    ; stand still while firing
    xor     a
    ld      (ix+V_VX),a
    ld      (ix+V_VY),a
    call    player_try_fire
    jr      .animate

.nofire:
    xor     a
    ld      (player_firing),a
    ld      a,c
    and     $0F
    jr      z,.still
    ld      (player_dir),a
    call    set_velocity
    jr      .tick

.still:
    xor     a
    ld      (ix+V_VX),a
    ld      (ix+V_VY),a

.tick:
    call    entity_move

.animate:
    ld      a,(player_firing)
    or      a
    ld      hl,spr_player
    jr      nz,.setspr
    ld      a,(ix+V_VX)
    or      (ix+V_VY)
    ld      hl,spr_player
    jr      z,.setspr
    ld      hl,spr_player_walk
.setspr:
    ld      (ix+V_SPR_L),l
    ld      (ix+V_SPR_H),h
    set     1,(ix+V_STATUS)                ; WRITE
    set     0,(ix+V_STATUS)                ; ERASE next frame
    ret

player_die:
    ; lose life, restart room
    ld      a,(deaths)
    or      a
    jr      z,.gameover
    dec     a
    ld      (deaths),a
    ld      a,1
    ld      (hud_dirty),a
    ; brief flash
    ld      a,2
    out     ($FE),a
    call    room_restart_life
    xor     a
    out     ($FE),a
    ret
.gameover:
    jp      game_over

; Draw player if WRITE set
player_draw:
    ld      ix,player_vec
    bit     1,(ix+V_STATUS)
    ret     z
    call    entity_draw
    ; wall collision kills
    ld      a,(draw_collide)
    or      a
    ret     z
    set     7,(ix+V_STATUS)
    ret
