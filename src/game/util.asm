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
; Also returns DE = d_tab offset (for callers that need it)
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
