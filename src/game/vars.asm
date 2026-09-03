; Game variables — assembled into the CODE block (initialized at load)

game_vars:

room_x:         db 0
room_y:         db 0
man_x:          db $1E
man_y:          db $64
deaths:         db 3
spawn_thresh:   db $60
rbolts_max:     db 0
robot_speed:    db 5
rwait:          db $5A
otto_timer:     db 0
rcount:         db 0
rsaved:         db 0
score:          db 0,0,0                    ; BCD
rng_seed:       dw 0
player_dir:     db DOWN
player_firing:  db 0
otto_active:    db 0
frame_tick:     db 0
hud_dirty:      db 1

door_bits:      ds 15

player_vec:     ds VEC_SIZE
robot_vecs:     ds VEC_SIZE * MAX_ROBOTS
otto_vec:       ds VEC_SIZE
player_bolts:   ds BOLT_SIZE * MAX_PBOLTS
robot_bolts:    ds BOLT_SIZE * MAX_RBOLTS

draw_collide:   db 0
spr_shift:      db 0
spr_hleft:      db 0
spr_xbyte:      db 0

game_vars_end:
