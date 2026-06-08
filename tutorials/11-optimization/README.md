# Stage 11 — Optimization tricks

**Source:** `src/BENCH.S`
**Build:** `make PROGRAM=BENCH run`

The Apple II runs at 1.023 MHz. That's roughly one million
single-byte 6502 instructions per second. For text-mode programs
you almost never bump into it, but for animation, sound, and
hi-res redraws, you can hit the wall fast. This stage is about
recognising when, and what to do.

The demo (`BENCH.S`) replaces the `JSR BASCALC` you've seen in
every previous stage with a lookup table, and the README walks
through *why* that helps, plus three other tricks that real Apple
II programmers used to make games feel snappy.

## What you'll learn

- 6502 cycle counting: enough to estimate before you measure
- The lookup-table-vs-formula tradeoff (the one in `BENCH.S`)
- Page-boundary penalties on indexed addressing
- Self-modifying code: rewriting instructions in place
- Loop unrolling and when it pays off
- When *not* to optimize

## Cycle counting in 60 seconds

The 6502 takes a fixed, documented number of cycles for every
instruction, with three exceptions:

1. **Branches**: 2 cycles if not taken, 3 if taken, 4 if taken
   *and* the target crosses a 256-byte page boundary.
2. **Indexed reads**: `LDA addr,X` is 4 cycles normally, **5** if
   `(addr + X) >> 8 != addr >> 8` (i.e. crossed a page).
3. **Stores via indexed addressing**: always pay the page-cross
   penalty (`STA addr,X` is 5 cycles regardless — the CPU does the
   "extra read" speculatively to handle the page-cross case).

Common instructions, off-the-top-of-head:

| Mnemonic | Form | Cycles |
|---|---|---|
| LDA #imm | `LDA #$nn` | 2 |
| LDA zp | `LDA $nn` | 3 |
| LDA abs | `LDA $nnnn` | 4 |
| LDA abs,X | `LDA $nnnn,X` | 4 (+1 page) |
| LDA (zp),Y | `LDA ($nn),Y` | 5 (+1 page) |
| STA abs | `STA $nnnn` | 4 |
| STA (zp),Y | `STA ($nn),Y` | 6 |
| INX/DEX/INY/DEY | | 2 |
| INC/DEC zp | `INC $nn` | 5 |
| INC/DEC abs | `INC $nnnn` | 6 |
| JSR | `JSR target` | 6 |
| RTS | | 6 |
| JMP | `JMP target` | 3 |
| BNE etc. taken | | 3 (+1 page) |
| BNE etc. not taken | | 2 |
| CMP / CPX / CPY (any) | | 2-4 |

For a real cycle count of any routine, count every line; the total
divided by 1,023,000 gives the wall-clock time at 1.023 MHz.

## The `BASCALC` vs. lookup table comparison

`BASCALC` in ROM is roughly:

```
BASCALC     PHA               ;3 cycles
            AND   #$18         ;2
            CLC               ;2
            ROR                ;2
            STA   BASL         ;3
            PLA               ;4
            AND   #$07         ;2
            ORA   #$04         ;2
            STA   BASH         ;3
            PLA               ;4
            AND   #$E0         ;2
            LSR               ;2
            LSR               ;2
            ORA   BASL         ;3
            STA   BASL         ;3
            RTS               ;6
            ; total ~ 45 cycles
```

Plus the `JSR BASCALC` itself: 6 cycles. Plus the `LDA #N` that
loaded the row number first: 2 cycles. Round trip: **~53 cycles**
per row.

`BENCH.S` instead does:

```
            LDA   ROW_LO,X     ;4 (+1 if page-cross, which it isn't here)
            STA   BASL         ;3
            LDA   ROW_HI,X     ;4
            STA   BASH         ;3
            ; total: 14 cycles
```

**14 vs. 53.** ~40 cycles saved per row × 24 rows = ~950 cycles
saved per full-screen pass. At 1 MHz that's about 1 ms. Doesn't
sound like much... until you realise a 60-fps animation has only
17 ms per frame. If you do this in the inner loop of every frame
of a hi-res game, the table is what makes the game playable.

**Cost**: 48 bytes of table. A 24-entry × 2-byte table is small
beer compared to the 8 KB of hi-res memory you're trying to fill.

The general lesson: any time you have a routine that computes a
known function of a small input set, **store the answers in a
table instead of recomputing**. Hi-res row addresses are
192-entry tables of 2 bytes each (384 bytes); fast trig tables
are 256-entry tables of 1 byte each (256 bytes). Almost every
serious Apple II program has a couple of these.

## Page-boundary penalties

If your table lives across a page boundary, every indexed read
that crosses pays an extra cycle:

```
* Suppose ROW_LO is at $20F0.  Then ROW_LO,X for X >= 16 reads
* from $2100 onward -- different page, +1 cycle each.

            LDA   ROW_LO,X      ;4 cycles for X in 0..15
                                 ;5 cycles for X in 16..23
```

The fix: **page-align your hot tables.** In Merlin32:

```
            DS    \             ;align to page boundary
ROW_LO      DFB   ...
```

The assembler pads to the next `$xx00` boundary. Now `ROW_LO,X`
costs exactly 4 cycles for every X in 0..255 — no surprise
penalties.

For `BENCH.S` we didn't bother because the table is tiny and only
24 entries. But once you've got a 256-byte sine table that's hit
many times per frame, alignment matters.

You can also straddle smarter: align *just* the part of the table
that's accessed in a hot loop. The compiler-y trick is to break
your data into separate sections and apply `DS \` only where it
matters.

## Self-modifying code

The 6502 has no separate code-and-data memory. Instructions are
just bytes you can `STA` into. Sometimes that lets you "specialise"
a routine at runtime to be faster.

Example: an inner loop that always reads from `($ABCD,Y)`. The
absolute-indexed mode bakes the base address into the instruction
(it's an `LDA $ABCD,Y`, i.e. `B9 CD AB`). If the base address
changes between calls but stays constant *within* a call:

```
LOOP        LDA   $0000,Y         ;the $0000 will be patched
            ...
            INY
            BNE   LOOP
            RTS

* To call: patch the $0000 to your real base, then JSR LOOP.
            LDA   #<TARGET
            STA   LOOP+1
            LDA   #>TARGET
            STA   LOOP+2
            JSR   LOOP
```

You save the indirect through zero page (`LDA (PTR),Y` is 5
cycles + page penalty; `LDA $xxxx,Y` is 4 cycles + page penalty,
and no zero-page bytes burned). For a tight inner loop running
thousands of times, that's a measurable win.

The downside: it's harder to reason about. If you accidentally
write to part of an instruction without setting it back, the
behaviour silently changes the next call. Real systems with
write-protected code pages forbid SMC; the 6502 doesn't.

Modern code, including high-performance Apple II games, uses SMC
sparingly — for the hottest inner loops only, with comments
explaining what's being modified.

## Loop unrolling

If the body of your loop is small and the trip count is known and
bounded, copy-pasting the body N times eliminates the loop
overhead (the `INX : CPX : BNE` adds 7 cycles per iteration).

Example: clear 8 bytes.

Rolled:

```
            LDX   #8
            LDA   #0
:LP         STA   BUF-1,X
            DEX
            BNE   :LP

* 8 iterations * (STA 5 + DEX 2 + BNE 3) = 80 cycles
```

Unrolled:

```
            LDA   #0
            STA   BUF
            STA   BUF+1
            STA   BUF+2
            STA   BUF+3
            STA   BUF+4
            STA   BUF+5
            STA   BUF+6
            STA   BUF+7

* 8 STA * 4 = 32 cycles.  ~2.5x faster.
```

Cost: 24 bytes of code instead of 9. Trade space for time.

For larger fills, partial unrolling (e.g. `STA` four times per
loop iteration so you only branch every 4 stores) gives most of
the speed at most of the size savings.

## When *not* to optimize

The seductive answer is "the inner loop." The honest answer is
"profile first." On a 1 MHz machine you can do a lot with no
optimization at all. Stages 1-10 don't optimize, and the demos
run snappily.

A few principles:

- **If it's user-facing and runs once**, don't optimize it. A
  90-cycle vs. 200-cycle startup is invisible.
- **If it runs every frame at 60 fps**, the frame budget is 17,000
  cycles. Anything that takes more than ~1000 cycles per frame
  starts to matter.
- **If you have an inner loop of inner loops**, optimize the
  innermost one first. Outer loops are usually noise.

The cycle-count instinct comes back once you've measured a few
times. Until then: write the clean version, run it, see if it's
fast enough.

## Exercises

1. **Time it.** Put the lookup-table version and the `BASCALC`
   version of a screen fill in the same program. Print one of them
   on the screen first, wait for a key. Then run the other. Use a
   small loop counter incrementing once per frame to feel the
   difference. (You probably won't notice; the screen fills are
   too fast either way. Try filling 100 times to feel it.)
2. **Page-align ROW_LO/ROW_HI in BENCH.S.** Add `DS \` before the
   tables. Disassemble or check the listing
   (`build/BENCH_S01_Segment1_Output.txt`) to verify the new
   addresses. Were the original ones already on a page boundary?
3. **Unroll the column loop.** The inner `:CL` loop in `BENCH.S`
   writes 40 bytes. Unroll it into 10 groups of 4 `STA` each, with
   a counter that branches every 4 iterations. Measure cycles for
   the original and the unrolled. Worth the code-size cost?

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 11

| Want to... | Use |
|---|---|
| Eliminate a per-call computation | Precompute into a table |
| Avoid the +1 cycle page-cross | Align hot tables with `DS \` |
| Squeeze the very innermost loop | Self-modifying code (sparingly) |
| Cut the per-iteration overhead | Unroll the loop body N times |
| Replace `(zp),Y` with `abs,Y` | SMC the absolute address before the loop |
| Estimate elapsed time | Sum cycles, divide by 1,023,000 (or 1,020,484 on PAL) |

### Reference cycle counts for the routines you've used

| Routine | Approximate cycles |
|---|---|
| `BASCALC` ($FBC1) | ~45 + JSR/RTS overhead = ~57 |
| `COUT` ($FDED) for normal char | ~50-60 |
| `HOME` ($FC58) | ~5000 (clears 960 bytes) |
| `HGR2` ($F3D8) | ~50,000 (clears 8 KB hi-res) |
| `HPOSN` ($F411) | ~80 |
| `HPLOT0` ($F457) | ~70 |
| `HLIN` ($F53A) | varies wildly with line length |
| `WAIT_VBL` poll | varies, ~17,000 cycles per frame (until next VBL) |
