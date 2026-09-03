; Sprite pixel data (from arcade ROM patterns, width×height)

; Player standing (arcade $10BF)
spr_player:
    db 1, 16
    db $18,$18,$00,$3C,$5A,$5A,$5A,$18
    db $18,$18,$18,$18,$18,$18,$1C,$10

; Player walk frame (arcade $10AD)
spr_player_walk:
    db 1, 16
    db $18,$18,$00,$3C,$5C,$5C,$5A,$18
    db $18,$18,$18,$18,$18,$18,$1C,$10

; Robot idle (arcade $10D1)
spr_robot:
    db 1, 11
    db $3C,$66,$FF,$BD,$BD,$BD,$3C,$24,$24,$24,$66

; Robot moving (arcade $111F)
spr_robot_move:
    db 1, 11
    db $3C,$78,$FF,$BD,$BD,$BD,$3C,$18,$18,$18,$1C

; Otto smile (compact — arcade bounce mid-size)
spr_otto:
    db 1, 8
    db $3C,$7E,$DB,$FF,$FF,$BD,$42,$3C

; Tiny blast
spr_blast:
    db 1, 8
    db $00,$24,$18,$7E,$7E,$18,$24,$00
