; Berzerk ZX Spectrum — build entry
;
; Assembles a 48K image: BASIC loader + CODE block at $8000,
; plus a .sna for fast emulator iteration.

    INCLUDE "tools/sjasm/BasicLib.asm"

    DEVICE ZXSPECTRUM48

; ---------------------------------------------------------------------------
; BASIC loader: CLEAR 32767 : LOAD "berzerk" CODE : RANDOMIZE USR 32768
; ---------------------------------------------------------------------------
    ORG 23755

basic:
    LINE : db clear,val,'"32767"'           : LEND
    LINE : db load,'"berzerk"',code         : LEND
    LINE : db rand,usr : NUM start          : LEND
basend:

; ---------------------------------------------------------------------------
; Machine code
; ---------------------------------------------------------------------------
    ORG $8000

start:
    di
    ld      sp,$FF58                        ; below BASIC UDGs / safe stack

    call    zx_cls
    call    demo_banner
    call    input_init

    ei
.main_loop:
    call    input_poll                      ; A = DURL|fire bits (arcade-style)
    call    demo_show_input
    halt                                    ; wait for interrupt (~50Hz)
    jr      .main_loop

; ---------------------------------------------------------------------------
    INCLUDE "src/zx/screen.asm"
    INCLUDE "src/zx/input.asm"
    INCLUDE "src/demo.asm"

code_end:

; ---------------------------------------------------------------------------
; Build artefacts (paths relative to cwd when sjasmplus runs)
; ---------------------------------------------------------------------------
    EMPTYTAP "build/berzerk.tap"
    SAVETAP  "build/berzerk.tap", BASIC, "berzerk", basic, basend - basic, 10
    SAVETAP  "build/berzerk.tap", CODE,  "berzerk", start, code_end - start

    SAVESNA  "build/berzerk.sna", start
