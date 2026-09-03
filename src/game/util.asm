; RNG and velocity helpers

; A = next random (arcade $2678)
random:
    push    hl
    push    de
    ld      hl,(rng_seed)
    ld      d,h
    ld      e,l
    add     hl,hl
    add     hl,de
    add     hl,hl
    add     hl,de
    ld      de,$3153
    add     hl,de
    ld      (rng_seed),hl
    ld      a,h
    pop     de
    pop     hl
    ret

; A = DURL bits → set IX vector VX/VY from m_tab
; Returns DE = D.TAB offset (arcade SET_VELOCITY $2B3D)
set_velocity:
    and     $0F
    ld      c,a
    ld      b,0
    ld      hl,d_tab
    add     hl,bc
    ld      e,(hl)
    ld      d,0
    ld      hl,m_tab
    add     hl,de
    ld      a,(hl)
    ld      (ix+V_VX),a
    inc     hl
    ld      a,(hl)
    ld      (ix+V_VY),a
    ret

; CDIR ($1F94): A = DURL. Sets velocity and player walk/still/death table.
cdir:
    call    set_velocity                    ; DE = D.TAB offset
    ld      hl,p_tab
    add     hl,de
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a                             ; arcade address of pattern table
    jp      vec_set_pattern

; SETPAT ($2436): A = DURL. Sets velocity and robot animation table.
; Skips if A equals the last direction this vector used.
robot_setpat:
    and     $0F
    cp      (ix+V_LAST)
    ret     z
    ld      (ix+V_LAST),a
    call    set_velocity
    ld      hl,robot_anim_tab
    add     hl,de
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a                             ; arcade address of pattern table
    call    vec_set_pattern
    or      1
    ret

; A = DURL, HL = 6-byte-record table (SR.TAB / S.TAB)
; Returns HL = table + D.TAB[A]*3
durl_to_6:
    and     $0F
    ld      c,a
    ld      b,0
    push    hl
    ld      hl,d_tab
    add     hl,bc
    ld      e,(hl)
    ld      d,0
    pop     hl
    add     hl,de
    add     hl,de
    add     hl,de
    ret

; Clear a VECTOR to empty
vec_clear:
    push    bc
    push    hl
    push    ix
    pop     hl
    ld      b,VEC_SIZE
    xor     a
.cl:
    ld      (hl),a
    inc     hl
    djnz    .cl
    pop     hl
    pop     bc
    ret
