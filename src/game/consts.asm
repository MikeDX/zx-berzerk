; Shared constants and game RAM (placed after code via ORG in main, or absolute)

; DURL bits (arcade Berzerk)
LEFT            EQU %00000001
RIGHT           EQU %00000010
UP              EQU %00000100
DOWN            EQU %00001000
FIRE            EQU %00010000

; VECTOR status bits
ST_ERASE        EQU %00000001
ST_WRITE        EQU %00000010
ST_MOVE         EQU %00000100
ST_HIT          EQU %10000000

MAX_ROBOTS      EQU 11
MAX_PBOLTS      EQU 2
MAX_RBOLTS      EQU 4

; Playfield (Spectrum 256×192; arcade was 256×223)
WALL_TOP_Y      EQU 0
WALL_BOT_Y      EQU 184
WALL_LEFT_X     EQU 4
WALL_RIGHT_X    EQU 248
ROW1_Y          EQU 56                      ; arcade $38
ROW2_Y          EQU 136                     ; arcade $88
CELL_PITCH      EQU $30

; Exit thresholds (tuned for 192-line screen)
EXIT_LEFT       EQU $FC
EXIT_RIGHT      EQU $F0
EXIT_TOP        EQU 2
EXIT_BOTTOM     EQU 176

; Respawn after exit
ENTER_LEFT_X    EQU $E8
ENTER_RIGHT_X   EQU 8
ENTER_TOP_Y     EQU 168
ENTER_BOT_Y     EQU 8

; Entity kinds
KIND_EMPTY      EQU 0
KIND_PLAYER     EQU 1
KIND_ROBOT      EQU 2
KIND_OTTO       EQU 3

; VECTOR layout (14 bytes) — matches arcade
V_STATUS        EQU 0
V_PAD           EQU 1                       ; unused (was Magic)
V_OLDX          EQU 2
V_OLDY          EQU 3
V_FRAME         EQU 4                       ; anim frame index
V_KIND          EQU 5
V_VX            EQU 6
V_PX            EQU 7
V_VY            EQU 8
V_PY            EQU 9
V_SPR_L         EQU 10                      ; sprite ptr lo
V_SPR_H         EQU 11
V_TIME          EQU 12
V_TPRIME        EQU 13
VEC_SIZE        EQU 14

; BOLT layout (8 bytes)
B_DIR           EQU 0
B_LEN           EQU 1
B_X             EQU 2
B_Y             EQU 3
B_LAST          EQU 4
B_MAX           EQU 5
B_TX            EQU 6
B_TY            EQU 7
BOLT_SIZE       EQU 8
