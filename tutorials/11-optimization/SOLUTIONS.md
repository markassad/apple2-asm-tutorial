# Stage 11 solutions

## 1. Timing the two methods

Wrap each fill in a 100-iteration counter and watch the difference
by eye:

```
            LDX   #100
:OUTER1     STX   :TMPX
            JSR   FILL_BASCALC
            LDX   :TMPX
            DEX
            BNE   :OUTER1

            ; ...then time the table version:
            LDX   #100
:OUTER2     STX   :TMPX
            JSR   FILL_TABLE
            LDX   :TMPX
            DEX
            BNE   :OUTER2
:TMPX       DFB   0
```

At ~950 cycles saved per screen pass, 100 passes ≈ 95,000 cycles
saved ≈ 93 ms. You'll see the table version finish noticeably
faster. (At 1000 passes, the difference is a full second — easy to
spot.)

For more precise timing, MAME's debugger has a cycle counter. From
the workspace:

```sh
mame apple2e -rompath ~/mame/roms -flop1 dist/WORK.po -debug
```

`Ctrl-Break` to break into the debugger. Set a breakpoint at the
start of each fill, then `Ctrl-F` (or "Cycles since last break")
to read the cycle counter.

## 2. Page alignment

Add `DS \` before the table:

```
            DS    \
ROW_LO      DFB   ...
            DFB   ...
            DFB   ...
ROW_HI      DFB   ...
```

Build and look at `build/BENCH_S01_Segment1_Output.txt` for the
addresses Merlin32 assigned. The original `ROW_LO` was probably
in the middle of a page somewhere (depends on the rest of the
program length). After `DS \`, `ROW_LO` is at the next `$xx00`.

Notice that the `ROW_HI` immediately follows `ROW_LO`. Since
`ROW_LO` is 24 bytes and ends mid-page, `ROW_HI` also starts
mid-page. The "load `ROW_HI,X`" calls might still cross a page
boundary on a high enough X. Double-aligning would mean another
`DS \` before `ROW_HI`, costing some padding. For 24-entry tables
on a 256-byte page, the cross at most happens once per pass — the
optimization is barely worth it. For 256-entry tables, the
penalty kicks in for every X above a certain threshold and
alignment matters a lot.

## 3. Unroll the column loop

```
* Unrolled inner: 10 groups of 4 STA, no per-iteration branch
*  inside the group.
:RL         LDA   ROW_LO,X
            STA   BASL
            LDA   ROW_HI,X
            STA   BASH
            LDY   #0
            LDA   #'*'+$80
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY                  ;Y = 4
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY                  ;Y = 8
            ; ... continue for 10 groups, Y reaches 40 ...
            INX
            CPX   #24
            BNE   :RL
```

Cycle count per row:

- Rolled (40 iters × (STA 6 + INY 2 + CPY 2 + BNE 3)) = 40 × 13 =
  520 cycles + the final BNE-not-taken
- Unrolled (40 STA × 6 + 40 INY × 2) = 240 + 80 = 320 cycles

200 cycles saved per row × 24 rows = ~5000 cycles per screen.

Code size: rolled is ~12 bytes for the inner; unrolled is ~80
bytes (40 × 2 bytes per `STA (BASL),Y` + 40 × 1 byte INY). About
70 bytes added for ~5000 cycles per pass. Worth it for a hot
inner loop; *not* worth it for a one-time fill.

You can do partial unrolling — unroll 4x with one branch per 4
stores — and get most of the speed with much less code:

```
:RL         LDY   #0
:CL         STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            CPY   #40
            BNE   :CL
            ; per-iter: 4×(STA 6+INY 2) + CPY 2 + BNE 3 = 37
            ; iterations: 40/4 = 10
            ; per row: 370 cycles
```

Partial 4x unroll: 370 cycles per row, 35-byte inner block.

The progression — rolled, partial unrolled, fully unrolled —
trades size for time. Pick what your budget allows. Real Apple II
games tend to do 4-8x partial unrolling on the hot innermost loop
and call it good.
