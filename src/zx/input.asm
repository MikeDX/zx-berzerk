; Control: Kempston joystick + QAOP/Space defaults + redefine table.
;
; Output of input_poll (active-high bits, arcade Berzerk DURL style):
;   bit 0 = LEFT
;   bit 1 = RIGHT
;   bit 2 = UP
;   bit 3 = DOWN
;   bit 4 = FIRE

IN_LEFT         EQU %00000001
IN_RIGHT        EQU %00000010
IN_UP           EQU %00000100
IN_DOWN         EQU %00001000
IN_FIRE         EQU %00010000

KEMPSTON_PORT   EQU $1F

; Key map entries: (FE-port high byte / row, active-low bit mask)
; Defaults: Q=up A=down O=left P=right Space=fire
keymap:
                db $FB, %00000001           ; Q  — UP
                db $FD, %00000001           ; A  — DOWN
                db $DF, %00000010           ; O  — LEFT
                db $DF, %00000001           ; P  — RIGHT
                db $7F, %00000001           ; Space — FIRE

; Parallel bit values written into result when that key is down
keybits:
                db IN_UP, IN_DOWN, IN_LEFT, IN_RIGHT, IN_FIRE

input_init:
    ret

; Returns A = Kempston OR keyboard bits.
input_poll:
    push    bc
    push    de
    push    hl

    ld      e,0                             ; E = result

    ; Kempston bit order: 0=RIGHT 1=LEFT 2=DOWN 3=UP 4=FIRE
    ; $FF usually means no interface on the bus — ignore it.
    in      a,(KEMPSTON_PORT)
    inc     a
    jr      z,.kb
    dec     a
    bit     1,a
    jr      z,.kr
    set     0,e                             ; LEFT
.kr:
    bit     0,a
    jr      z,.ku
    set     1,e                             ; RIGHT
.ku:
    bit     3,a
    jr      z,.kd
    set     2,e                             ; UP
.kd:
    bit     2,a
    jr      z,.kf
    set     3,e                             ; DOWN
.kf:
    bit     4,a
    jr      z,.kb
    set     4,e                             ; FIRE
.kb:
    ; Keyboard: 5 entries
    ld      hl,keymap
    ld      bc,keybits
    ld      d,5
.kloop:
    push    bc
    ld      b,(hl)                          ; row in B
    inc     hl
    ld      c,$FE
    ld      a,(hl)                          ; mask
    inc     hl
    push    af
    in      a,(c)
    pop     bc                              ; B = mask (C garbage)
    and     b
    pop     bc                              ; restore keybits ptr in BC
    jr      nz,.next                        ; key up (bit still set)
    ld      a,(bc)
    or      e
    ld      e,a
.next:
    inc     bc
    dec     d
    jr      nz,.kloop

    ld      a,e
    pop     hl
    pop     de
    pop     bc
    ret
