# Stage 3 — Loops, indexes, addressing modes

**Source:** `src/MULT.S`
**Build:** `make PROGRAM=MULT run`

So far you've used a tiny slice of the 6502's instruction set: `LDA`
with `#imm`, `LDA` with an absolute address (`LDA MSG,X`), `STA`
with indirect-indexed (`STA (BASL),Y`), and `JSR`/`RTS`. That's
about a third of what you'll reach for in real code. This stage
fills in the rest, and the demo (an 8x8 multiplication table)
exercises every common addressing mode and looping idiom in close
quarters.

## What you'll learn

- The seven addressing modes you'll actually use
- Why X and Y are *different* registers, not just two of the same
  thing
- What `CMP`/`CPX`/`CPY` leave behind and which branch instructions
  consume each flag
- Three distinct loop idioms (count-up, count-down, walk-a-pointer)
- How to do multiplication and division on a CPU that has neither

## Addressing modes you'll meet

The 6502 has thirteen addressing modes if you count them all, but a
practical 95% of code uses these seven. Every load and store
instruction (`LDA`, `STA`, `LDX`, `STX`, `LDY`, `STY`, `EOR`, `AND`,
`ORA`, `ADC`, `SBC`, `CMP`) supports a subset.

| Form | Name | Example | What it does |
|---|---|---|---|
| `#nn` | Immediate | `LDA #$80` | Use the literal byte as the operand. |
| `nn` | Zero page | `LDA $E0` | Load from address `$00E0`. One byte cheaper than absolute. |
| `nnnn` | Absolute | `LDA $0400` | Load from a 16-bit address. |
| `nnnn,X` | Absolute indexed (X) | `LDA MSG,X` | Load from `MSG + X`. |
| `nnnn,Y` | Absolute indexed (Y) | `LDA MSG,Y` | Same with Y. (`STA` works with this too.) |
| `nn,X` | Zero page indexed (X) | `LDA TABLE,X` | Like absolute,X but the base is zero page. Cheaper. |
| `(nn),Y` | Indirect-indexed | `STA (BASL),Y` | Read 16-bit address from zp `nn` (the bytes at `nn` and `nn+1`), add Y, store/load there. |

A few notes on the messier corners:

- `(nn,X)` (indexed-indirect) also exists, but you'll see it once
  every few thousand lines. It does `addr = read16(zp + X) ; A =
  read(addr)`. It mostly shows up in old code-table dispatch and the
  Apple II's Pascal interpreter.
- There's no `(nnnn)` direct indirect on the original NMOS 6502
  except for `JMP (nnnn)`. The 65C02 (Apple IIc and IIe with the
  enhancement) adds `LDA (nn)` without the trailing `,Y`. If you're
  targeting the IIe specifically, you can use those. The Apple IIe
  has a 65C02 from the "enhanced" revision onward (1985); MAME's
  `apple2e` driver emulates the enhanced IIe.
- All the indexed modes have a subtle cost: if `base + X` crosses a
  256-byte boundary, the read takes one extra cycle. That's the
  "page boundary penalty" we'll exploit in stage 11.

## X and Y are not the same

X and Y are both 8-bit index registers, but the 6502 wasn't
symmetrical about them:

| | X | Y |
|---|---|---|
| `LDA nn,reg` (zp,reg) | ✅ | ❌ |
| `LDA nnnn,reg` (abs,reg) | ✅ | ✅ |
| `LDA (nn,reg)` (indexed-indirect) | ✅ | ❌ |
| `LDA (nn),reg` (indirect-indexed) | ❌ | ✅ |
| `INC reg`, `DEC reg` | ✅ (`INX`, `DEX`) | ✅ (`INY`, `DEY`) |
| `TXS`/`TSX` (stack pointer) | ✅ | ❌ |

So X owns "zero page indexed" and "indexed-indirect" and the stack
pointer; Y owns "indirect-indexed." When you see code casually
write `LDX` here and `LDY` there it's not capriciousness — the
choice locked in which addressing modes that loop can use.

In `MULT.S`, the title loop uses `LDA TITLE,X` (X is the table
index) and `STA (BASL),Y` (Y is the screen column). They genuinely
have to be different registers because no single one of them does
both jobs.

## Comparison and branching

`CMP`, `CPX`, and `CPY` perform `reg - operand` without storing the
result anywhere. They set three flags:

| Flag | Set when | Branch | Read as |
|---|---|---|---|
| Z (zero) | `reg == operand` | `BEQ` / `BNE` | equal / not equal |
| C (carry) | `reg >= operand` (treating both unsigned) | `BCC` / `BCS` | less than / greater or equal |
| N (negative) | bit 7 of `reg - operand` set | `BPL` / `BMI` | (signed) less than / greater or equal |

For unsigned values (which is most of what you compare) you almost
always use the Z and C flags. `CMP #10 : BCC :LESS` means "if A
< 10, jump." `CMP #10 : BCS :GE` means "if A >= 10."

Other useful branches set by anything that updates the flags
(loads, arithmetic, shifts):

- `BPL` / `BMI` — bit 7 of last result (also used to detect "key
  ready" in `LDA $C000`)
- `BVC` / `BVS` — overflow flag (rarely set deliberately)

## Loop idioms

There are essentially three loops in 6502 code:

**Count up:**

```
            LDX   #0
:LOOP       ; ...do something with X
            INX
            CPX   #N
            BNE   :LOOP
```

**Count down (cheaper):**

```
            LDX   #N
:LOOP       ; ...do something
            DEX
            BNE   :LOOP
```

`DEX` already sets the Z flag, so you skip the `CPX` and save 2
cycles per iteration. The downside: X counts N, N-1, N-2 ... 1, which
is backwards from what your problem might want.

**Walk a pointer:**

```
            LDY   #0
:LOOP       LDA   (PTR),Y
            BEQ   :DONE        ;null-terminator stops the loop
            ; ...
            INY
            BNE   :LOOP
```

This pattern is everywhere in null-terminated string code, including
stage 1's `HELLO.S` print loop.

## Walking through `MULT.S`

### Title loop

```
            LDA   #0
            JSR   BASCALC
            LDY   #8
            LDX   #0
:TLOOP      LDA   TITLE,X
            BEQ   :TDONE
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :TLOOP
```

`LDA TITLE,X` is *absolute indexed (X)*. The CPU reads the byte at
`TITLE + X`. Two registers in flight at once: X walks the source
data (`TITLE,X`), Y walks the destination (`(BASL),Y`).

### The product computation

```
            LDA   #0
            LDX   COL
:MULLOOP    CLC
            ADC   ROW
            DEX
            BNE   :MULLOOP
```

The 6502 has no multiply instruction. To compute `ROW * COL`, we
add `ROW` to A `COL` times. `LDX COL` loads the count (note: `COL`
is a *zero page address*, not an immediate — no `#`). `DEX : BNE`
is the count-down idiom; we use it because it's two cycles faster
per iteration and the order doesn't matter (we're summing).

For `COL=1`, the loop runs once and `A = 0 + ROW`. For `COL=8`,
the loop runs eight times and `A = 8 * ROW`. If `COL` were `0`
(which never happens here) the first `DEX` would wrap to `$FF` and
the loop would run 256 times — be careful with this pattern when
the count might be zero.

### The division by 10

```
            LDX   #0
:DIVLOOP    CMP   #10
            BCC   :DIVDONE
            SEC
            SBC   #10
            INX
            JMP   :DIVLOOP
:DIVDONE    STA   ONES
            STX   TENS
```

Same trick in reverse: subtract 10 repeatedly, counting iterations.
After the loop, X holds the tens digit and A holds the ones (0-9).

The `SEC` before `SBC` is mandatory. The 6502's `SBC` does
`A - operand - (1 - C)`, so to do plain `A - operand` you need the
carry flag set going in. That's the one bit of 6502 that surprises
everyone (every other CPU's subtract is plain) — burn it in: **`SEC`
before every `SBC`**, just like `CLC` before every `ADC`.

The `CMP #10 : BCC :DIVDONE` test reads as "if `A < 10`, we're
done." `BCC` branches on carry clear, which `CMP` clears when the
left operand is *less* than the right.

### Y from the cell number

```
            LDA   COL
            ASL                  ;A = 2*COL
            CLC
            ADC   COL            ;A = 3*COL
            SEC
            SBC   #1             ;A = 3*COL - 1
            TAY
```

This is a stock idiom for "multiply by 3" — the 6502 has no `LSR
A,3` or `MUL`, but it has `ASL` (shift left by 1, i.e. multiply by
2) and `ADC` (add). Want `*5`? `ASL : ASL : ADC original`. Want
`*10`? `ASL : ADC orig : ASL`. You can do any small constant
multiply by chaining shifts and adds, and it's substantially faster
than a `MULLOOP`.

`TAY` transfers A to Y (without changing A). Sister instructions:
`TAX`, `TXA`, `TYA`. There's no `TXY` or `TYX` direct — you'd `TXA :
TAY` to copy X to Y.

## Exercises

1. **6x6 table instead of 8x8.** Smaller, products fit single digits
   for the first row. Hint: change every `#9` in the outer loop tests
   to `#7`, and pick new title text.
2. **Powers of 2.** Print `2^0` through `2^8` (= 1, 2, 4, ..., 256).
   Hint: 256 doesn't fit in a byte; you'll need to track the high
   byte separately, or stop at `2^7 = 128`. The doubling itself is
   one `ASL` per power.
3. **Highlight the diagonal.** When `ROW == COL`, print the product
   in *inverse* video (no `ORA #$80`). What's the test? What
   changes? You'll need a branch in the cell-print code that uses
   either the regular or inverse character.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 3

| Want to... | Use |
|---|---|
| Count up | `LDX #0 : ... : INX : CPX #N : BNE` |
| Count down (faster) | `LDX #N : ... : DEX : BNE` |
| Walk a string | `LDY #0 : LDA (PTR),Y : BEQ :DONE : ... : INY : BNE` |
| Multiply by 2 | `ASL` |
| Multiply by N (small) | combine `ASL` and `ADC original` |
| Multiply by N (variable) | repeated `ADC` loop |
| Divide by 10 | repeated `SBC #10`, count iterations in X |
| Subtract (any) | always `SEC` before `SBC` |
| Add (any) | always `CLC` before `ADC` |
| Compare unsigned | `CMP` / `BCC` (less) / `BCS` (>=) / `BEQ` (=) |
| Move A to Y | `TAY` |
| Move A to X | `TAX` |

### Cycle counts worth remembering

| Mode | Cycles | Notes |
|---|---|---|
| `LDA #nn` | 2 | immediate |
| `LDA nn` | 3 | zero page |
| `LDA nnnn` | 4 | absolute |
| `LDA nnnn,X` | 4 (+1 if crosses page) | absolute indexed |
| `LDA (nn),Y` | 5 (+1 if crosses page) | indirect indexed |
| `STA (nn),Y` | 6 | always; the page-cross penalty is built in |
| `JSR` | 6 | + the time inside the routine |
| `RTS` | 6 | |
| `BNE` taken | 3 (+1 if crosses page) | not taken: 2 |
