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
ROW1_Y          EQU $44                     ; arcade interior row 1 ($4438)
ROW2_Y          EQU $88                     ; arcade interior row 2 ($8838)
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

; VECTOR layout. Offsets 0-13 match the arcade structure exactly, so the
; ported routines can be read side by side with the disassembly. The arcade
; erases a sprite via O.A (the magic RAM address it was drawn at) and O.P (the
; pattern it was drawn with); we keep the screen-space equivalents instead.
V_STATUS        EQU 0
V_KIND          EQU 1                       ; arcade Magic
V_OLDX          EQU 2                       ; arcade O.A: where it was drawn
V_OLDY          EQU 3
V_OSPR_L        EQU 4                       ; arcade O.P: what was drawn there
V_OSPR_H        EQU 5
V_VX            EQU 6
V_PX            EQU 7
V_VY            EQU 8
V_PY            EQU 9
V_DP_L          EQU 10                      ; arcade D.P: cursor in a pattern table
V_DP_H          EQU 11
V_TIME          EQU 12
V_TPRIME        EQU 13
; Spectrum-only additions
V_SPR_L         EQU 14                      ; sprite resolved from D.P this frame
V_SPR_H         EQU 15
V_DX            EQU 16                      ; draw offset from the sprite's $80 prefix
V_DY            EQU 17
V_ODX           EQU 18                      ; the offsets the old sprite was drawn with
V_ODY           EQU 19
V_TAB_L         EQU 20                      ; pattern table currently playing
V_TAB_H         EQU 21
V_LAST          EQU 22                      ; last DURL that selected a pattern
VEC_SIZE        EQU 23

; Pattern tables, as arcade ROM addresses (see src/game/romdata.asm)
PAT_ROBOT_STILL EQU $1000
PAT_EXPLOSION   EQU $103B
PAT_PLAYER_DIE  EQU $12B3
PAT_OTTO        EQU $120B

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
