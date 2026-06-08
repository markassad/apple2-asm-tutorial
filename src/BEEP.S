*--------------------------------------
* BEEP.S
*
* Tutorial stage 8.  An interactive
* sound demo.  Press 1-8 to play notes
* of a C-major scale, ESC to quit.
*
* The Apple II speaker has no D-to-A
* converter.  Reading address $C030
* toggles a single bit driving the
* speaker cone; the periodicity of your
* reads is the audio frequency.
*
* Build: make PROGRAM=BEEP run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   BEEP

HOME        EQU   $FC58
BASCALC     EQU   $FBC1
BASL        EQU   $28

PITCH       EQU   $E0          ;loop count: bigger = lower frequency
DUR         EQU   $E1          ;number of half-cycles to play

SPEAKER     EQU   $C030
KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME

* Title on row 1, centered
            LDA   #1
            JSR   BASCALC
            LDY   #14
            LDX   #0
:TL         LDA   TITLE,X
            BEQ   :TD
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :TL
:TD

* Hint on row 3, centered
            LDA   #3
            JSR   BASCALC
            LDY   #4
            LDX   #0
:HL         LDA   HINT,X
            BEQ   :HD
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :HL
:HD

*--------------------------------------
* Wait for a key, dispatch.
*--------------------------------------
:LOOP       LDA   KBD
            BPL   :LOOP
            STA   KBDSTRB
            AND   #$7F
            CMP   #$1B          ;ESC?
            BEQ   :QUIT
            CMP   #'1'
            BCC   :LOOP
            CMP   #'8'+1
            BCS   :LOOP
            SEC
            SBC   #'1'          ;index 0..7
            TAX
            LDA   PITCHES,X
            STA   PITCH
            LDA   #80
            STA   DUR
            JSR   TONE
            JMP   :LOOP

:QUIT       JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* TONE -- emit a square-wave tone.
*
* For DUR half-cycles, toggle the
* speaker bit at SPEAKER and wait PITCH
* iterations of a 5-cycle inner loop.
* Resulting frequency is roughly:
*   f = 1023000 / (2 * (5*PITCH + 15))
*--------------------------------------
TONE
:CYC        LDA   SPEAKER       ;click
            LDX   PITCH
:WP         DEX
            BNE   :WP
            DEC   DUR
            BNE   :CYC
            RTS

TITLE       ASC   "SPEAKER DEMO"
            DFB   $00
HINT        ASC   "PRESS 1-8 FOR NOTES, ESC TO QUIT"
            DFB   $00

* PITCH values for an approximate C-major scale (lower PITCH =
* higher frequency).  These are tuned by ear; real Apple II tuning
* would compute these from desired Hz and the 1.023 MHz CPU clock.
PITCHES     DFB   200,178,159,150,134,119,106,100
