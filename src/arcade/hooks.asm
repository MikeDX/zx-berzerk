; Arcade ↔ Spectrum I/O hook implementations.
; Veneer JP table lives in host.asm at ZX_HAL.
;
; 1:1 remapped arcade code; HAL replaces hardware only (video/magic/input).
; Shadow / RTOAX keep arcade Y=0 at top. Clip Y to 192 (arcade has 223).

hook_clear_screen:
    push    af
    push    bc
    push    de
    push    hl
    call    zx_cls
    ld      hl,ZX_VIDEO
    ld      de,ZX_VIDEO+1
    ld      bc,$1C00-1              ; 224 lines
    ld      (hl),0
    ldir
    ld      hl,ZX_MAGIC
    ld      de,ZX_MAGIC+1
    ld      bc,$1800-1              ; 192 lines
    ld      (hl),0
    ldir
    xor     a
    ld      (magic_collide),a
    pop     hl
    pop     de
    pop     bc
    pop     af
    ret

; HL = (X=L, Y=H) → magic address. Same contract as CALCULATE @ $29A3.
hook_rtoax:
    push    bc
    ld      a,l
    ld      (rtoax_x),a
    ld      a,h
    cp      192
    jr      c,.yok
    ld      a,191
.yok:
    ld      (rtoax_y),a
    ld      l,a
    ld      h,0
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,(rtoax_x)
    rrca
    rrca
    rrca
    and     31
    ld      c,a
    ld      b,0
    add     hl,bc
    ld      bc,ZX_MAGIC
    add     hl,bc
    pop     bc
    ld      a,(rtoax_x)
    and     7
    ld      (magic_shift),a
    or      b                       ; arcade: (X&7) | control
    ; OUT ($4B) / magicram_control_w raises the intercept flip-flop.
    ; Maze bricks that share a pixel must not kill the first sprite.
    push    af
    xor     a
    ld      (magic_collide),a
    pop     af
    ret

hook_draw_sprite:
    ; Magic + $4000. IRQ SP=$A040 is tiny; use the private blit stack.
    ; IRQ uses SP=$A040 (~64 bytes); a 16-row sprite overflows that into PROM.
    push    af
    ld      a,i
    di
    push    af
    ld      (blit_save_sp),sp
    ld      sp,blit_stack
    push    bc
    push    de
    push    hl
    push    ix
    push    hl
    pop     ix
    call    magic_dest_xy
    ld      a,(magic_shift)
    add     a,b                     ; byte column * 8 + (X&7)
    ld      (draw_x),a
    ld      a,c
    ld      (draw_y),a
    push    ix
    pop     hl
    ld      a,(draw_x)
    ld      b,a
    ld      a,(draw_y)
    ld      c,a
    call    magic_xor_sprite            ; Magic + Spectrum $4000
    pop     ix
    pop     hl
    pop     de
    pop     bc
    ld      sp,(blit_save_sp)
    pop     af
    jp      po,.noid
    ei
.noid:
    pop     af
    ret

magic_dest_xy:
    push    de
    pop     hl
    ld      a,h
    cp      ZX_VIDEO >> 8
    jr      c,.video                    ; below video → treat as video
    cp      ZX_MAGIC >> 8
    jr      c,.video                    ; $A8..$C3
    cp      ZX_MAGIC_SCRATCH >> 8
    jr      c,.magic                    ; $C4..$DB
    ld      bc,ZX_MAGIC_SCRATCH         ; $DC..
    jr      .sub
.magic:
    ld      bc,ZX_MAGIC
    jr      .sub
.video:
    ld      bc,ZX_VIDEO
.sub:
    or      a
    sbc     hl,bc
    ld      a,l
    and     31
    add     a,a
    add     a,a
    add     a,a
    ld      b,a
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    srl     h
    rr      l
    ld      c,l
    ret

hook_in_p1:
    push    bc
    push    de
    push    hl
    call    input_poll
    xor     $1F
    pop     hl
    pop     de
    pop     bc
    ret

hook_in_status:
    ; Preserve HL — IRQ samples $4E before saving HL.
    ; Do not present here: a 6K XOR blit is several Spectrum frames and
    ; DRAW already XORs onto $4000. Only the IRQ prologue (SP still near
    ; $A040) advances the fake vblank bit; collision INs must not.
    push    hl
    push    bc
    ld      c,0
    ld      a,(magic_collide)
    or      a
    jr      z,.nocoll
    ld      c,%10000000             ; latch stays until next OUT ($4B)
.nocoll:
    ld      hl,0
    add     hl,sp
    ld      a,h
    cp      ZX_SCRATCH_CMOS >> 8    ; IRQ SP page $A0
    jr      nz,.novb
    ld      a,l
    cp      $30                     ; prologue, not BOTTOM / DRAW
    jr      c,.novb
    ld      a,(vblank_div)
    inc     a
    ld      (vblank_div),a
    and     1
    ld      a,c
    jr      nz,.out
    or      %00000001
    jr      .out
.novb:
    ld      a,c
.out:
    pop     bc
    pop     hl
    ret

hook_out_magic:
    push    af
    and     7
    ld      (magic_shift),a
    xor     a
    ld      (magic_collide),a
    pop     af
    ret

hook_nmi:
    ret

; Room loop $2157: arcade `bit 2,(MAN_PTR); ret z` with a NULL pointer reads
; address 0. On the Spectrum that is ROM ($F3, MOVE bit clear) so we RET out
; of the room, $22F1 wipes vectors, and only the maze walls remain.
; With no player yet, tick jobs at $21A3 (delay bit + dispatcher) until
; MAN_INIT sets MAN_PTR. Jumping at $21C9 skipped that and starved spawn.
hook_game_loop:
    ld      ix,(ZX_SCRATCH_CMOS + ($0876 - $0800))
    push    ix
    pop     hl
    ld      a,h
    or      l
    jp      z,ARC_ROOM_JOBS
    bit     2,(ix+$00)
    ret     z
    jp      ARC_ROOM_MOVE

; SYSTEM $49 — active-low. Idle $FF.
; Keys: 0 or ENTER = COIN1, 1 = START1, 2 = START2.
hook_in_system:
    push    bc
    ld      a,$FF
    ld      bc,$EFFE                    ; row with 0
    in      c,(c)
    bit     0,c
    jr      nz,.noc0
    res     7,a                         ; COIN1
.noc0:
    ld      bc,$BFFE                    ; ENTER
    in      c,(c)
    bit     0,c
    jr      nz,.nocoin
    res     7,a
.nocoin:
    ld      bc,$F7FE                    ; 1..5
    in      c,(c)
    bit     0,c
    jr      nz,.nos1
    res     0,a                         ; START1
.nos1:
    bit     1,c
    jr      nz,.nos2
    res     1,a                         ; START2
.nos2:
    pop     bc
    ret

hook_in_safe:
    ld      a,$FF
    ret

; Spectrum ROM font → screen + magic (so frame_blit keeps HUD text).
hook_print_char:
    push    af
    push    bc
    push    de
    push    hl
    ld      a,c
    and     $7F
    cp      $1F
    jr      nz,.not_copy
    ld      a,'*'
    jr      .glyph
.not_copy:
    cp      32
    jr      c,.out
.glyph:
    push    af
    call    magic_dest_xy               ; B=x C=y pixels
    ld      a,b
    ld      (draw_x),a
    ld      a,c
    ld      (draw_y),a
    ld      a,b
    rrca
    rrca
    rrca
    and     31
    ld      b,a                         ; col
    ld      a,(draw_y)
    cp      192
    jr      c,.yok
    ld      a,191
.yok:
    rrca
    rrca
    rrca
    and     31
    cp      24
    jr      nc,.pop_out
    ld      c,a                         ; row
    pop     af
    push    af
    call    zx_print_char
    pop     af
    ld      b,a
    ld      a,(draw_x)
    ld      d,a
    ld      a,(draw_y)
    ld      e,a
    ld      a,b
    call    magic_print_char
    jr      .out
.pop_out:
    pop     af
.out:
    pop     hl
    pop     de
    pop     bc
    pop     af
    xor     a
    ret

; Arcade $1578: ld (hl),$80 after RTOAX, then IN $4E / rlca.
; Return carry set if that pixel hit existing Magic ink.
hook_bolt_pixel:
    push    bc
    push    de
    call    magic_xor_pixel80
    pop     de
    pop     bc
    ld      a,(magic_collide)
    rrca
    ret
