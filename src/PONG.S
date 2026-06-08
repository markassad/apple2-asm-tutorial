*--------------------------------------
* PONG.S
*
* Tutorial stage 12.  A single-paddle
* Pong-ish bouncing-ball game in lo-res
* mixed mode.  The 40x40 graphics area
* (top 20 text rows) is the playfield;
* the bottom 4 text rows show score and
* instructions.
*
* The player controls a 2-text-row tall
* paddle on the right edge with W/S
* (or arrow keys).  The ball bounces
* off the top, bottom, and left walls.
* If it reaches the right edge inside
* the paddle, it bounces back and the
* score goes up; if it misses, the ball
* resets to the centre and the score
* drops to zero.
*
* Press ESC to quit.
*
* Build: make PROGRAM=PONG run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   PONG

HOME        EQU   $FC58
BASCALC     EQU   $FBC1
BASL        EQU   $28

TXTOFF      EQU   $C050
TXTON       EQU   $C051
MIXON       EQU   $C053          ;mixed: graphics top, 4 text rows bottom
PAGE1       EQU   $C054
HIRESOFF    EQU   $C056

SPEAKER     EQU   $C030

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

* Game state in zero page
BX          EQU   $E0
BY          EQU   $E1
BVX         EQU   $E2          ;direction: $01 or $FF
BVY         EQU   $E3
PY          EQU   $E4          ;paddle top row
SCORE       EQU   $E5
OLD_BX      EQU   $E6
OLD_BY      EQU   $E7
TMP         EQU   $E8

MAX_X       EQU   39
MAX_Y       EQU   19           ;top 20 rows are playfield
PADDLE_X    EQU   39
PADDLE_LEN  EQU   2            ;text rows the paddle occupies
MAX_PY      EQU   18           ;MAX_Y - (PADDLE_LEN-1)

* IIe key codes, with the high bit set
K_W         EQU   $D7
K_S         EQU   $D3
K_UP        EQU   $8B
K_DOWN      EQU   $8A
K_ESC       EQU   $9B

* Lo-res colors: each byte is (color<<4)|color, so both stacked pixels
* in the same column share the color.
COLOR_BALL    EQU   $FF        ;white
COLOR_PADDLE  EQU   $EE        ;aqua

START       JSR   HOME

* Print "SCORE: 00" on row 20 (text area)
            LDA   #20
            JSR   BASCALC
            LDY   #2
            LDX   #0
:LL1        LDA   LBL1,X
            BEQ   :LL1D
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :LL1
:LL1D
* Print hint on row 22
            LDA   #22
            JSR   BASCALC
            LDY   #4
            LDX   #0
:LL2        LDA   LBL2,X
            BEQ   :LL2D
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :LL2
:LL2D
* Switch to lo-res mixed-mode
            LDA   TXTOFF
            LDA   MIXON
            LDA   PAGE1
            LDA   HIRESOFF

* Clear graphics area (text rows 0..19)
            LDA   #0
            STA   TMP
:CL_R       LDA   TMP
            JSR   BASCALC
            LDY   #0
            LDA   #0
:CL_C       STA   (BASL),Y
            INY
            CPY   #40
            BNE   :CL_C
            INC   TMP
            LDA   TMP
            CMP   #20
            BNE   :CL_R

* Init ball and paddle
            LDA   #10
            STA   BX
            STA   BY
            STA   OLD_BX
            STA   OLD_BY
            LDA   #1
            STA   BVX
            STA   BVY
            LDA   #9
            STA   PY
            LDA   #0
            STA   SCORE
            JSR   UPDATE_SCORE

*--------------------------------------
* Main loop
*--------------------------------------
:LOOP
* Non-blocking key poll
            LDA   KBD
            BPL   :NOK
            STA   KBDSTRB
            CMP   #K_ESC
            BNE   :NOTESC
            JMP   :QUIT             ;long-distance jump out of the loop
:NOTESC     CMP   #K_W
            BEQ   :KUP
            CMP   #K_UP
            BEQ   :KUP
            CMP   #K_S
            BEQ   :KDOWN
            CMP   #K_DOWN
            BEQ   :KDOWN
            JMP   :NOK
:KUP        LDA   PY
            BEQ   :NOK
            DEC   PY
            JMP   :NOK
:KDOWN      LDA   PY
            CMP   #MAX_PY
            BEQ   :NOK
            INC   PY
:NOK

* Erase old ball
            LDA   OLD_BY
            JSR   BASCALC
            LDY   OLD_BX
            LDA   #0
            STA   (BASL),Y

* Erase paddle column (col 39, rows 0..19)
            LDX   #0
:EPL        TXA
            JSR   BASCALC
            LDY   #PADDLE_X
            LDA   #0
            STA   (BASL),Y
            INX
            CPX   #20
            BNE   :EPL

*--------------------------------------
* Vertical: bounce if at edge, then move
*--------------------------------------
            LDA   BY
            BNE   :V_NB
            LDA   #1
            STA   BVY
:V_NB       LDA   BY
            CMP   #MAX_Y
            BNE   :V_NT
            LDA   #$FF
            STA   BVY
:V_NT       LDA   BY
            CLC
            ADC   BVY
            STA   BY

*--------------------------------------
* Horizontal: bounce at left edge,
* paddle/miss at right edge, then move.
*--------------------------------------
            LDA   BX
            BNE   :H_NL
            LDA   #1
            STA   BVX
:H_NL       LDA   BX
            CMP   #MAX_X
            BNE   :H_MOVE         ;not at right edge, just move
            LDA   BVX
            BMI   :H_MOVE          ;already moving left
* At right edge, moving right -- did the paddle catch the ball?
            LDA   BY
            CMP   PY
            BCC   :MISS
            SEC
            SBC   PY
            CMP   #PADDLE_LEN
            BCS   :MISS
* Hit!
            LDA   #$FF
            STA   BVX
            INC   SCORE
            JSR   UPDATE_SCORE
            JSR   BEEP
            JMP   :H_MOVE
:MISS       LDA   #10
            STA   BX
            STA   BY
            STA   OLD_BX
            STA   OLD_BY
            LDA   #1
            STA   BVX
            STA   BVY
            LDA   #0
            STA   SCORE
            JSR   UPDATE_SCORE
            JSR   BUZZ
            JMP   :DRAW

:H_MOVE     LDA   BX
            CLC
            ADC   BVX
            STA   BX

*--------------------------------------
* Draw paddle and ball
*--------------------------------------
:DRAW       LDA   PY
            JSR   BASCALC
            LDY   #PADDLE_X
            LDA   #COLOR_PADDLE
            STA   (BASL),Y
            LDA   PY
            CLC
            ADC   #1
            JSR   BASCALC
            LDY   #PADDLE_X
            LDA   #COLOR_PADDLE
            STA   (BASL),Y

            LDA   BY
            JSR   BASCALC
            LDY   BX
            LDA   #COLOR_BALL
            STA   (BASL),Y

            LDA   BX
            STA   OLD_BX
            LDA   BY
            STA   OLD_BY

            JSR   DELAY
            JMP   :LOOP

:QUIT       LDA   TXTON
            JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* UPDATE_SCORE -- write SCORE as two
* decimal digits at row 20 cols 9-10.
*--------------------------------------
UPDATE_SCORE
            LDA   #20
            JSR   BASCALC
            LDA   SCORE
            LDX   #0
:DV         CMP   #10
            BCC   :DVD
            SEC
            SBC   #10
            INX
            JMP   :DV
:DVD        STA   US_ONES
            TXA
            CLC
            ADC   #'0'
            ORA   #$80
            LDY   #9
            STA   (BASL),Y
            LDA   US_ONES
            CLC
            ADC   #'0'
            ORA   #$80
            INY
            STA   (BASL),Y
            RTS

US_ONES     DFB   $00

*--------------------------------------
* BEEP -- short high tone for hit
*--------------------------------------
BEEP        LDY   #$10
:BC         LDA   SPEAKER
            LDX   #$40
:BW         DEX
            BNE   :BW
            DEY
            BNE   :BC
            RTS

*--------------------------------------
* BUZZ -- longer low tone for miss
*--------------------------------------
BUZZ        LDY   #$30
:ZC         LDA   SPEAKER
            LDX   #$C0
:ZW         DEX
            BNE   :ZW
            DEY
            BNE   :ZC
            RTS

*--------------------------------------
* DELAY -- ~50 ms (about 16 fps)
*--------------------------------------
DELAY       LDY   #$28
:DO         LDX   #$FF
:DI         DEX
            BNE   :DI
            DEY
            BNE   :DO
            RTS

LBL1        ASC   "SCORE: 00"
            DFB   $00
LBL2        ASC   "PRESS W/S, ESC TO QUIT"
            DFB   $00
