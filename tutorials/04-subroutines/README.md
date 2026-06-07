# Stage 4 — Subroutines and the stack

**Source:** `src/PRINTAT.S`
**Build:** `make PROGRAM=PRINTAT run`

Stage 1 used `JSR COUT` to call into ROM. Stage 4 makes you write
the subroutine. Once you can factor a reusable `printat(row, col,
msg)` out of an inline print loop, the rest of this tutorial gets a
lot less repetitive — every later stage leans on subroutines.

This stage also explains what `JSR` and `RTS` actually do at the
hardware level (they fiddle with the stack), and why the 6502's
stack is a fixed 256-byte page that you can both feed and corrupt.

## What you'll learn

- What `JSR` and `RTS` do to the stack
- Where the stack lives (`$0100-$01FF`), why exactly there, and what
  the stack pointer `S` is
- Three real options for passing arguments to a subroutine: zero
  page, registers, and inline-after-JSR
- How to write `PRINTAT` and use it to build screens declaratively
- What happens if you `RTS` without a matching `JSR`, or `JSR`
  beyond the stack's depth

## The stack lives at $0100-$01FF

256 bytes. Fixed in hardware. You cannot move it. The stack pointer
register `S` is 8 bits and indexes into this page from the top
down: `S = $FF` means "the next push lands at `$01FF`."

When you `JSR target`:

1. The CPU computes "the address one byte before the next
   instruction." (Not the next instruction — one byte before. This
   is a 6502 quirk that doesn't matter as long as `RTS` is
   symmetric with it, which it is.)
2. It pushes the high byte of that address to `$0100 + S`, then
   decrements `S`.
3. It pushes the low byte to `$0100 + S`, then decrements `S`.
4. It loads the program counter with `target`.

When `RTS` runs:

1. Increment `S`. Read the byte at `$0100 + S` (low byte).
2. Increment `S`. Read the byte at `$0100 + S` (high byte).
3. Combine into a 16-bit address, add 1 (to get past the JSR
   instruction).
4. Load that into the program counter and continue.

So each `JSR` burns 2 bytes of stack. Each `RTS` reclaims them. If
your subroutine calls another subroutine which calls another, the
stack grows by 2 bytes per level.

256 bytes of stack ÷ 2 = 128 nested `JSR` calls before you overflow.
In practice you'll never get close — ProDOS itself uses some of that
space, and you should leave headroom. Real Apple II code typically
nests 8-16 deep at most.

If you push too far (overflow), `S` wraps from `$00` back to `$FF`,
and now your subroutine returns will read corrupted addresses from
what *used* to be the bottom of the stack — usually a wild jump and
a crash.

The accumulator and flags can also be pushed (`PHA` / `PLA` and
`PHP` / `PLP`) — useful when a subroutine needs to clobber A but
you want the caller's A preserved. The 65C02 adds `PHX` / `PLX` /
`PHY` / `PLY` for the same purpose with X and Y.

## Why is the stack at $0100-$01FF?

The 6502's stack pointer is *8 bits*. That's a tradeoff: cheap to
implement on a 4000-transistor CPU, but it means the stack can only
address 256 bytes. The hardware hard-codes the high byte to `$01`
and uses `S` as the low byte. You can't change that. You can move
the *initial value* of `S` (with `LDX #$FF : TXS`), but the actual
bytes always sit between `$0100` and `$01FF`.

Page `$00` is faster (zero-page addressing modes are 1 byte
shorter), so Apple chose page `$01` for the stack. Useful side
effect: if you've ever wondered why your code "isn't allowed to
use" `$0100-$01FF` — that's why.

## Three options for argument passing

You can't put 4 integers in 3 registers (A, X, Y) without
overflowing. Conventions to get around this:

### Option A: Zero page (what `PRINTAT.S` does)

```
            LDA   #row
            STA   P_ROW
            LDA   #col
            STA   P_COL
            LDA   #<MSG
            STA   P_PTR
            LDA   #>MSG
            STA   P_PTR+1
            JSR   PRINTAT
```

Pros: any number of arguments, any size. The subroutine reads them
with cheap zero-page addressing.

Cons: caller boilerplate. The five setup instructions take 14
bytes; that's bigger than the JSR itself.

### Option B: Registers

```
            LDX   #row
            LDY   #col
            LDA   #<MSG
            ; ...where do we put the high byte of MSG?  We're out of registers.
            JSR   PRINTAT
```

Works only when total parameters fit in A + X + Y = 3 bytes. For
two integers and a pointer, it doesn't.

### Option C: Inline after JSR

```
            JSR   PRINTAT
            DFB   row
            DFB   col
            DA    MSG
```

The subroutine reads the parameters from after its own return
address, then adjusts the return address to skip past them.

```
PRINTAT     PLA               ;low byte of return address
            STA   RET
            PLA               ;high byte
            STA   RET+1
            LDY   #1
            LDA   (RET),Y     ;first arg (row)
            STA   P_ROW
            INY
            LDA   (RET),Y     ;second arg (col)
            STA   P_COL
            ; ...etc...
            ; Adjust return address by +4 (past the 4 arg bytes)
            CLC
            LDA   RET
            ADC   #4
            STA   RET
            BCC   :NC
            INC   RET+1
:NC         ; Push adjusted address back onto stack so RTS works
            LDA   RET+1
            PHA
            LDA   RET
            PHA
            ; ...do work...
            RTS
```

Pros: caller is dense and reads almost like a function call. The
Apple II monitor uses this style heavily.

Cons: gymnastic stack work. The subroutine pays a fixed setup cost
to read its args, and you must be careful about the +1 offset (the
return address points one *before* the next instruction, remember).

In `PRINTAT.S` we use option A. It's the cleanest path for someone
new to subroutines. Stage 11 (optimization) will revisit option C.

## Walking through `PRINTAT`

```
PRINTAT     LDA   P_ROW
            JSR   BASCALC
            LDA   BASL
            CLC
            ADC   P_COL
            STA   BASL
            BCC   :NOC
            INC   BASH
:NOC        LDY   #0
:LOOP       LDA   (P_PTR),Y
            BEQ   :DONE
            ORA   #$80
            STA   (BASL),Y
            INY
            BNE   :LOOP
:DONE       RTS
```

`BASCALC` gives us `BASL`/`BASH` = address of column 0 of `P_ROW`.

We then need to write at column `P_COL`. Options:

- Add `P_COL` to `Y` before each store, then use `STA (BASL),Y`
  where `Y = msg_index + P_COL`. Works as long as `Y` doesn't
  overflow, which means `P_COL + strlen(msg) < 256`. For a 40-col
  screen with a max-40-char message that's fine.
- Adjust `BASL`/`BASH` once to point at the start cell, then use
  `Y` as the *string index* — what the code does.

The adjustment is `BASL += P_COL` with carry into `BASH`. `BASL +
P_COL` might overflow 8 bits (e.g., `BASL=$E0, P_COL=$28, sum=$108`)
so we test the carry flag and `INC BASH` if needed. The 6502 has no
single instruction for "add 8-bit value to 16-bit register" so this
two-step is the idiom.

Then `LDY #0 : LDA (P_PTR),Y` reads `MSG[0]`, the loop walks Y up
until it hits the null terminator. The `STA (BASL),Y` writes each
character into the adjusted screen address.

`BNE :LOOP` works because `INY` from anything but `$FF` leaves Y
non-zero. If Y were `$FF`, the next `INY` would wrap to `$00` and
`BNE` wouldn't take — a bug for any string longer than 255 bytes.
Our messages are ≤ 40 bytes so we're fine.

## The main program's repetition

Eight `PRINTAT` calls. Each one is 14 bytes of "load args + JSR."
Total caller overhead: 112 bytes. The subroutine itself is 17
bytes. Even after one or two calls, having `PRINTAT` is a net win
on space — and on readability.

You could shave the boilerplate with a Merlin32 *macro*:

```
            MAC   PRAT
            LDA   #]1
            STA   P_ROW
            LDA   #]2
            STA   P_COL
            LDA   #<]3
            STA   P_PTR
            LDA   #>]3
            STA   P_PTR+1
            JSR   PRINTAT
            <<<

            ; ...then call with:
            PRAT  0;14;TITLE
            PRAT  4;2;MENU_HDR
```

Macros expand at assembly time so the byte count is identical to
writing out the calls by hand. Stage 11 talks about when this
matters.

## Exercises

1. **`PRINTHLINE(row, col, length, char)`** — draw a horizontal run
   of a single character. You'll need a fourth zero-page parameter
   (`P_LEN`) and a fifth (`P_CHAR`). The screen-write loop uses Y
   as both the counter and the column offset.
2. **`CLRLINE(row)`** — clear one row. Implement it as a one-liner
   that fills 40 spaces by calling your new `PRINTHLINE`. Hint:
   `' '+$80` is `$A0`.
3. **Nested `JSR` depth tracker.** Add a zero-page byte
   `CALL_DEPTH = $E5`. At the top of `PRINTAT`, `INC CALL_DEPTH`.
   At the bottom, `DEC CALL_DEPTH`. After all calls, print the
   final value with a tiny "hex print" routine. What should it be?
   Now wrap `PRINTAT` in a `PRINTAT_LOG` that JSRs to `PRINTAT` and
   trace it again.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 4

| Want to... | Use |
|---|---|
| Call a subroutine | `JSR target` (pushes return addr, 6 cycles) |
| Return from a subroutine | `RTS` (pops return addr, 6 cycles) |
| Push A | `PHA` |
| Pop A | `PLA` |
| Push flags / pop flags | `PHP` / `PLP` |
| Push X / Y (65C02 only) | `PHX` / `PHY` |
| Get low byte of a label | `#<LABEL` |
| Get high byte of a label | `#>LABEL` |
| Adjust BASL/BASH by N | `LDA BASL : CLC : ADC #N : STA BASL : BCC ok : INC BASH : ok ...` |
