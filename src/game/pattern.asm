; Sprite pattern engine, ported from the arcade MOVE_ANIMATE_VECTOR ($27A9)
; and WRITE_PATTERN ($274D).
;
; A pattern table is a list of 2-byte frame pointers stored HIGH byte first,
; ended by a $00 byte followed by a 2-byte restart pointer stored LOW byte
; first. The two byte orders are not a mistake -- the arcade reads frames with
; "ld d,(hl) / inc hl / ld e,(hl)" and restart pointers with
; "ld a,(hl) / inc hl / ld h,(hl) / ld l,a".
;
; Every pointer in these tables is an address in the original ROM, so they get
; run through pat_translate before use.

; HL = arcade address -> HL = address in our copy
pat_translate:
    ld      de,pat_rom - PAT_ROM_ORG
    add     hl,de
    ret

; HL = arcade pattern table. Always starts the table from the first frame,
; matching arcade CDIR / SETPAT which rewrite D.P on every direction change.
vec_set_pattern:
    ld      (ix+V_TAB_L),l
    ld      (ix+V_TAB_H),h
    ld      (ix+V_DP_L),l
    ld      (ix+V_DP_H),h
    ret

; Step D.P on to the next frame, following the restart pointer at the end.
; Arcade: $27C9-$27DD.
vec_next_frame:
    ld      l,(ix+V_DP_L)
    ld      h,(ix+V_DP_H)
    inc     hl
    inc     hl
    push    hl                              ; keep the arcade-space cursor
    call    pat_translate
    ld      a,(hl)
    or      a
    jr      nz,.keep
    inc     hl                              ; $00 ends the table
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a                             ; restart pointer, already arcade-space
    pop     de
    push    hl
.keep:
    pop     hl
    ld      (ix+V_DP_L),l
    ld      (ix+V_DP_H),h
    ret

; Resolve D.P into V_SPR (a local address) plus the draw offset in V_DX/V_DY.
; Arcade: $2765-$278A.
;
; A sprite record is "width, height, rows..." unless its first byte has bit 7
; set, in which case a 16-bit magic RAM offset precedes it. Magic RAM is 32
; bytes per row, so that offset means dy = off/32, dx = (off & 31) * 8.
vec_resolve_sprite:
    ld      l,(ix+V_DP_L)
    ld      h,(ix+V_DP_H)
    call    pat_translate
    ld      a,(hl)                          ; frame pointers are high byte first
    inc     hl
    ld      l,(hl)
    ld      h,a
    call    pat_translate

    xor     a
    ld      (ix+V_DX),a
    ld      (ix+V_DY),a
    ld      a,(hl)
    bit     7,a
    jr      z,.store

    inc     hl
    and     $7F
    ld      b,a
    ld      c,(hl)
    inc     hl
    push    hl
    ld      a,c
    and     31
    add     a,a
    add     a,a
    add     a,a
    ld      (ix+V_DX),a
    ld      a,b                             ; dy = BC >> 5
    ld      d,c
    srl     a
    rr      d
    srl     a
    rr      d
    srl     a
    rr      d
    srl     a
    rr      d
    srl     a
    rr      d
    ld      (ix+V_DY),d
    pop     hl

.store:
    ld      (ix+V_SPR_L),l
    ld      (ix+V_SPR_H),h
    ret
