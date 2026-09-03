; Berzerk ZX Spectrum — build entry

    INCLUDE "tools/sjasm/BasicLib.asm"
    INCLUDE "src/game/consts.asm"

    DEVICE ZXSPECTRUM48

; BASIC loader
    ORG 23755

basic:
    LINE : db clear,val,'"32767"'           : LEND
    LINE : db load,'"berzerk"',code         : LEND
    LINE : db rand,usr : NUM start          : LEND
basend:

; Machine code
    ORG $8000

start:
    di
    ld      sp,$FF58
    call    game_init
    ei
.main:
    halt
    call    game_frame
    jr      .main

; ---------------------------------------------------------------------------
    INCLUDE "src/zx/screen.asm"
    INCLUDE "src/zx/input.asm"
    INCLUDE "src/game/draw.asm"
    INCLUDE "src/game/util.asm"
    INCLUDE "src/game/tables.asm"
    INCLUDE "src/game/sprites.asm"
    INCLUDE "src/game/entity.asm"
    INCLUDE "src/game/maze.asm"
    INCLUDE "src/game/bolts.asm"
    INCLUDE "src/game/player.asm"
    INCLUDE "src/game/robots.asm"
    INCLUDE "src/game/otto.asm"
    INCLUDE "src/game/hud.asm"
    INCLUDE "src/game/game.asm"
    INCLUDE "src/game/vars.asm"

code_end:

    EMPTYTAP "build/berzerk.tap"
    SAVETAP  "build/berzerk.tap", BASIC, "berzerk", basic, basend - basic, 10
    SAVETAP  "build/berzerk.tap", CODE,  "berzerk", start, code_end - start
    SAVESNA  "build/berzerk.sna", start
