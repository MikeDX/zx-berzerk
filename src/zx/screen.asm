; ZX Spectrum display helpers (48K bitmap + attributes)

ATTR_P          EQU $5C8D                   ; system variable: permanent attrs
BORDCR          EQU $5C48

; Clear screen to black paper / white ink, border black.
zx_cls:
    ld      hl,$4000
    ld      de,$4001
    ld      bc,6144 - 1
    ld      (hl),0
    ldir

    ld      hl,$5800
    ld      de,$5801
    ld      bc,768 - 1
    ld      (hl),%00000111                  ; ink 7, paper 0, bright 0
    ldir

    xor     a
    out     ($FE),a                         ; black border
    ret

; Print A (ASCII) at character cell B=column (0-31), C=row (0-23).
; Uses the 48K ROM font at $3D00.
zx_print_char:
    push    bc
    push    de
    push    hl
    ld      h,0
    ld      l,a
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      de,$3D00 - 256                  ; $3D00 - 32*8
    add     hl,de
    ex      de,hl                           ; DE -> glyph
    ld      a,c
    and     %00011000
    or      %01000000
    ld      h,a
    ld      a,c
    and     7
    rrca
    rrca
    rrca
    or      b
    ld      l,a
    ld      b,8
.row:
    ld      a,(de)
    ld      (hl),a
    inc     de
    inc     h
    djnz    .row
    pop     hl
    pop     de
    pop     bc
    ret

; HL -> NUL-terminated string. B=column, C=row.
zx_print:
    ld      a,(hl)
    or      a
    ret     z
    inc     hl
    call    zx_print_char
    inc     b
    jr      zx_print


; HL = pixel address for (B=x 0..255, C=y 0..191)
; Standard Spectrum screen address formula.
zx_pixel_addr:
    ld      a,c
    and     %00000111
    or      %01000000
    ld      h,a
    ld      a,c
    rra
    rra
    rra
    and     %00011000
    or      h
    ld      h,a
    ld      a,c
    rla
    rla
    and     %11100000
    ld      l,a
    ld      a,b
    rra
    rra
    rra
    and     %00011111
    or      l
    ld      l,a
    ret
