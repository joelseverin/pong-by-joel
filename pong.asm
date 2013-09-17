; Pong by Joel - a pong game for SNES.
; Copyright (C) 2013 Joel Severin
; 
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
; 
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.
; 
; You should have received a copy of the GNU General Public License
; along with this program. If not, see <http://www.gnu.org/licenses/>.

.include "pong.inc"
.include "init.asm"

.define SCREEN_WIDTH $FF
.define SCREEN_HEIGHT $E0

.struct OAM_low_t
  xLow db
  y db
  originTile db
  properties db
.endst

.struct OAM_high_t
  data ds 32
.endst

; All these defines are pseudo recurisve structs. WLA-DX doesn't support instanceof inside .struct!
.define _sizeof_OAM_t.low _sizeof_OAM_low_t*128
.define _sizeof_OAM_t.high _sizeof_OAM_high_t
.struct OAM_t
  low ds  _sizeof_OAM_t.low
  high ds _sizeof_OAM_t.high
.endst

.struct player_t
  x db
  y db
  score dw
.endst

.struct ball_t
  x db
  y db
  velocityX db
  velocityY db
.endst

; The bounds of the area the ball bounces in.
.define BALL_LEFT_BOUNDS $10
.define BALL_RIGHT_BOUNDS SCREEN_WIDTH-$10
.define BALL_TOP_BOUNDS 40
.define BALL_BOTTOM_BOUNDS SCREEN_HEIGHT

; Some paddle configuration.
.define PADDLE_SPEED 2 ; The static speed of the paddle when moving.
.define PADDLE_HEIGHT 32

; Sprite configuration in OAM.
.define OAM_BALL_INDEX 0
.define OAM_LEFT_PADDLE_INDEX 1
.define OAM_RIGHT_PADDLE_INDEX 2

.define OAM_SCORE_LETTER_SPACING 4
.define OAM_SCORE_MARGIN_TOP 8
.define OAM_SCORE_LETTER_WIDTH 16

.define OAM_LEFT_PLAYER_SCORE_0_INDEX 4
.define OAM_LEFT_PLAYER_SCORE_0_X BALL_LEFT_BOUNDS + OAM_SCORE_LETTER_WIDTH + OAM_SCORE_LETTER_SPACING
.define OAM_LEFT_PLAYER_SCORE_0_Y OAM_SCORE_MARGIN_TOP

.define OAM_LEFT_PLAYER_SCORE_1_INDEX 5
.define OAM_LEFT_PLAYER_SCORE_1_X BALL_LEFT_BOUNDS
.define OAM_LEFT_PLAYER_SCORE_1_Y OAM_SCORE_MARGIN_TOP

.define OAM_RIGHT_PLAYER_SCORE_0_INDEX 6
.define OAM_RIGHT_PLAYER_SCORE_0_X BALL_RIGHT_BOUNDS - OAM_SCORE_LETTER_WIDTH
.define OAM_RIGHT_PLAYER_SCORE_0_Y OAM_SCORE_MARGIN_TOP

.define OAM_RIGHT_PLAYER_SCORE_1_INDEX 7
.define OAM_RIGHT_PLAYER_SCORE_1_X BALL_RIGHT_BOUNDS - 2*OAM_SCORE_LETTER_WIDTH - OAM_SCORE_LETTER_SPACING
.define OAM_RIGHT_PLAYER_SCORE_1_Y OAM_SCORE_MARGIN_TOP

.ramsection "Variables" bank 0 slot 1
  leftPlayer instanceof player_t
  rightPlayer instanceof player_t
  ball instanceof ball_t
.ends

.ramsection "OAM" bank 0 slot 1
  OAM instanceof OAM_t
.ends

.bank 0
.section "MainCode"
  CHARACTER_TABLE:
    ; This corresponds to the tile base indices each character (0, 1, 2, ..., 9) has.
    .db           $28, $2C
    .db $60, $64, $68, $6C
    .db $A0, $A4, $A8, $AC
  ; END CHARACTER_BASE_TABLE

  ; Gets called for every V-blank that occurs after initialization.
  ; pong.inc dependency: NMI Vector
  VBlank:
    ; Note that the P register is pushed on interrupt (and PB, PC too, obviously).
    ; A, X, Y, DB and DP is not pushed. We do that. We rely on well-written code for S (stack).
    rep #$30 ; Get us to a KNOWN state, both for us and the compiler!
    pha ; It is important we are in 16-bit A-mode, to push both bytes of A.
    phx ; (X, Y won't get saved if they were 8 bit before, anyway. Only A works like that.)
    phy
    phb ; DB
    phd ; DP

    ; Very handy debug hack: use the left paddle in order to see what tiles we have (32x32 window).
    ;sep #$20
    ;lda leftPlayer.y.w
    ;sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PADDLE_INDEX*_sizeof_OAM_low_t

    jsr reloadGraphics ; Make OAM reflect the current game state.
    jsr uploadOAM ; Re-upload OAM

    rep #$30 ; Get back to the A/X/Y = 16-bit state to pull them back the way they were pushed.
    pld
    plb
    ply
    plx
    pla
  rti

  ; Start program execution. Runs loop (see tick).
  ; pong.inc dependency: RESET Vector
  Start:
    Snes_Init

    sep #$20
    
    lda #$80 ; Force screen off (go into force-blank)
    sta $2100

    ; Setup graphics
    lda #$00 ; Mode 0 (4 BGs @ 2 bpp); BG 1,2,3,4 uses 8x8 tiles; (BG prio: 0 (only for Mode 1))
    sta $2105
    lda #%00010000 ; Enable sprites, disable BG 1,2,3,4.
    sta $212C ; $212C is main screen, $212D would be sub screen.

    jsr setupPalettes
    
    jsr setupTiles

    jsr setupOAM

    jsr resetGame

    lda #$0F ; Screen full on
    sta $2100

    lda #%10000001 ; Enable V-blank NMI and auto joypad read.
    sta $4200

    -:
    jsr tick
    wai
    jmp -
  ; END Start

  ; Uploads the palette data.
  ; A: INVALIDATED(LOW BYTE)
  setupPalettes:
    php
    
    ; We will just set color 1 of 0..15, of palette 128 of 0..127 (BG) + 128..255 (sprite) to white.
    ; Note that each color is 2 bytes (really, 15 bits), little endian: GGGRRRRR 0BBBBBGG
    ; This yields 512 bytes CGRAM. Set $2121 to the WORD address, then write to to $2122 twice.
    ; After TWO writes to $2122, the $2121 address advances by ONE. Little endian order: LOW HIGH b.
    sep #$20
    
    lda #$80
    sta $2121
    lda #$FF ; white low
    sta $2122
    lda #$7F ; white high
    sta $2122
    
    plp
  rts

  ; Configures tiles and uploads the tile data.
  ; A: INVALIDATED
  ; X: INVALIDATED
  setupTiles:
    ; tiles.bin are expected to conform to this:
    ; It contains a tile map with 16x16 tiles, each 8x8 in size. 4bpp = 16 colors.
    ; First row: blank
    ; Second row: first 8x8 column = ball, the rest blank
    ; Rows 2,4,5,6: columns 1,2,3,4 contains a paddle, the rest blank. Preferably, col 2-4 is blank.
    ; The color for transparent is 0, the color for white is 1 (so $FF $00 ... $00 $00 gives the
    ; bit planes to make a row white - note the 2bpp + 2bpp format of 8 bit planes each = 16 byte).
    
    php

    sep #$20
    rep #$10

    ; Upload tiles, using DMA.
    lda #%10000000 ; Increment on VRAM Data High Byte ($2119), not VRAM Data Low Byte ($2118).
    sta $2115
    stz $2116 ; Destination low byte: 0. Note: This is a WORD address (2 data bytes per address)!
    stz $2117 ; Destination high byte: 0
    lda #%00000001 ; DMA Word increment: write $2118 = addr, then $2119 = addr+1 (matches $2115).
    sta $4300
    lda #$18 ; VRAM write port is register $2118 (low byte) + $2119 (high byte).
    sta $4301
    ldx #tiles.data ; Source low+high byte
    stx $4302 ; Source gets into $4302 (low) and $4303 (high) - by a little endian write.
    lda #:tiles.data ; Put the source bank in aswell.
    sta $4304
    ldx #tiles.size ; Put tile size on $4305 (low) and $4306 (high) - by little endian write.
    stx $4305
    lda #%00000001 ; Transfer this channel (0)...
    sta $420B ; ...now!

    plp
  rts
    
  rts

  ; Sets up OAM.
  ; X, Y, A: INVALIDATED
  setupOAM:
    php
    
    rep #$30

    ; Initialize OAM with all sprites:
    ; * x0..7: 1 (setting 0 is reported to display them for some reason, even though x8 is set :S)
    ; * x8 = X: 1 (put well off-screen)
    ; * y, originTile, properties (name table, palette, prio, h-flip, v-flip, size-flag) = 0

    ; First clear the low table.
    ldx #$0000
    lda #$0001 ; Set x0..7 = $01, y = $00. Think about it: it is saved little endian: $01 $00.
    -: sta OAM.low.w, X
    inx
    inx
    stz OAM.low.w, X
    inx
    stz OAM.low.w, X
    inx
    cpx #_sizeof_OAM_t.low
    bne -

    ; Now clear the high table. Set %sXsXsXsX = %01010101 = $55.
    ldx #$0000
    lda #$5555
    -: sta OAM.high.w, X
    inx
    inx ; (High table is 128 sprites * 2 bits/sprite = 32 bytes => even size <=> can unroll loop.)
    cpx #_sizeof_OAM_t.high
    bne -

    sep #$20

    ; Set up sprite registers
    lda #%00100000 ; OAM sprite size 001 = 8x8 and 32x32; OAM (name) base and name is both 0 = none.
    sta $2101

    ; Enable ball sprite
    lda #$10 ; Ball is in row $1, column $0.
    sta OAM.low.w + OAM_low_t.originTile + OAM_BALL_INDEX*_sizeof_OAM_low_t

    ; Enable paddle sprites
    lda #$20 ; Paddle origins are in row $2, column $0
    sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PADDLE_INDEX*_sizeof_OAM_low_t ; left paddle
    sta OAM.low.w + OAM_low_t.originTile + OAM_RIGHT_PADDLE_INDEX*_sizeof_OAM_low_t ; right paddle

    ; Set X8 on ball and paddles to 0. Also, set size on both paddles to 1 (0 = 8x8, 1 = 32x32).
    ;lda #%00101001 ; NOTE: assumes sprite 4 (3, counting 0-based) is unused!
    ;     sXsXsXsX
    lda #%01101000 ; STRANGE BUG! You would expect %00101001, but that doesn't work. This does. :S
    sta OAM.high.w ; + 0

    ; Setup score tiles:
    ; Default char
    lda CHARACTER_TABLE.w+0 ; Char "0"
    sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t
    sta OAM.low.w + OAM_low_t.originTile + OAM_RIGHT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    sta OAM.low.w + OAM_low_t.originTile + OAM_RIGHT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t

    ; Place x
    lda #OAM_LEFT_PLAYER_SCORE_0_X
    sta OAM.low.w + OAM_low_t.xLow + OAM_LEFT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    lda #OAM_LEFT_PLAYER_SCORE_1_X
    sta OAM.low.w + OAM_low_t.xLow + OAM_LEFT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t
    lda #OAM_RIGHT_PLAYER_SCORE_0_X
    sta OAM.low.w + OAM_low_t.xLow + OAM_RIGHT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    lda #OAM_RIGHT_PLAYER_SCORE_1_X
    sta OAM.low.w + OAM_low_t.xLow + OAM_RIGHT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t

    ; Place y
    lda #OAM_LEFT_PLAYER_SCORE_0_Y
    sta OAM.low.w + OAM_low_t.y + OAM_LEFT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    lda #OAM_LEFT_PLAYER_SCORE_1_Y
    sta OAM.low.w + OAM_low_t.y + OAM_LEFT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t
    lda #OAM_RIGHT_PLAYER_SCORE_0_Y
    sta OAM.low.w + OAM_low_t.y + OAM_RIGHT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    lda #OAM_RIGHT_PLAYER_SCORE_1_Y
    sta OAM.low.w + OAM_low_t.y + OAM_RIGHT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t

    ; Set all X8 to 0. Set all sizes to 1 (0 = 8x8, 1 = 32x32).
    ;     sXsXsXsX
    lda #%10101010
    sta OAM.high.w+1

    plp
  rts

  ; Uploads the OAM, initialized by setupOAM, with DMA.
  ; A, X: INVALIDATED
  uploadOAM:
    php

    sep #$20
    rep #$10
    
    ; Set OAM address to 0, and OAM priority enable bit to 0 ($2102, $2103).
    ldx #$0000
    stx $2102

    stz $4300 ; Plain single 8-bit DMA from RAM to register.
    lda #$04 ; OAM write port is register $2104.
    sta $4301
    ldx #OAM ; Setup source.
    stx $4302 ; (Little endian word write: low byte, high hoes into $4303.)
    lda #:OAM ; (Source bank, 8 bit.)
    sta $4304
    ldx #_sizeof_OAM_t
    stx $4305 ; (Little endian word write: low byte, high hoes into $4306.)
    lda #%00000001 ; Transfer this channel (0)...
    sta $420B ; ...now!

    plp
  rts

  ; Fills some address block with data, like RAM.
  ; X: 16-bit Start address. INVALIDATED
  ; Y: 16-bit Number of bytes to fill. INVALIDATED
  ; A: 8-bit The byte to fill with.
  ; P: INVALIDATED(FLAGS)
  ;memFill:
  ;  - sta $0000, X
  ;  inx
  ;  dey
  ;  bne -
  ;rts

  ; Resets the game. The game will behave like it is has been reset the next tick.
  resetGame:
    php
    rep #$20
    pha

    lda #$0000 ; no stz for 16-bit :(
    sta leftPlayer.score.w
    sta rightPlayer.score.w

    jsr resetRound

    rep #$20 ; Really make sure it is 16-bit, just like when we pushed A...
    pla
    plp
  rts

  ; Resets the round (but preserves the current player score).
  resetRound:
    php
    rep #$20
    pha
    sep #$20

    ; Put paddles in their initial place
    lda #(SCREEN_HEIGHT - 32)/2 ; Center horizontal
    sta leftPlayer.y.w
    sta rightPlayer.y.w
    lda #BALL_LEFT_BOUNDS-8 ; Place left paddle. Subtract its visual width.
    sta leftPlayer.x.w
    lda #BALL_RIGHT_BOUNDS-8 ; Place right paddle. Subtract visual width here as well...
    sta rightPlayer.x.w

    ; Place ball in the middle.
    lda #((BALL_RIGHT_BOUNDS - BALL_LEFT_BOUNDS) - 8)/2
    sta ball.x.w
    lda #((BALL_BOTTOM_BOUNDS - BALL_TOP_BOUNDS) - 8)/2
    sta ball.y.w

    ; Set velocity vector to (2, -1)
    lda #$02
    sta ball.velocityX.w
    lda #$FF
    sta ball.velocityY.w

    rep #$20 ; make sure it is 16 bit when pulling it!
    pla
    plp
  rts

  ; Reloads the current controller data.
  ; A: INVALIDATED
  ; X: INVALIDATED
  ; Y: INVALIDATED
  reloadControllerData:
    php

    sep #$20
    rep #$10
    
    lda $4212 ; Load status register. Bit 0: 0 = invalid controller data, 1 = valid.
    and #%00000001
    bne +++ ; skip to end if invalid

    lda $4218 ; Check controller type, controler 1 (left player)
    and #$0F
    bne ++ ; Abort if controller is of invalid type (not standard joypad, which is 0000)
    ldx #leftPlayer.w
    ldy #$4218
    jsr _reloadControllerData_parse

    ++:
    lda $421A ; Check controller type, controler 2 (right player)
    and #$0F
    bne +++ ; Abort if controller is of invalid type (not standard joypad, which is 0000)
    ldx #rightPlayer.w
    ldy #$421A
    jsr _reloadControllerData_parse
    
    +++:
    plp
  rts

  ; Parses the controller data and updates
  ; A: INVALIDATED
  ; X: 16-bit: Player base address to update.
  ; Y: 16-bit: Controller base address, in which to load data from.
  _reloadControllerData_parse:
    php
    sep #$20
    
    lda $0001, Y ; Check up
    and #%00001000
    beq ++
    lda player_t.y.w, X ; Decrease position
    clc
    adc #-PADDLE_SPEED.b
    rep #$20 ; If we go past the ball area bounds, clamp it to the edge.
    and #$00FF
    cmp #BALL_TOP_BOUNDS.w ; Must do this in 16-bit, since we're dealing with a 2-compl. comparison.
    bpl + ; (Technically NOT catching 0, but storing the edge works anyway since it is equal.)
    lda #BALL_TOP_BOUNDS.w ; Clamp it to the edge.
    +:
    sep #$20 ; Cast it to 8-bit (losing any garbage)
    sta player_t.y.w, X

    ++:
    lda $0001, Y ; Check down
    and #%00000100
    beq ++
    lda player_t.y.w, X ; Increase position
    clc
    adc #PADDLE_SPEED.b
    rep #$20 ; If we go past the ball area bounds, clamp it to the edge.
    and #$00FF
    cmp #BALL_BOTTOM_BOUNDS.w - PADDLE_HEIGHT
    bmi + ; (Technically NOT catching 0, but storing the edge works anyway since it is equal.)
    lda #BALL_BOTTOM_BOUNDS.w - PADDLE_HEIGHT; Clamp it to the edge.
    +:
    sep #$20 ; Cast it to 8-bit (losing any garbage)
    sta player_t.y.w, X

    ++:
    +++:
    plp
  rts

  ; Reloads the graphics, based on the current game state.
  ; A: INVALIDATED
  reloadGraphics:
    php
    sep #$20
    
    ; Update the sprite positions
    lda ball.x.w ; Ball
    sta OAM.low.w + OAM_low_t.xLow + OAM_BALL_INDEX*_sizeof_OAM_low_t
    lda ball.y.w
    sta OAM.low.w + OAM_low_t.y + OAM_BALL_INDEX*_sizeof_OAM_low_t

    lda leftPlayer.x.w ; Left paddle
    sta OAM.low.w + OAM_low_t.xLow + OAM_LEFT_PADDLE_INDEX*_sizeof_OAM_low_t
    lda leftPlayer.y.w
    sta OAM.low.w + OAM_low_t.y + OAM_LEFT_PADDLE_INDEX*_sizeof_OAM_low_t
    

    lda rightPlayer.x.w ; Right paddle
    sta OAM.low.w + OAM_low_t.xLow + OAM_RIGHT_PADDLE_INDEX*_sizeof_OAM_low_t
    lda rightPlayer.y.w
    sta OAM.low.w + OAM_low_t.y + OAM_RIGHT_PADDLE_INDEX*_sizeof_OAM_low_t
    
    ; Refresh the score board
    jsr refreshScoreGraphics

    plp
  rts

  ; Tick gets called after v-blank every frame. Non-graphics stuff goes here.
  tick:
    php
    
    jsr reloadControllerData

    sep #$20
    rep #$10
    
    ; Move the ball according to its velocity, see if it collided... If it did, reverse the
    ; direction of the velocity vector for the given component(s): x, y, or both x and y.
    ; Otherwise, update the position.
    
    ; For x. Will set the X-reg: $0000 if no x collision, $0001 if left collision, if $0002 right.
    ldx #$0000
    lda ball.velocityX.w ; Load ball x velocity (8 bit signed), then convert to 16 bit signed
    rep #$20
    bmi +
    and #$00FF
    bra ++
    +: and #$00FF ; Sign extend
    ora #$FF00
    ++: pha ; (done) push 16 bit veclociy component
    sep #$20
    lda ball.x.w ; Load ball x (8 bit unsigned), then convert to 16 bit signed
    rep #$20
    and #$00FF
    clc ; Now, add the velocity vector to the position vector
    adc $01, S; (stack relative: note that S points to 1 byte ahead of the top of stack)
    cmp #BALL_LEFT_BOUNDS.w ; Is it out of bounds?
    bmi +
    cmp #(BALL_RIGHT_BOUNDS - 8).w ; (account for ball size)
    bpl ++
    sep #$20 ; Nope, in bounds. Convert back to 8 bit unsigned.
    sta ball.x.w ; Save new position.
    bra +++
    ; Out of bounds, check paddles...
    +: ; Left paddle hit
    ldx #$0001
    bra +
    ++: ; Right paddle hit
    ldx #$0002
    +: ; (continue left paddle hit)
    sep #$20 
    lda #$FF ; Invert the velocity component (2's-complement)
    eor ball.velocityX.w
    ina
    sta ball.velocityX.w
    +++: ply ; (done) Remove the velocity component from the stack. Note: Pulling affects the flags!

    ; For y. Also: Will check the X register for left/right hits in x, and fix score if miss in Y.
    lda ball.velocityY.w ; Load ball y velocity (8 bit signed), then convert to 16 bit signed
    rep #$20
    bmi +
    and #$00FF
    bra ++
    +: and #$00FF ; Sign extend
    ora #$FF00
    ++: pha ; push 16 bit velocity component
    sep #$20
    lda ball.y.w ; Load ball y (8 bit unsigned), then convert to 16 bit signed
    rep #$20
    and #$00FF
    clc ; Now, add the velocity vector to the position vector
    adc $01, S; (stack relative: note that S points to 1 byte ahead of the top of stack)
    jsr _tick_checkPaddleCollision ; Just a quick collision check, will set score etc. See *
    cmp #BALL_TOP_BOUNDS.w ; Is it out of bounds?
    bmi +
    cmp #(BALL_BOTTOM_BOUNDS - 8).w ; (account for ball size)
    bpl +
    sep #$20 ; Nope, in bounds. Convert back to 8 bit unsigned.
    sta ball.y.w ; Save new position.
    bra ++
    +: sep #$20 ; Out of bounds.
    lda #$FF ; Invert the velocity component (2's-complement)
    eor ball.velocityY.w
    ina
    sta ball.velocityY.w
    ++: ply ; (done) Remove the velocity component from the stack. Note: Pulling affects the flags!
    ; * = It is important that we have: 16-bit A with the new y-coordinate, 16-bit X with paddle
    ;     collision status ($0000 = none, $0001 = possibly left, $0002 = possible right).
    ;     The y-coordinate should really be the one in the x-collision moment, but having it a bit
    ;     "too far" is close enough for us.
    
    plp
  rts

  ; Checks if the paddle collides...
  ; A: 16-bit: the ball y-coordinate (in the x-collision moment). Please see notes above.
  ; X: 16-bit: x-coordinate collisiton status: $0000 = none, $0001 = left, $0002 = right.
  ; @todo: Break out collision status codes into constants...
  _tick_checkPaddleCollision:
    php
    pha ; Note: this is used below in stack-relative addressing.

    cpx #$0000
    beq +++
    cpx #$0002
    beq ++
    
    ; @todo: Convert to macros or something...

    ; Left
    sep #$20 ; Load unsigned 8-bit player Y, convert to 16-bit.
    lda leftPlayer.y.w
    rep #$20
    and #$00FF
    cmp $01, S ; Compare with the new ball Y
    bpl + ; (check above paddle)
    clc ; Need to add paddle height to check belowWe don't have to worry about its visual width here.
    adc #32.w ; @todo: break out to constant
    bmi + ; (check below paddle)
    bra +++ ; (all clear)
    +: ; Means we had a paddle miss
    inc rightPlayer.score.w ; Give the other player some points
    bra +++
    
    ++: ; Right
    sep #$20 ; Load unsigned 8-bit player Y, convert to 16-bit.
    lda rightPlayer.y.w
    rep #$20
    and #$00FF
    cmp $01, S ; Compare with the new ball Y
    bpl + ; (check above paddle)
    clc ; Need to add paddle height to check below
    adc #32.w ; @todo: break out to constant
    bmi + ; (check below paddle)
    bra +++ ; (all clear)
    +: ; Means we had a paddle miss
    inc leftPlayer.score.w ; Give the other player some points
    bra +++    

    +++:
    pla
    plp
  rts

  ; Refreshes the graphics of the score system.
  ; A: INVALIDATED
  ; X: INVALIDATED
  refreshScoreGraphics:
    php

    ; Hardware division, unsigned:
    ; $4204 (low), $4205 (high) 16-bit Dividend
    ; $4206 8-bit Divisor
    ; After writing the divisor, the result is available in these registers 16 clock cycles later:
    ; $4214 (low), $4215 (high) 16-bit Quotient
    ; $4216 (low), $4217 (high) 16-bit Remainder

    rep #$30 ; Divide left player score by 10.
    lda leftPlayer.score.w 
    sta $4204 ; +$4205, 16 bit little-endian write.
    sep #$20
    lda #10
    sta $4206
    .rept 8
    nop ; 2 clock cycles
    .endr
    ldx $4216 ; (X is 16-bit from above)
    lda CHARACTER_TABLE.w, X ; (A is still 8 bit)
    sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    ldx $4214 ; (X is 16-bit from above)
    cpx #9.w ; We only have two chars per player, so we have to stop there...
    bmi +
    lda CHARACTER_TABLE.w, X ; (A is still 8 bit)
    sta OAM.low.w + OAM_low_t.originTile + OAM_LEFT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t
    +:

    rep #$30 ; Divide right player score by 10.
    lda rightPlayer.score.w 
    sta $4204 ; +$4205, 16 bit little-endian write.
    sep #$20
    lda #10
    sta $4206
    .rept 8
    nop ; 2 clock cycles
    .endr
    ldx $4216 ; (X is 16-bit from above)
    lda CHARACTER_TABLE.w, X ; (A is still 8 bit)
    sta OAM.low.w + OAM_low_t.originTile + OAM_RIGHT_PLAYER_SCORE_0_INDEX*_sizeof_OAM_low_t
    ldx $4214 ; (X is 16-bit from above)
    cpx #9.w ; We only have two chars per player, so we have to stop there...
    bmi +
    lda CHARACTER_TABLE.w, X ; (A is still 8 bit)
    sta OAM.low.w + OAM_low_t.originTile + OAM_RIGHT_PLAYER_SCORE_1_INDEX*_sizeof_OAM_low_t
    +:    

    plp
  rts
.ends

.bank 1 slot 0
.org 0
.section "TileData"
  tiles.data:
  .incbin "tiles.bin" fsize tiles.size ; tiles.size = file_size(tiles.bin)
.ends