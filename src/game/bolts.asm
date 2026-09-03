; Laser bolts

; Clear all bolts
bolts_clear:
    ld      hl,player_bolts
    ld      b,BOLT_SIZE * MAX_PBOLTS + BOLT_SIZE * MAX_RBOLTS
    xor     a
.cl:
    ld      (hl),a
    inc     hl
    djnz    .cl
    ret

; Fire player bolt if a free slot exists.
; Uses player_vec position + player_dir
player_try_fire:
    ld      a,(player_dir)
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
    ld      a,(player_dir)
    and     $0F
    ld      (iy+B_DIR),a
    ld      (iy+B_LAST),a
    xor     a
    ld      (iy+B_LEN),a
    ld      a,12
    ld      (iy+B_MAX),a
    ld      a,(player_vec+V_PX)
    add     a,3
    ld      (iy+B_X),a
    ld      (iy+B_TX),a
    ld      a,(player_vec+V_PY)
    add     a,6
    ld      (iy+B_Y),a
    ld      (iy+B_TY),a
    ret

; Robot fire from IX robot toward DURL in A
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
    and     $0F
    ld      (iy+B_DIR),a
    xor     a
    ld      (iy+B_LEN),a
    ld      a,5
    ld      (iy+B_MAX),a
    ld      a,(ix+V_PX)
    add     a,3
    ld      (iy+B_X),a
    ld      (iy+B_TX),a
    ld      a,(ix+V_PY)
    add     a,4
    ld      (iy+B_Y),a
    ld      (iy+B_TY),a
    ret

; Advance all active bolts one step
bolts_update:
    ld      iy,player_bolts
    ld      b,MAX_PBOLTS + MAX_RBOLTS
.loop:
    push    bc
    ld      a,(iy+B_DIR)
    or      a
    jr      z,.next
    call    bolt_step
.next:
    ld      de,BOLT_SIZE
    add     iy,de
    pop     bc
    djnz    .loop
    ret

; Step one bolt in IY
bolt_step:
    ; erase tail pixel if length > 0 by XOR again
    ld      a,(iy+B_LEN)
    or      a
    jr      z,.grow
    ; if at max, shrink from tail
    ld      a,(iy+B_LEN)
    ld      c,a
    ld      a,(iy+B_MAX)
    cp      c
    jr      z,.shrink

.grow:
    ; move head
    ld      a,(iy+B_DIR)
    ld      b,(iy+B_X)
    ld      c,(iy+B_Y)
    bit     0,a
    jr      z,.nr
    dec     b
.nr:
    bit     1,a
    jr      z,.nu
    inc     b
.nu:
    bit     2,a
    jr      z,.nd
    dec     c
.nd:
    bit     3,a
    jr      z,.moved
    inc     c
.moved:
    ; offscreen?
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

    ld      (iy+B_X),b
    ld      (iy+B_Y),c
    call    xor_pixel
    jr      c,.hit_wall
    ld      a,(iy+B_LEN)
    inc     a
    ld      (iy+B_LEN),a
    ; AABB vs entities
    call    bolt_hit_check
    ret

.hit_wall:
    ; pixel already there — leave the colliding XOR undone? xor_pixel already flipped.
    ; Flip back to restore wall, kill bolt.
    ld      b,(iy+B_X)
    ld      c,(iy+B_Y)
    call    xor_pixel
    call    bolt_hit_check
.kill:
    xor     a
    ld      (iy+B_DIR),a
    ret

.shrink:
    ; erase oldest tail — approximate: kill bolt trail by clearing dir
    ; For simplicity when maxed, keep moving head and erase previous head
    ld      b,(iy+B_TX)
    ld      c,(iy+B_TY)
    ld      a,b
    or      c
    call    nz,xor_pixel
    ld      a,(iy+B_X)
    ld      (iy+B_TX),a
    ld      a,(iy+B_Y)
    ld      (iy+B_TY),a
    jr      .grow

; Bolt head vs player / robots
bolt_hit_check:
    ; vs player
    ld      ix,player_vec
    ld      a,(ix+V_KIND)
    cp      KIND_PLAYER
    call    z,.vs_vec
    ; vs robots
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
    set     7,(ix+V_STATUS)                ; HIT
    xor     a
    ld      (iy+B_DIR),a
    ret
