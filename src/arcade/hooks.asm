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
    ld      bc,$1800-1
    ld      (hl),0
    ldir
    ld      hl,ZX_MAGIC
    ld      de,ZX_MAGIC+1
    ld      bc,$1800-1
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
    ld      a,$90
    ret

hook_draw_sprite:
    push    af
    push    bc
    push    de
    push    hl
    push    ix
    push    hl
    pop     ix
    call    magic_dest_xy
    ld      a,b
    ld      (draw_x),a
    ld      a,c
    ld      (draw_y),a
    push    ix
    pop     hl
    ld      a,(draw_x)
    ld      b,a
    ld      a,(draw_y)
    ld      c,a
    call    xor_sprite
    push    ix
    pop     hl
    ld      a,(draw_x)
    ld      b,a
    ld      a,(draw_y)
    ld      c,a
    call    magic_xor_sprite
    pop     ix
    pop     hl
    pop     de
    pop     bc
    pop     af
    ret

magic_dest_xy:
    push    de
    pop     hl
    ld      a,h
    cp      ZX_MAGIC >> 8
    jr      nc,.magic
    cp      ZX_MAGIC_SCRATCH >> 8
    jr      c,.video
    ld      bc,ZX_MAGIC_SCRATCH
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
    ; frame_blit not called here yet (IM2 + long blit → $0038 in smoke).
    ; Shadows fill during demo; present path still TODO (job-shell exit).
    push    hl
    ld      hl,ZX_SCRATCH_CMOS + ($0876 - $0800)  ; MAN_PTR
    ld      a,(hl)
    inc     hl
    ld      h,(hl)
    ld      l,a
    ld      a,h
    cp      ZX_SCRATCH_CMOS >> 8
    jr      c,.idle
    cp      ZX_HAL >> 8
    jr      nc,.idle
    ld      a,(magic_collide)
    or      a
    jr      z,.vblank
    xor     a
    ld      (magic_collide),a
    ld      a,%10000001
    pop     hl
    ret
.vblank:
    ld      a,(vblank_div)
    inc     a
    ld      (vblank_div),a
    and     7
    ld      a,%00000001
    jr      z,.vblank_out
    xor     a
.vblank_out:
    pop     hl
    ret
.idle:
    ld      a,(magic_collide)
    or      a
    jr      z,.zero
    xor     a
    ld      (magic_collide),a
    ld      a,%10000000
    pop     hl
    ret
.zero:
    xor     a
    pop     hl
    ret

hook_nmi:
    ret

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

; Spectrum ROM font stand-in (arcade ordinal $1F = © → '*').
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
    call    magic_dest_xy
    ld      a,b
    rrca
    rrca
    rrca
    and     31
    ld      b,a
    ld      a,c
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
    ld      c,a
    pop     af
    call    zx_print_char
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
