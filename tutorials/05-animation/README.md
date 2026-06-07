# Stage 5 — Animation and timing

**Source:** `src/BOUNCE.S` (already in the workspace)
**Build:** `make PROGRAM=BOUNCE run`

Animation on a 1 MHz machine with no GPU and no interrupt-driven
frame timer comes down to three things: a tight main loop, a way
to erase the old frame before drawing the new one, and a delay so
the user sees individual frames instead of a blur. `BOUNCE.S` does
all three in 219 bytes.

## What you'll learn

- The "erase, move, draw, delay, check key" frame-loop pattern
- Why erase-before-move (not after-draw) avoids flicker
- Two ways to flip a signed direction byte
- A self-contained delay loop and how to tune it
- Polling the vertical blank as a more accurate alternative

## The frame loop

```
LOOP        JSR   ERASE
            JSR   BOUNCE
            JSR   DRAW
            JSR   DELAY
            LDA   KBD
            BPL   LOOP
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT
```

Four subroutines (more material for stage 4!) plus a keyboard poll.
The structure is:

1. **`ERASE`** writes spaces at the *current* `(COL, ROW)` —
   wherever the last `DRAW` left the message. On the very first
   frame this clobbers blank screen with blanks (no-op visually).
2. **`BOUNCE`** updates `COL` and `ROW` by `DCOL` and `DROW`,
   flipping a direction byte if the new position would go past an
   edge.
3. **`DRAW`** writes the message at the *new* `(COL, ROW)`.
4. **`DELAY`** burns ~60 ms so the eye sees this frame.
5. **`LDA KBD`** checks for input. `BPL LOOP` means "if bit 7 is
   clear (no key pending), repeat the loop." On a key, fall
   through, clear the strobe, clear the screen, reboot.

## Why erase first, not "draw new, then erase old"

The alternative is to remember the *previous* `(COL, ROW)` and
after drawing the new frame, erase the previous one. That works,
but the visible state for one frame is "message at new position
plus residue at old position." On a slow-clocked display you can
sometimes see the trail.

The "erase current, move, draw" pattern means: at all times when
the display is being scanned, *one* copy of the message exists.
The fact that the very first frame erases an empty region is fine
— it's invisible.

(For more advanced animations — sprites, parallax, etc. — you'd
allocate a back buffer, render into it, and swap pages with the
soft switches. The Apple II has two text pages, two lo-res pages,
two hi-res pages — three sets of two — so page flipping is a real
option. That's stage 11+ territory.)

## The bounce arithmetic

```
BOUNCE      LDA   COL
            CLC
            ADC   DCOL
            TAX
            CPX   #MAXCOL+1
            BCS   :HFLIP
            STX   COL
            JMP   :HDONE
:HFLIP      LDA   #0
            SEC
            SBC   DCOL
            STA   DCOL
            LDA   COL
            CLC
            ADC   DCOL
            STA   COL
```

`DCOL` is `+1` or `-1` stored as `$01` or `$FF`. The candidate new
column is `COL + DCOL`, parked in X. The single test `CPX
#MAXCOL+1 : BCS :HFLIP` catches both edges:

- If the move would put X past `MAXCOL`, X is now > `MAXCOL` so
  carry is set.
- If the move would put X *below* 0 (`COL=0`, `DCOL=$FF`), the add
  wraps and X becomes `$FF`. `$FF >= MAXCOL+1` so carry is also
  set.

Either way, `:HFLIP` runs: negate `DCOL` (`0 - DCOL`), apply the
new direction, store the result. The flip-and-step pattern means
"bounce" without ever rendering off-screen.

The row version adds `CPX #MINROW : BCC :VFLIP` because rows start
at 2 (we want a clear row 0 for the title bar) — Y has both a top
and a bottom bound.

## The delay loop

```
DELAY       LDY   #$30
:DOUTER     LDX   #$FF
:DINNER     DEX
            BNE   :DINNER
            DEY
            BNE   :DOUTER
            RTS
```

Inner loop: `DEX : BNE` is 5 cycles per iteration. 256 iterations
× 5 = 1280 cycles ≈ 1.28 ms (the 6502 in the Apple IIe runs at
1.023 MHz).

Outer loop: 48 (`$30`) iterations × 1.28 ms ≈ 61 ms. So the
animation runs at about 16 fps.

To make it faster, lower `LDY #$30`. To make it slower, raise it.

But delay loops are fragile: if you ever take an interrupt mid-loop
(rare on Apple II during normal SYS-file execution, but possible),
the timing shifts. They're also unaware of the actual display
refresh — your animation can update mid-scanout and produce a
tearing artifact.

## The vertical blank

The Apple IIe exposes the vertical blank state at soft switch
`$C019`. Reading the byte and inspecting bit 7 tells you "are we
currently in vertical blank?" — i.e., is the video circuit between
finishing the last scanline of one frame and starting the next?

A more accurate animation loop polls VBL to lock to the display
refresh:

```
WAIT_VBL    LDA   $C019
            BPL   WAIT_VBL      ;wait for VBL to start (bit 7 set on IIe)
WAIT_NOT    LDA   $C019
            BMI   WAIT_NOT      ;wait for VBL to end
            RTS
```

Replace `JSR DELAY` with `JSR WAIT_VBL` and the animation runs at
60 Hz (NTSC) or 50 Hz (PAL), locked to the scanout. Exercise 2
asks you to do this.

**Important IIe note:** the polarity of `$C019` bit 7 differs
between the IIe and later Apples (IIc, IIgs). On the IIe, bit 7
set = "in VBL." On the IIc, bit 7 clear = "in VBL." If you
distribute software that polls `$C019`, you check the machine
identification byte at `$FBB3` first or just don't use VBL polling.
For this tutorial we're targeting the IIe specifically so
"bit-7-set means VBL" is what we use.

## Exercises

1. **Leave a trail.** Remove the `JSR ERASE` call. What changes?
   Now make the trail decay: after every N frames, run a "fade"
   pass that overwrites every character on the screen with a space
   *only if* it currently shows the message character. (Hint: this
   needs a screen read, which on Apple II is just `LDA (BASL),Y`.)
2. **VBL timing.** Replace `DELAY` with `WAIT_VBL` as shown above.
   The bouncer now runs at 60 fps instead of 16. Is that too fast?
   If yes, call `WAIT_VBL` multiple times to slow down (`JSR
   WAIT_VBL : JSR WAIT_VBL : JSR WAIT_VBL` halves to 20 fps).
3. **Second bouncer.** Add `COL2`, `ROW2`, `DCOL2`, `DROW2`. Erase
   and draw both each frame. The second bouncer's message could be
   `"GREETINGS!"`. What happens when they overlap? Should overlap
   be handled?

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 5

| Want to... | Use |
|---|---|
| Erase before draw, not after | The simple flicker-free pattern |
| Negate a one-byte signed value | `LDA #0 : SEC : SBC value` |
| Wait one frame (Apple IIe) | Poll `$C019` bit 7 |
| Detect "key pending" | `LDA $C000 : BMI key_pending` |
| Acknowledge key | `STA $C010` |
| Time a delay loop crudely | Nested `DEY : BNE` (Y outer, X inner) |
