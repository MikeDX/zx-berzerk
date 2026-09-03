; Score / HUD

; Add to score: B = digit power (0=units,1=tens,...), C = value 0-9
; Simplified: treat as add C * 10^B in BCD to score[3]
add_score:
    ld      a,1
    ld      (hud_dirty),a
    ld      hl,score+2                       ; point at ones/tens byte
    ; move HL left by B/2 bytes roughly — keep simple path for +10/+50
    ld      a,b
    cp      1
    jr      z,.tens
    cp      2
    jr      z,.hundreds
    ; units
    ld      a,(hl)
    add     a,c
    daa
    ld      (hl),a
    ret     nc
    jr      .carry
.tens:
    ld      a,c
    add     a,a
    add     a,a
    add     a,a
    add     a,a                             ; to high nibble
    add     a,(hl)
    daa
    ld      (hl),a
    ret     nc
.carry:
    dec     hl
    ld      a,(hl)
    add     a,1
    daa
    ld      (hl),a
    ret     nc
    dec     hl
    ld      a,(hl)
    add     a,1
    daa
    ld      (hl),a
    ret
.hundreds:
    dec     hl
    ld      a,c
    add     a,(hl)
    daa
    ld      (hl),a
    ret     nc
    dec     hl
    ld      a,(hl)
    add     a,1
    daa
    ld      (hl),a
    ret

; Draw score digits + lives as attribute bar / simple pixels
hud_draw:
    ld      a,(hud_dirty)
    or      a
    ret     z
    xor     a
    ld      (hud_dirty),a

    ; lives as cyan attributes bottom-left
    ld      hl,$5AE0
    ld      a,(deaths)
    ld      b,a
    ld      a,b
    or      a
    jr      z,.score
.life:
    ld      (hl),%01000101
    inc     hl
    djnz    .life

.score:
    ; show BCD score as attributes colour strip intensity — placeholder
    ; proper digit gfx later; flash border nibble for now is too crude
    ; plot 6 nibbles into top-right attrs
    ld      hl,$5818
    ld      de,score
    ld      b,3
.sc:
    ld      a,(de)
    rrca
    rrca
    rrca
    rrca
    and     $0F
    call    .digit_attr
    ld      a,(de)
    and     $0F
    call    .digit_attr
    inc     de
    djnz    .sc
    ret

.digit_attr:
    add     a,%01000000                     ; bright paper variations
    ld      (hl),a
    inc     hl
    ret
