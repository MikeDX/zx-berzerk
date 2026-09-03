; Maze templates and spawn bases. Direction/animation tables live in romdata.asm.

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
