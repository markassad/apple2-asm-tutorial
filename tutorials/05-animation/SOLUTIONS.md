# Stage 5 solutions

## 1. Trail with fade

**Removing `JSR ERASE`:** the message draws on top of the previous
position without clearing it. After a few frames the screen is a
field of `HELLO, APPLE IIE!` ghosts.

**The fade pass:** every N frames, scan all of `$0400-$07FF` and
turn every `H` (or any of the message chars) into a space. The
cheap version blanks anything that isn't `' ' + $80`:

```
FADE        LDA   #0
            STA   :ROW
:RL         LDA   :ROW
            JSR   BASCALC
            LDY   #0
:CL         LDA   (BASL),Y
            CMP   #$A0          ;already a space?
            BEQ   :NEXT
            CMP   #'*'+$80      ;border char, leave alone (if you have one)
            BEQ   :NEXT
            LDA   #$A0
            STA   (BASL),Y
:NEXT       INY
            CPY   #40
            BNE   :CL
            INC   :ROW
            LDA   :ROW
            CMP   #24
            BNE   :RL
            RTS
:ROW        DFB   0
```

Call `FADE` every 30 frames, say, by incrementing a counter and
checking it in the main loop. A cleaner version: instead of
nuking everything, walk the screen and replace each non-space char
with the next-paler one using a small character table. Apple II
text doesn't really have "pale" though — you'd cycle through space
→ '.' → ',' → ';' or similar visual hierarchy.

The classic-trail look is to leave the trail and not fade at all,
which makes the demo look like an etch-a-sketch with letters.

## 2. VBL timing

Drop in:

```
WAIT_VBL    LDA   $C019
            BPL   WAIT_VBL      ;poll until bit 7 sets (VBL active)
:WAIT_NOT   LDA   $C019
            BMI   :WAIT_NOT     ;poll until bit 7 clears (back to scan)
            RTS
```

Replace `JSR DELAY` with `JSR WAIT_VBL`. The bouncer now runs at
60 fps. If that's too fast, repeat:

```
            JSR   WAIT_VBL
            JSR   WAIT_VBL      ;30 fps
            JSR   WAIT_VBL      ;20 fps
```

VBL-locked timing is steady (no clock drift, no per-iteration
variance) and survives most interrupt scenarios. The downside is
that you must finish all your per-frame work *before* the next
VBL, or you skip frames silently.

## 3. Second bouncer

Add second-bouncer state:

```
COL2        EQU   $E5
ROW2        EQU   $E6
DCOL2       EQU   $E7
DROW2       EQU   $E8

* In START init:
            LDA   #20
            STA   COL2
            LDA   #10
            STA   ROW2
            LDA   #$FF        ;moving left
            STA   DCOL2
            LDA   #1
            STA   DROW2
```

Make `ERASE2`, `BOUNCE2`, `DRAW2` mirror the first set but using
the `2` zero-page locations. Or factor: parameterize `ERASE`,
`BOUNCE`, `DRAW` on the ZP locations they operate on — but that
needs a "pointer to ZP" pattern, which requires self-modifying code
or a higher-cost dispatch. For two bouncers, copy-paste is fine.

**About overlap:** when the two messages cross, they appear to
swap halves: bouncer A's left half plus bouncer B's right half
shows at the overlap. The reason is they take turns drawing on top
of each other.

To handle overlap "correctly" you'd need a back buffer (or a
single pass that decides per-character which sprite wins), which
is unnecessary complexity for two messages. Real Apple II games
with multiple sprites either composite into a hi-res back buffer or
accept the priority-by-draw-order behavior, which is what BOUNCE2
does.
