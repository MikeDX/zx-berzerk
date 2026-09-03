; Spectrum I/O hooks for the arcade host.
; These replace Magic RAM / ports. Wire from a relocated ROM or CALL patches.
; See docs/PORT.md.

; Placeholder: the hand-ported shell still owns gameplay.
; Next step: jump into HOOK_ATTRACT_LOOP / HOOK_START_GAME with
; DRAW_SPRITE / RTOAX / IN $48 intercepted.

arcade_hooks_ready:
    xor     a
    ret
