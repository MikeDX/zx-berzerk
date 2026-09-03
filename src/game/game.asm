; Room / game flow

game_init:
    xor     a
    ld      (room_x),a
    ld      (room_y),a
    ld      a,3
    ld      (deaths),a
    ld      a,$90
    ld      (spawn_thresh),a
    xor     a
    ld      (rbolts_max),a
    ld      a,5
    ld      (robot_speed),a
    ld      a,$5A
    ld      (rwait),a
    xor     a
    ld      (score),a
    ld      (score+1),a
    ld      (score+2),a
    ld      a,$1E
    ld      (man_x),a
    ld      a,$64
    ld      (man_y),a
    ld      a,1
    ld      (hud_dirty),a
    call    bolts_clear
    call    otto_clear
    jp      room_enter

room_enter:
    call    zx_cls
    ; colour playfield green walls feel
    ld      hl,$5800
    ld      de,$5801
    ld      bc,767
    ld      (hl),%00000100                  ; green ink
    ldir

    call    maze_build
    call    bolts_clear
    call    otto_clear
    call    robots_spawn
    call    player_init
    ld      a,1
    ld      (hud_dirty),a
    call    hud_draw
    ret

room_restart_life:
    ld      a,$1E
    ld      (man_x),a
    ld      a,$64
    ld      (man_y),a
    jp      room_enter

; Bump difficulty then enter (after exit)
room_next:
    ld      a,(spawn_thresh)
    add     a,$20
    jr      nc,.st
    ld      a,$E0
.st:
    ld      (spawn_thresh),a
    ld      a,(robot_speed)
    cp      1
    jr      z,.rw
    dec     a
    ld      (robot_speed),a
.rw:
    ld      a,(rwait)
    cp      $14
    jr      c,.rb
    sub     $0A
    ld      (rwait),a
.rb:
    ; enable robot shots after a few rooms
    ld      a,(room_x)
    ld      b,a
    ld      a,(room_y)
    add     a,b
    cp      2
    jr      c,.enter
    ld      a,2
    ld      (rbolts_max),a
.enter:
    jp      room_enter

; Check player for room exits
room_check_exit:
    ld      a,(player_vec+V_PX)
    cp      EXIT_RIGHT
    jr      c,.not_r
    ld      hl,room_x
    inc     (hl)
    ld      a,ENTER_RIGHT_X
    ld      (man_x),a
    ld      a,(player_vec+V_PY)
    ld      (man_y),a
    jp      room_next
.not_r:
    cp      2
    jr      nc,.chk_y
    ld      hl,room_x
    dec     (hl)
    ld      a,ENTER_LEFT_X
    ld      (man_x),a
    ld      a,(player_vec+V_PY)
    ld      (man_y),a
    jp      room_next

.chk_y:
    ld      a,(player_vec+V_PY)
    cp      EXIT_BOTTOM
    jr      c,.not_b
    ld      hl,room_y
    inc     (hl)
    ld      a,(player_vec+V_PX)
    ld      (man_x),a
    ld      a,ENTER_BOT_Y
    ld      (man_y),a
    jp      room_next
.not_b:
    cp      EXIT_TOP
    ret     nc
    ld      hl,room_y
    dec     (hl)
    ld      a,(player_vec+V_PX)
    ld      (man_x),a
    ld      a,ENTER_TOP_Y
    ld      (man_y),a
    jp      room_next

game_over:
    ; red border, freeze until fire
    ld      a,2
    out     ($FE),a
.wait:
    halt
    call    input_poll
    and     FIRE
    jr      z,.wait
    xor     a
    out     ($FE),a
    jp      game_init

; Main per-frame update
game_frame:
    call    player_update
    call    robots_update
    call    otto_update
    call    bolts_update

    call    player_draw
    call    robots_draw
    call    otto_draw

    call    hud_draw
    call    room_check_exit
    ret
