# Stage 12 — A complete small game

**Source:** `src/PONG.S`
**Build:** `make PROGRAM=PONG run`

This is the capstone — every concept from stages 1-11 used in
service of one playable thing. `PONG.S` is a single-paddle bouncing
ball game in lo-res mixed mode. The ball bounces around the
40x40 playfield; you move the paddle on the right edge with W/S
or arrow keys; the ball bounces off your paddle and gives you a
point, or sails past and resets your score to zero. ESC quits.

If you've worked through stages 1-11 the source should read like
plain English. The interesting part of this stage is the
*structure* — how a working game holds together — not the
individual instructions.

## What you'll learn

- The shape of a working game's main loop
- How game state lives in zero page when there's nowhere else for
  it to live
- The "erase, update, draw" frame structure (revisited from stage 5)
- Mixed mode for "playfield on top, status on bottom"
- The trampoline pattern for far branches
- Sound effects on top of game events
- Why this game is exactly 477 bytes assembled

## The game state

Eight zero-page bytes hold everything:

```
BX         EQU $E0          ;ball X (0..39)
BY         EQU $E1          ;ball Y (0..19)
BVX        EQU $E2          ;ball X velocity ($01 right, $FF left)
BVY        EQU $E3          ;ball Y velocity
PY         EQU $E4          ;paddle top row (0..18)
SCORE      EQU $E5          ;0..99
OLD_BX     EQU $E6          ;ball X last frame (for erase)
OLD_BY     EQU $E7          ;ball Y last frame
```

That's it. No heap, no stack-allocated objects, no managed memory.
For a small game on a small machine, eight bytes is the whole
universe. (Stages 5 and 6 used similar but smaller state.)

This compactness is one of the joys of writing for the Apple II:
you can hold the entire game's state in your head.

## The shape of the main loop

Every game loop does the same things in the same order:

```
1. Read input
2. Erase what was drawn last frame
3. Update game state (bounce, collision, scoring)
4. Draw the new state
5. Save "what was just drawn" for next frame's erase
6. Wait one frame's worth (delay or VBL)
7. Repeat
```

`PONG.S`'s `:LOOP` is exactly that structure. The reading is
non-blocking (we don't `BPL :READ` — if no key is pending, we
skip the dispatch and move on). The game keeps running even when
the player isn't pressing anything; the paddle just doesn't move.

### Erase phase

```
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
```

The ball erase is one byte: write 0 at `(OLD_BX, OLD_BY)`. Cheap.

The paddle erase walks the entire right column and zeros 20
bytes. We could be cleverer (track `OLD_PY` and erase only the
2-row paddle area), but at 20 stores per frame the cost is
negligible and the code is simpler.

### Update phase: bounces

Vertical and horizontal updates have nearly-identical structure:
"if at the relevant edge, reverse direction; then add velocity to
position."

```
* Vertical
            LDA   BY
            BNE   :V_NB              ;BY != 0, not at top
            LDA   #1                  ;at top, force downward
            STA   BVY
:V_NB       LDA   BY
            CMP   #MAX_Y
            BNE   :V_NT              ;not at bottom
            LDA   #$FF                ;at bottom, force upward
            STA   BVY
:V_NT       LDA   BY
            CLC
            ADC   BVY
            STA   BY
```

Two edge tests, then one move. The "set direction explicitly to
+1 or -1" approach is bug-free; the alternative "negate the
direction byte" can drift if the ball overshoots by 2 in a single
frame.

The horizontal update is more interesting because the right edge
isn't a wall — it's the paddle:

```
            LDA   BX
            BNE   :H_NL
            LDA   #1
            STA   BVX
:H_NL       LDA   BX
            CMP   #MAX_X
            BNE   :H_MOVE             ;not at right edge
            LDA   BVX
            BMI   :H_MOVE              ;already going left
* At right edge, going right -- did the paddle catch the ball?
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
:MISS       ...                       ;reset everything
```

The paddle hit test is two compares:

- `CMP PY : BCC :MISS` — if `BY < PY`, the ball is above the
  paddle top, miss.
- After subtracting `PY`, the value is `BY - PY` (0, 1, 2, ...).
  `CMP #PADDLE_LEN : BCS :MISS` — if that distance >= 2, the
  ball is below the paddle bottom, miss.

Otherwise it's a hit: flip BVX, INC score, beep, continue.

### The trampoline branch

```
            CMP   #K_ESC
            BNE   :NOTESC
            JMP   :QUIT
:NOTESC     CMP   #K_W
```

The straightforward `BEQ :QUIT` doesn't fit — `:QUIT` is more
than 127 bytes away in the binary, beyond the 6502's signed-byte
branch range. The fix is "negate the test and `JMP` instead":

- Original: `BEQ :QUIT` (branch if equal)
- Trampoline: `BNE :NOTESC : JMP :QUIT` (skip the JMP if not
  equal, JMP otherwise)

Same semantics, no range limit. Costs 1 extra byte and one extra
instruction. Whenever you see `BNE :ahead : JMP :somewhere :ahead`
in 6502 code, that's a long branch in disguise.

Merlin32 doesn't auto-trampoline for you the way some assemblers
do, so you'll see the assembler complain and edit by hand. After
a while it becomes reflex.

## Mixed mode: playfield + status

Mixed mode (`$C053` instead of `$C052`) gives you 40 columns of
graphics on rows 0-19 and 40 columns of text on rows 20-23.
That's exactly what a game wants: gameplay area on top, score and
hints on the bottom.

The text rows in mixed mode are *the same memory* as the bottom
text-page rows. We write `"SCORE: 00"` and the hint *before*
flipping to mixed mode, so by the time the mode switch happens
the text is already there. The graphics area we clear afterwards
because it's the gameplay zone.

You can write to text rows after flipping to mixed mode too — the
video circuitry doesn't care when you wrote; it just reads each
byte at scanout time and decides how to display it based on which
*row* it is.

## Sound effects

```
BEEP        LDY   #$10
:BC         LDA   SPEAKER
            LDX   #$40
:BW         DEX
            BNE   :BW
            DEY
            BNE   :BC
            RTS

BUZZ        LDY   #$30
:ZC         LDA   SPEAKER
            LDX   #$C0
:ZW         DEX
            BNE   :ZW
            DEY
            BNE   :ZC
            RTS
```

Same `TONE` structure as stage 8: read `$C030` to click, loop X
cycles, repeat Y times. `BEEP` has a short inner loop (high
pitch) and short outer (short duration); `BUZZ` has a long inner
loop (low pitch) and longer outer (sustained).

The game calls `BEEP` after a paddle hit (player feedback for
"good!") and `BUZZ` after a miss (feedback for "bad"). On a 1MHz
machine these are fast enough that they don't visibly slow the
game.

## Why 477 bytes?

The whole game is half a kilobyte. For comparison:

- A single ProDOS block is 512 bytes.
- A modern PNG of one game screenshot is ~50,000 bytes.
- The smallest Hello World binary in modern C with the standard
  library statically linked is ~50,000 bytes.
- An idle Slack tab in a modern browser is several hundred
  megabytes.

Six-five-oh-two assembly forces you to think about every byte.
That constraint is one of the reasons people still write for the
Apple II forty years on — there's an honesty to the medium that
modern stacks have mostly lost.

You can probably golf this game down further. Stage 11's tricks
(lookup tables for `BASCALC`, SMC, unrolled inner loops) would
save another 50-100 bytes if applied. As a tutorial, readability
won.

## Exercises

1. **AI for a second paddle.** Add `LPY` for a left-edge paddle.
   The CPU tracks the ball: if the ball is above the paddle's
   center, `DEC LPY`; if below, `INC LPY`. Add collision check
   on left edge similar to right. Now you have proper Pong.
2. **Increase ball speed as score climbs.** Reduce `DELAY`'s
   `LDY #$28` as `SCORE` rises. At score 0, slow. At score 10,
   `LDY #$18`. At score 20, `LDY #$08`. The game gets harder over
   time.
3. **Power-up.** Drop a yellow block (color 13) at a random
   playfield position. When the ball touches it, +5 score and a
   distinctive 3-note jingle. The randomness can come from a
   pseudo-random byte updated each frame (frame counter modulo
   playfield size), or from sampling `$C000` low byte for
   keyboard-driven randomness.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## What you've built

By finishing stage 12, you've gone from "no idea what `ORG` does"
in stage 1 to "shipping a working game in 477 bytes" with a
hand-rolled keyboard polling loop, sound effects, mixed-mode
graphics, real-time score display, and bouncing physics.

The capabilities of the 6502 and the Apple II are roughly tapped
out here for *what you can do in 12 stages of 200 lines each*.
What's beyond: hi-res sprites with bit-blit, music with
delta-modulation samples, disk-paged levels with streaming
loaders, networking via slot 7 cards, multi-tasking under
ProDOS with interrupts. The mechanism for each is the same as
what you've learned — `LDA`, `STA`, branches, the soft switches
— just used more cleverly.

Welcome to retrocomputing.

## Cheat sheet — survival kit

| Domain | Key concept | Cheat |
|---|---|---|
| Boot | SYS auto-launch | First SYS file in directory order; rename your file with `.SYSTEM` |
| Display | Text screen | `BASCALC` + `(BASL),Y`, OR `#$80` |
| Display | Lo-res | Same memory; each byte = 2 stacked pixels, nibble each |
| Display | Hi-res | Page 2 from a SYS file; 7 pixels/byte, weird Y math |
| Input | Keyboard | Poll `$C000` bit 7, ack `$C010`, dispatch by `CMP` |
| Sound | Speaker | Toggle `$C030`, half-period = pitch, count = duration |
| Files | ProDOS MLI | `JSR $BF00 : DFB cmd : DA params` |
| Speed | Hot loops | Lookup table over formula; page-align tables |
| Memory | Stack | `$0100-$01FF`; `JSR` pushes 2, `RTS` pops 2 |
| Errors | Long branch | `BNE skip : JMP target : skip` |
| Exit | SYS file | `JMP $C600` to reboot, or chain to another SYS |
