*--------------------------------------
* SHAPES.S
*
* Tutorial stage 7.  Switches to lo-res
* graphics, fills the screen with the
* 16-color palette as vertical strips,
* and waits for a key to return to text.
*
* Build: make PROGRAM=SHAPES run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   SHAPES

HOME        EQU   $FC58
BASCALC     EQU   $FBC1

BASL        EQU   $28
ROW         EQU   $E0

* Soft switches
TXTOFF      EQU   $C050        ;graphics on (TEXT off)
TXTON       EQU   $C051
MIXOFF      EQU   $C052        ;full-screen (MIXED off)
PAGE1       EQU   $C054        ;page 1 (PAGE2 off)
HIRESOFF    EQU   $C056        ;lo-res (HIRES off)

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME
* Enter lo-res, full-screen, page 1.  All four soft switches are
* read-only side-effect addresses; the LDA value is irrelevant.
            LDA   TXTOFF
            LDA   MIXOFF
            LDA   PAGE1
            LDA   HIRESOFF

* Clear the graphics page (40 cols x 24 byte rows of black).
            LDA   #0
            STA   ROW
:CRL        LDA   ROW
            JSR   BASCALC
            LDA   #0
            LDY   #0
:CCL        STA   (BASL),Y
            INY
            CPY   #40
            BNE   :CCL
            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :CRL

* Paint 16 vertical color strips (2 cols per color, cols 0..31).
* Cols 32-39 stay black.
            LDA   #0
            STA   ROW
:PRL        LDA   ROW
            JSR   BASCALC
            LDY   #0
            LDX   #0
:PCL        LDA   PALETTE,X
            STA   (BASL),Y
            INY
            STA   (BASL),Y       ;same color, next column
            INY
            INX
            CPX   #16
            BNE   :PCL
            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :PRL

* Wait for a key, return to text, reboot.
:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            LDA   TXTON
            JSR   HOME
            JMP   DISKIIBOOT

* Each palette byte has the color in both nibbles, so the top
* half-pixel and the bottom half-pixel of every byte we write are
* the same color.  Colors 0..15 are:
*   0 black     4 dark green   8 brown    12 green
*   1 magenta   5 grey-1       9 orange   13 yellow
*   2 dark blue 6 medium blue 10 grey-2   14 aqua
*   3 purple    7 light blue  11 pink     15 white
PALETTE     DFB   $00,$11,$22,$33,$44,$55,$66,$77
            DFB   $88,$99,$AA,$BB,$CC,$DD,$EE,$FF
