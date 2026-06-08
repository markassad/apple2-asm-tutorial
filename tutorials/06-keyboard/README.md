# Stage 6 — Keyboard input

**Source:** `src/WALKER.S`
**Build:** `make PROGRAM=WALKER run`

You've used the keyboard for "press any key to continue" since stage
1. Now it's time to read *which* key, and to do something different
based on the answer. The demo is a single '@' character you can move
around the text screen with the arrow keys.

## What you'll learn

- How `$C000` and `$C010` work together
- The Apple IIe key-code table for arrow keys and ESC
- The `CMP` cascade pattern for dispatch
- Why you save the old position before moving
- The "JSR then fall-through" trick for a hex printer

## The keyboard, in detail

There are two addresses you care about:

- **`$C000`** — keyboard data register. Reading it returns
  bits 0-6 of the most-recent key as ASCII, plus bit 7 set
  to "1 means a key is waiting, 0 means no key has happened
  since the last acknowledgement."
- **`$C010`** — keyboard strobe. *Any* read or write of this
  address clears bit 7 of `$C000`.

So the canonical "wait for key" sequence is:

```
:WAIT       LDA   $C000
            BPL   :WAIT       ;loop while bit 7 clear (no key)
            STA   $C010       ;ack the key
```

After `STA $C010`, `$C000` still has the key code in bits 0-6 *with
bit 7 set* (the strobe clear takes effect on the next read), so the
A register at this point is the key code. That's why `LDA $C000`
then `STA $C010` works: A keeps the key, the strobe clears for next
time.

If you don't `STA $C010`, the next `LDA $C000` will still see bit 7
set and you'll process the same key twice.

## The Apple IIe key-code table

Reading `$C000` returns bytes with bit 7 set. After masking with
`#$7F` you'd get the raw 7-bit code, but most Apple II code compares
against the high-bit-set form directly:

| Key | 7-bit code | As read from `$C000` |
|---|---|---|
| Left arrow | `$08` | `$88` |
| Right arrow | `$15` | `$95` |
| Up arrow | `$0B` | `$8B` |
| Down arrow | `$0A` | `$8A` |
| ESC | `$1B` | `$9B` |
| Return | `$0D` | `$8D` |
| Space | `$20` | `$A0` |
| `A` | `$41` | `$C1` |
| `0` | `$30` | `$B0` |

(The Apple II keyboard is uppercase-only on the original II/II+; the
IIe and IIc added a Caps Lock and proper lowercase. On the IIe in
MAME, with Caps Lock on, letters come back uppercase.)

Notice the arrow keys map to Ctrl-H / Ctrl-K / Ctrl-J / Ctrl-U.
That's the venerable VT-100-ish convention — moving the cursor was
historically the same as those control characters. If you're
writing a text editor or game that should also accept WASD or HJKL,
you check for the additional code values too.

## The dispatch cascade

```
            CMP   #K_ESC
            BEQ   :QUIT
            LDX   COL
            STX   OLD_COL
            LDX   ROW
            STX   OLD_ROW
            CMP   #K_LEFT
            BEQ   :L
            CMP   #K_RIGHT
            BEQ   :R
            CMP   #K_UP
            BEQ   :U
            CMP   #K_DOWN
            BEQ   :D
            JMP   :WAIT       ;unknown key, keep waiting
```

This is the most-common dispatcher: a chain of `CMP` / `BEQ`
pairs. Each `CMP` doesn't change A, so we can keep comparing the
same key against different constants without reloading.

For up to ~5 cases the cascade is fine. Beyond that, you'd reach
for a *jump table* — store the handler addresses in memory, index
by key, and `JMP` via indirect addressing. The cascade is 4 bytes
per case (CMP + BEQ); a jump table is ~6 bytes total for setup plus
2 bytes per case. The crossover is around 10 cases.

The `LDX COL : STX OLD_COL` and friends save the current position
*before* deciding which way to move. We need OLD_COL/OLD_ROW after
the move to know where to erase the old '@'.

## Bounds checking pattern

Each direction handler tests "would moving exceed the edge?" before
moving:

```
:L          LDX   COL
            BEQ   :WAIT        ;already at col 0, ignore
            DEC   COL
            JMP   :MOVED
```

`LDX COL : BEQ :WAIT` reads "if COL is zero, ignore the keypress
and go back to waiting for input." For "right":

```
:R          LDX   COL
            CPX   #MAX_COL
            BEQ   :WAIT
            INC   COL
            JMP   :MOVED
```

`CPX #MAX_COL : BEQ :WAIT` reads "if COL is already at MAX_COL, the
move would go past the edge." Skip the move.

A common bug: forgetting that the bounds check should be against
*both* edges. With `BCS` instead of `BEQ` you can use a single
comparison that catches both wrap-below-0 and overshoot — but
since `COL` is unsigned and we only ever move by 1, the equality
test is simpler.

## The move-then-erase sequence

```
:MOVED      LDA   OLD_ROW
            JSR   BASCALC
            LDY   OLD_COL
            LDA   #' '+$80
            STA   (BASL),Y
            ; ...bump steps...
            JMP   :LOOP
```

Once we've updated `COL`/`ROW`, the *previous* `(OLD_COL, OLD_ROW)`
still has the '@' on screen. We erase it (write a space), bump the
step counter, then jump to `:LOOP` which redraws the '@' at the new
`COL`/`ROW`.

Why not "erase first, then move, then redraw"? Same result. We
chose move-then-erase here because the dispatcher needs OLD_ROW
saved before it can decide whether to move, and once we've decided
to move we may as well do it before the erase. With erase-then-move
you'd save OLD before erasing too. Same cost.

## The hex printer

`SHOW_STEPS` prints two hex digits at row 23, cols 8-9. It uses a
classic 6502 trick: ends with a JSR to a helper, then falls
through into the same helper for the second call.

```
SHOW_STEPS  LDA   #23
            JSR   BASCALC
            LDY   #8
            LDA   STEPS
            PHA
            LSR
            LSR
            LSR
            LSR
            JSR   PRINT_NIB   ;first call (high nibble)
            PLA
            AND   #$0F
            ; fall through

PRINT_NIB   ORA   #$30
            CMP   #$3A
            BCC   :OUT
            CLC
            ADC   #6
:OUT        ORA   #$80
            STA   (BASL),Y
            INY
            RTS
```

The stack walks through three frames here:
1. *Caller* `JSR SHOW_STEPS` pushes return addr A.
2. *SHOW_STEPS* `JSR PRINT_NIB` pushes return addr B.
3. *PRINT_NIB* `RTS` pops B, jumps back to SHOW_STEPS.
4. SHOW_STEPS continues: `PLA`, `AND`, then falls into `PRINT_NIB`.
5. *PRINT_NIB* `RTS` pops A, jumps back to the original caller.

That's two distinct uses of `RTS` to pop different return
addresses. The point is that "subroutine" is just "code that ends
in RTS"; whether you got there by `JSR` or by falling through is up
to you.

Saved: 4 bytes (avoid a second `JSR PRINT_NIB : RTS` sequence) and
12 cycles. Real Apple II ROM code uses this trick everywhere.

The `CMP #$3A : BCC :OUT : ADC #6` trick: '0'-'9' are ASCII `$30`-`$39`,
'A'-'F' are `$41`-`$46`. Their difference is 7 (jumping over `:`, `;`,
`<`, `=`, `>`, `?`, `@`). So for nibble values 0-9 we just `ORA #$30`;
for 10-15 we add 6 more after the `ORA`. The `CMP #$3A : BCC` is
"if the result of ORA is `< $3A`, jump to output." Same effect as
"if the nibble was < 10."

## Exercises

1. **Wrap-around movement.** Instead of clamping at the edges,
   wrap the '@' around. Stepping off the left edge puts you at the
   right edge of the same row. Stepping off the top puts you at
   the bottom. Hint: replace `BEQ :WAIT` with `LDA #MAX_COL : STA
   COL : JMP :MOVED` in the `:L` handler.
2. **Walls.** Make column 10 (or row 5) impassable. The dispatcher
   needs to predict the *next* position and check whether it's a
   wall *before* updating. You'll need to refactor each direction
   handler to compute the candidate position separately.
3. **Pickup.** Place a `$` somewhere on the screen at startup. When
   the '@' walks into the `$`, print "GOT IT!" on row 22 and
   remove the `$`. Hint: check the screen byte at the new position
   with `LDA (BASL),Y` before drawing the '@'.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 6

| Want to... | Use |
|---|---|
| Poll until a key | `LDA $C000 : BPL back` |
| Acknowledge key | `STA $C010` (or any access to `$C010`) |
| Compare key value | `CMP #$XX` against high-bit-set codes |
| Mask high bit off | `AND #$7F` |
| Left/right arrows (IIe) | `$88` / `$95` |
| Up/down arrows (IIe) | `$8B` / `$8A` |
| ESC | `$9B` |
| Return | `$8D` |
| Print one hex digit | `ORA #$30 : CMP #$3A : BCC out : ADC #6` |
