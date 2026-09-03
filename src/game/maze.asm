; Maze generation — arcade $2540 adapted to Spectrum bitmap

; Draw 12 bricks horizontally; advances B by 48
maze_hwall:
    ld      a,12
.hloop:
    push    af
    push    bc
    ld      hl,spr_brick
    call    or_sprite
    pop     bc
    ld      a,4
    add     a,b
    ld      b,a
    pop     af
    dec     a
    jr      nz,.hloop
    ret

; Draw 18 bricks vertically; advances C by 72
maze_vwall:
    ld      a,18
.vloop:
    ld      d,a
    ld      a,c
    cp      192
    ret     nc
    ld      a,d
    push    af
    push    bc
    ld      hl,spr_brick
    call    or_sprite
    pop     bc
    ld      a,4
    add     a,c
    ld      c,a
    pop     af
    dec     a
    jr      nz,.vloop
    ret

; Arcade $25D4 — two walls, gap $30, two walls (door in middle)
maze_hperim:
    call    maze_hwall
    call    maze_hwall
    ld      a,$30
    add     a,b
    ld      b,a
    call    maze_hwall
    jp      maze_hwall

; Arcade $25CA — two vertical stacks with $40 Y step between starts
maze_vperim:
    push    bc
    call    maze_vwall
    pop     bc
    ld      a,$40
    add     a,c
    ld      c,a
    jp      maze_vwall

; Interior junctions along a row (arcade $25EB)
maze_interior_row:
.junc:
    call    random
    push    bc
    and     3
    jr      z,.up
    dec     a
    jr      z,.down
    dec     a
    jr      z,.left
    call    maze_hwall
    set     3,(ix+1)
    set     2,(ix+6)
    jr      .next
.left:
    ld      a,b
    sub     $30
    ld      b,a
    call    maze_hwall
    set     3,(ix+0)
    set     2,(ix+5)
    jr      .next
.up:
    ld      a,c
    sub     $44
    jr      nc,.upy
    xor     a
.upy:
    ld      c,a
    call    maze_vwall
    set     1,(ix+0)
    set     0,(ix+1)
    jr      .next
.down:
    call    maze_vwall
    set     1,(ix+5)
    set     0,(ix+6)
.next:
    pop     bc
    inc     ix
    ld      a,$30
    add     a,b
    ld      b,a
    cp      $DC
    jr      c,.junc
    inc     ix
    ret

maze_build:
    ld      a,(room_x)
    ld      l,a
    ld      a,(room_y)
    ld      h,a
    ld      (rng_seed),hl

    ld      hl,door_template
    ld      de,door_bits
    ld      bc,15
    ldir

    ld      b,8
    ld      c,WALL_TOP_Y
    call    maze_hperim
    ld      b,8
    ld      c,WALL_BOT_Y
    call    maze_hperim
    ld      b,WALL_LEFT_X
    ld      c,0
    call    maze_vperim
    ld      b,WALL_RIGHT_X
    ld      c,0
    call    maze_vperim

    ld      ix,door_bits
    ld      b,$38
    ld      c,ROW1_Y
    call    maze_interior_row
    ld      b,$38
    ld      c,ROW2_Y
    call    maze_interior_row
    jp      mask_capture
