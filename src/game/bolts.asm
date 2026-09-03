; Laser bolts — plot against wall mask; restore pixels on erase

bolts_clear:
    ld      hl,player_bolts
    ld      b,BOLT_SIZE * MAX_PBOLTS + BOLT_SIZE * MAX_RBOLTS
    xor     a
.cl:
    ld      (hl),a
    inc     hl
    djnz    .cl
    ret

; A = full input (FIRE | DURL). Arcade FIRE ($1F1B) using SR.TAB.
player_try_fire:
    ld      c,a
    ld      a,(player_fire_cd)
    or      a
    ret     nz
    ld      a,c
    and     $0F
    ret     z
    ld      iy,player_bolts
    ld      b,MAX_PBOLTS
.find:
    ld      a,(iy+B_DIR)
    or      a
    jr      z,.slot
    ld      de,BOLT_SIZE
    add     iy,de
    djnz    .find
    ret
.slot:
    ld      a,c
    ld      hl,sr_tab
    call    durl_to_6
    xor     a
    ld      (ix+V_VX),a
    ld      (ix+V_VY),a
    ld      a,(hl)
    inc     hl
    ld      (ix+V_DP_L),a
    ld      (ix+V_TAB_L),a
    ld      a,(hl)
    inc     hl
    ld      (ix+V_DP_H),a
    ld      (ix+V_TAB_H),a
    ld      b,(hl)                          ; X offset
    inc     hl
    ld      c,(hl)                          ; Y offset
    inc     hl
    ld      a,(hl)                          ; bolt DURL
    ld      (iy+B_DIR),a
    ld      (iy+B_LAST),a
    xor     a
    ld      (iy+B_LEN),a
    ld      a,12
    ld      (iy+B_MAX),a
    ld      a,(ix+V_PX)
    add     a,b
    ld      (iy+B_X),a
    ld      (iy+B_TX),a
    ld      a,(ix+V_PY)
    add     a,c
    ld      (iy+B_Y),a
    ld      (iy+B_TY),a
    ld      a,8
    ld      (player_fire_cd),a
    ret

; A = DURL, IX = firing robot. Arcade SHOOT using S.TAB.
robot_try_fire:
    ld      c,a
    ld      a,(rbolts_max)
    or      a
    ret     z
    ld      iy,robot_bolts
    ld      b,MAX_RBOLTS
.rf:
    ld      a,(iy+B_DIR)
    or      a
    jr      z,.rslot
    ld      de,BOLT_SIZE
    add     iy,de
    djnz    .rf
    ret
.rslot:
    ld      a,c
    ld      hl,shoot_tab
    call    durl_to_6
    inc     hl                              ; skip pattern
    inc     hl
    ld      b,(hl)
    inc     hl
    ld      c,(hl)
    inc     hl
    ld      a,(hl)
    ld      (iy+B_DIR),a
    xor     a
    ld      (iy+B_LEN),a
    ld      a,5
    ld      (iy+B_MAX),a
    ld      a,(ix+V_PX)
    add     a,b
    ld      (iy+B_X),a
    ld      (iy+B_TX),a
    ld      a,(ix+V_PY)
    add     a,c
    ld      (iy+B_Y),a
    ld      (iy+B_TY),a
    ret


bolts_update:
    ; player bolts: only hurt robots
    xor     a
    ld      (bolt_from_robot),a
    ld      iy,player_bolts
    ld      b,MAX_PBOLTS
    call    .group
    ; robot bolts: hurt the player and other robots
    ld      a,1
    ld      (bolt_from_robot),a
    ld      iy,robot_bolts
    ld      b,MAX_RBOLTS
    call    .group
    ret

.group:
    push    bc
    ld      a,(iy+B_DIR)
    or      a
    jr      z,.next
    call    bolt_step
.next:
    ld      de,BOLT_SIZE
    add     iy,de
    pop     bc
    djnz    .group
    ret

bolt_step:
    ld      a,(iy+B_LEN)
    or      a
    jr      z,.grow
    ld      c,a
    ld      a,(iy+B_MAX)
    cp      c
    jp      z,.shrink

.grow:
    ld      a,(iy+B_DIR)
    ld      b,(iy+B_X)
    ld      c,(iy+B_Y)
    bit     0,a
    jr      z,.nl
    dec     b
.nl:
    bit     1,a
    jr      z,.nr
    inc     b
.nr:
    bit     2,a
    jr      z,.nu
    dec     c
.nu:
    bit     3,a
    jr      z,.moved
    inc     c
.moved:
    ld      a,b
    or      a
    jp      z,.kill
    inc     a
    jp      z,.kill
    ld      a,c
    or      a
    jp      z,.kill
    cp      192
    jp      nc,.kill

    call    pixel_hits_wall
    jp      c,.kill

    ld      (iy+B_X),b
    ld      (iy+B_Y),c
    call    plot_pixel
    ld      a,(iy+B_LEN)
    inc     a
    ld      (iy+B_LEN),a
    call    bolt_hit_check
    ret

.kill:
    ld      b,(iy+B_X)
    ld      c,(iy+B_Y)
    ld      a,(iy+B_LEN)
    or      a
    call    nz,restore_pixel
    ld      b,(iy+B_TX)
    ld      c,(iy+B_TY)
    ld      a,b
    cp      (iy+B_X)
    jr      nz,.rest_tail
    ld      a,c
    cp      (iy+B_Y)
    jr      z,.cleared
.rest_tail:
    call    restore_pixel
.cleared:
    xor     a
    ld      (iy+B_DIR),a
    ld      (iy+B_LEN),a
    ret

.shrink:
    ld      b,(iy+B_TX)
    ld      c,(iy+B_TY)
    call    restore_pixel
    ld      a,(iy+B_X)
    ld      (iy+B_TX),a
    ld      a,(iy+B_Y)
    ld      (iy+B_TY),a
    jp      .grow

bolt_hit_check:
    ld      a,(bolt_from_robot)
    or      a
    jr      z,.robots_only
    ld      ix,player_vec
    ld      a,(ix+V_KIND)
    cp      KIND_PLAYER
    call    z,.vs_vec
.robots_only:
    ld      ix,robot_vecs
    ld      b,MAX_ROBOTS
.rv:
    push    bc
    ld      a,(ix+V_KIND)
    cp      KIND_ROBOT
    call    z,.vs_vec
    ld      de,VEC_SIZE
    add     ix,de
    pop     bc
    djnz    .rv
    ret

.vs_vec:
    ld      a,(iy+B_X)
    sub     (ix+V_PX)
    ret     m
    cp      10
    ret     nc
    ld      a,(iy+B_Y)
    sub     (ix+V_PY)
    ret     m
    cp      16
    ret     nc
    set     7,(ix+V_STATUS)
    ld      b,(iy+B_X)
    ld      c,(iy+B_Y)
    call    restore_pixel
    xor     a
    ld      (iy+B_DIR),a
    ret
