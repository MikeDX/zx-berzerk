; Phase-0 smoke test: banner + live input bit display.

demo_banner:
    ; Cyan attribute bar across the top row
    ld      hl,$5800
    ld      b,32
.bar:
    ld      (hl),%01000101                  ; bright cyan ink
    inc     hl
    djnz    .bar

    ; Diagonal pixels — confirms bitmap addressing
    ld      b,0
.diag:
    ld      c,b                             ; y = x
    push    bc
    call    zx_pixel_addr
    pop     bc
    ld      a,b
    and     7
    push    bc
    ld      b,a
    ld      a,%10000000
    inc     b
.shift:
    dec     b
    jr      z,.store
    rrca
    jr      .shift
.store:
    or      (hl)
    ld      (hl),a
    pop     bc
    inc     b
    ld      a,b
    cp      64
    jr      c,.diag
    ret

; A = input bits. Five attribute cells on row 1 show LEFT RIGHT UP DOWN FIRE.
demo_show_input:
    ld      hl,$5820
    ld      c,a
    ld      b,5
.bit:
    xor     a
    srl     c
    jr      nc,.off
    ld      a,%01111010                     ; bright yellow/blue = pressed
    jr      .put
.off:
    ld      a,%00000001                     ; blue = released
.put:
    ld      (hl),a
    inc     hl
    djnz    .bit
    ret
