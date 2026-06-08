*--------------------------------------
* HIRES.S
*
* Tutorial stage 9.  Switches to hi-res
* page 2 and fills the whole 8 KB page
* with $7F (all 7 visible bits set), so
* the entire 280x192 screen turns white.
* Press any key to return to text and
* reboot.
*
* We drive the soft switches directly
* and walk memory by hand instead of
* calling the Applesoft ROM hi-res
* routines (HGR2 at $F3D8, HCOLOR,
* HPOSN, HLIN).  Those routines rely on
* internal state that BASIC.SYSTEM sets
* up; called from a bare SYS file they
* misbehave.  Doing it manually is also
* a more honest look at how the hi-res
* page actually works.
*
* Build: make PROGRAM=HIRES run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   HIRES

* Soft switches.  Reading these has side effects; the byte you
* get back is irrelevant.
TXTOFF      EQU   $C050        ;graphics on (TEXT off)
TXTON       EQU   $C051
MIXOFF      EQU   $C052        ;full screen (MIXED off)
PAGE2       EQU   $C055        ;display page 2
HIRESON     EQU   $C057        ;hi-res (HIRES on)

* Zero-page pointer used to walk the 8 KB page.
PTR         EQU   $20

HOME        EQU   $FC58
KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START
* Switch to hi-res, page 2, full-screen graphics.
            LDA   TXTOFF
            LDA   MIXOFF
            LDA   PAGE2
            LDA   HIRESON

* Fill all 8 KB of hi-res page 2 ($4000-$5FFF) with $7F.
*
* $7F = 0111 1111.  Bits 0-6 set means all 7 pixels in the byte are
* "on."  Bit 7 (the color phase bit) is clear.  Wall-to-wall $7F
* gives a uniformly white screen (with some green/violet edge
* fringing on a color CRT due to NTSC artifacting).
            LDA   #$00
            STA   PTR
            LDA   #$40
            STA   PTR+1
            LDX   #$20            ;32 pages = 8 KB
            LDY   #$00
            LDA   #$F3
:FILL       STA   (PTR),Y
            INY
            BNE   :FILL
            INC   PTR+1
            DEX
            BNE   :FILL

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            LDA   TXTON
            JSR   HOME
            JMP   DISKIIBOOT
