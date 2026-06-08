# Stage 12 solutions

## 1. AI for a second paddle (real Pong)

Add ZP for the CPU paddle:

```
LPY         EQU   $E9
LPADDLE_X   EQU   0
LSCORE      EQU   $EA
OLD_LPY     EQU   $EB
```

At init: `LDA #9 : STA LPY`.

Each frame, before erasing the ball, move the AI paddle. Simple
"track the ball" logic:

```
* AI: if ball center is above paddle center, DEC; if below, INC.
* PADDLE_CENTER offset from LPY = 1 (half of 2-row paddle, integer)
            LDA   LPY
            CLC
            ADC   #1            ;A = paddle vertical center
            CMP   BY
            BEQ   :AI_DONE
            BCS   :AI_UP        ;paddle below ball, move up
            LDA   LPY
            CMP   #MAX_PY
            BEQ   :AI_DONE
            INC   LPY
            JMP   :AI_DONE
:AI_UP      LDA   LPY
            BEQ   :AI_DONE
            DEC   LPY
:AI_DONE
```

For collision at left edge, mirror the right-edge code:

```
            LDA   BX
            BNE   :H_NL
            LDA   BVX
            BPL   :L_NORMAL    ;already going right
* At left edge, going left -- check left paddle
            LDA   BY
            CMP   LPY
            BCC   :L_MISS
            SEC
            SBC   LPY
            CMP   #PADDLE_LEN
            BCS   :L_MISS
            LDA   #1
            STA   BVX
            INC   LSCORE
            JSR   UPDATE_LSCORE
            JSR   BEEP
            JMP   :L_NORMAL
:L_MISS     ; reset ball, no AI score
            LDA   #20
            STA   BX
            STA   BY
            LDA   #1
            STA   BVX
            STA   BVY
            INC   SCORE         ;player score++ when AI misses
            JSR   UPDATE_SCORE
            JSR   BUZZ
:L_NORMAL
```

Now the right edge ("MISS" in the original) becomes "AI scores":

```
:MISS       ; was: reset everything and zero player score
* New: AI scores, ball resets
            INC   LSCORE
            JSR   UPDATE_LSCORE
            LDA   #20
            STA   BX
            STA   BY
            LDA   #$FF
            STA   BVX
            LDA   #1
            STA   BVY
            JSR   BUZZ
            JMP   :DRAW
```

Display both scores. Add `UPDATE_LSCORE` analogous to
`UPDATE_SCORE` at a different column.

You also need to draw and erase the left paddle similar to the right.

This grows the game by ~80 bytes and turns it into real Pong. The
AI is "perfect tracking" which is unfun; for a real game, slow the
AI by only moving every other frame or by adding random hesitation.

## 2. Speed ramp

Replace the constant `LDY #$28` in `DELAY` with a computed value
based on `SCORE`.

The cheap version: precomputed table.

```
SPEED_TBL   DFB   $30,$28,$22,$1C,$18,$14,$10,$0C,$0A,$08
            DFB   $06,$05,$04,$04,$04,$04,$04,$04,$04,$04
            ;...20 entries, faster up to score 19, then capped

DELAY       LDA   SCORE
            CMP   #20
            BCC   :SOK
            LDA   #19
:SOK        TAX
            LDY   SPEED_TBL,X
:DO         LDX   #$FF
:DI         DEX
            BNE   :DI
            DEY
            BNE   :DO
            RTS
```

Or do it with arithmetic — start with `$30`, subtract `SCORE`
clamped to `$2C`. The table is more flexible for tuning by ear.

The game ramps from "leisurely bounce" at score 0 to "nearly
unhittable" by score 15. You'll likely tune the curve a few times
before it feels right.

## 3. Power-up

A "yellow square at random position" that bumps score by 5 when
hit. State:

```
PUP_X       EQU   $EC
PUP_Y       EQU   $ED
PUP_ACTIVE  EQU   $EE          ;$00 hidden, $80 visible
PRNG        EQU   $EF          ;simple pseudo-random byte
```

Each frame, if `PUP_ACTIVE` is $00, roll the dice (cheap
PRNG: `INC PRNG : LDA PRNG : EOR $C000` or similar). 1-in-256
chance to spawn a power-up at a random `(X, Y)`.

```
            LDA   PUP_ACTIVE
            BNE   :PUP_VISIBLE
            INC   PRNG
            LDA   PRNG
            CMP   #0            ;spawn each time PRNG wraps to 0
            BNE   :PUP_DONE
            ; Roll position
            LDA   FRAME         ;frame counter as poor-man's seed
            AND   #$1F          ;0..31
            STA   PUP_X
            LDA   FRAME
            LSR
            LSR
            LSR
            AND   #$0F          ;0..15
            STA   PUP_Y
            LDA   #$80
            STA   PUP_ACTIVE
:PUP_VISIBLE
* Draw power-up
            LDA   PUP_Y
            JSR   BASCALC
            LDY   PUP_X
            LDA   #$DD          ;yellow (color 13 both nibbles)
            STA   (BASL),Y
:PUP_DONE
```

After the ball update, check collision:

```
            LDA   PUP_ACTIVE
            BEQ   :PUP_NC
            LDA   BX
            CMP   PUP_X
            BNE   :PUP_NC
            LDA   BY
            CMP   PUP_Y
            BNE   :PUP_NC
* Collected!
            LDA   #0
            STA   PUP_ACTIVE
            CLC
            LDA   SCORE
            ADC   #5
            STA   SCORE
            JSR   UPDATE_SCORE
            JSR   JINGLE        ;new 3-note sound
:PUP_NC
```

The 3-note jingle:

```
JINGLE      LDA   #134          ;G note
            STA   PITCH
            LDA   #40
            STA   DUR
            JSR   TONE
            LDA   #119          ;A
            STA   PITCH
            LDA   #40
            STA   DUR
            JSR   TONE
            LDA   #100          ;C
            STA   PITCH
            LDA   #40
            STA   DUR
            JSR   TONE
            RTS
```

(Reusing `TONE` from `BEEP.S` patterns.)

For a real game, you'd want multiple power-up types (slower
ball, longer paddle, double-score-for-N-seconds) cycling through
colors. The mechanism is the same.
