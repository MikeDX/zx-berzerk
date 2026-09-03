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
