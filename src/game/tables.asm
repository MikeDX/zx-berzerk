; Tables: velocities, door template, robot spawn bases, DURL→index

; DURL bitmask → offset into M.TAB / direction tables (arcade D.TAB)
; Index = DURL & $0F
d_tab:
    db 0                                    ; 0  none
    db 12                                   ; 1  left
    db 4                                    ; 2  right
    db 0                                    ; 3
    db 16                                   ; 4  up
    db 14                                   ; 5  up+left
    db 2                                    ; 6  up+right
    db 16                                   ; 7  up default
    db 8                                    ; 8  down
    db 10                                   ; 9  down+left
    db 6                                    ; 10 down+right
    db 8                                    ; 11
    db 0                                    ; 12
    db 12                                   ; 13
    db 4                                    ; 14
    db 0                                    ; 15

; Signed velocity pairs (dx, dy) — arcade M.TAB
m_tab:
    db  0,  0                               ; +0  none
    db  1, -1                               ; +2  up-right
    db  1,  0                               ; +4  right
    db  1,  1                               ; +6  down-right
    db  0,  1                               ; +8  down
    db -1,  1                               ; +10 down-left
    db -1,  0                               ; +12 left
    db -1, -1                               ; +14 up-left
    db  0, -1                               ; +16 up

; Initial door bitmask (arcade $268C) — 15 bytes
door_template:
    db $05,$04,$04,$04,$06,$01,$00,$00,$00,$02,$09,$08,$08,$08,$0A

; Robot spawn base positions (X,Y) — derived from arcade $23A2
robot_spawns:
    db $0C,$0C, $40,$0C, $A0,$0C, $CE,$0C
    db $40,$50, $70,$50, $9E,$50
    db $0C,$96, $40,$96, $A0,$96, $CE,$96
NUM_SPAWNS      EQU 11

; Wall brick sprite: 1×4, solid nibbles
spr_brick:
    db 1, 4
    db $F0,$F0,$F0,$F0
