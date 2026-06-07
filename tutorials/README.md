# Apple IIe 6502 Assembly Tutorial

A staged tutorial for writing real programs for the Apple IIe in 6502
assembly. Builds on the workspace at the root of this repo: Merlin32
to assemble, `a2fuse` to pack a ProDOS disk, MAME's `apple2e` driver
to run.

## Who this is for

You can write code and read code, but you've never written 6502 (or any
8-bit) assembly before. You know what a register and a stack are; you
don't know what's special about the *6502's* registers or stack, or why
the Apple II's screen memory looks the way it does. Each stage
introduces a few new concepts, a small program that demonstrates them,
and 2-3 exercises with solutions.

## How each stage is structured

```
tutorials/NN-name/
  README.md       walkthrough, concepts, exercises at the bottom
  SOLUTIONS.md    worked solutions (peek deliberately)
```

The actual source file for each stage lives in `src/` at the workspace
root, under the name the README tells you to use. To build and run
stage 1, for example:

```sh
make PROGRAM=HELLO run
```

(`INSTALL_NAME` defaults to `$(PROGRAM).SYSTEM`, so the SYS file
auto-launches at boot.)

## Curriculum

| # | Stage | Source | Concepts introduced |
|---|---|---|---|
| 1 | [Anatomy of a SYS file](01-anatomy/README.md) | `src/HELLO.S` | ProDOS SYS files, the `ORG`/`TYP`/`DSK` directives, EQUates, `ASC`, the high-bit ASCII trick, calling ROM (`COUT`) |
| 2 | The text screen | `src/FILL.S` | The `$0400-$07FF` text page, the interleaved row layout, screen holes, `BASCALC`, direct writes via `(BASL),Y` |
| 3 | Loops, indexes, addressing modes | `src/MULT.S` | LDA's many flavors, X and Y registers, comparison and branching, looping idioms |
| 4 | Subroutines and the stack | `src/PRINTAT.S` | `JSR`/`RTS`, the stack page `$0100-$01FF`, passing arguments via zero page, reusable helpers |
| 5 | Animation and timing | `src/BOUNCE.S` | The frame loop, delay loops, erase-before-draw, the vertical blank, two's-complement direction flips |
| 6 | Keyboard input | `src/WALKER.S` | `$C000`/`$C010`, polling vs blocking, the IIe keymap, arrow keys, ESC |
| 7 | Lo-res graphics | `src/SHAPES.S` | The `GR` soft switches, lo-res memory layout (it shares with text!), nibble color encoding, the 16-color palette |
| 8 | The speaker and sound | `src/BEEP.S` | `$C030` clicks, square-wave generation, frequency vs duration, a tiny tone routine |
| 9 | Hi-res graphics fundamentals | `src/HIRES.S` | The `$2000-$3FFF` and `$4000-$5FFF` hi-res pages, the truly weird 7-pixels-per-byte interleaved layout, why we use page 2 from a SYS file |
| 10 | ProDOS MLI for file I/O | `src/LOAD.S` | The MLI dispatcher at `$BF00`, the `JSR / DFB cmd / DA params` calling convention, OPEN/READ/CLOSE |
| 11 | Optimization tricks | `src/BENCH.S` | Page-boundary penalties, zero-page lookup tables, unrolled loops, self-modifying code, when each is worth it |
| 12 | A complete small game | `src/PONG.S` | Game state, the main loop, score display, win/reset, putting input + animation + sound + lo-res together |

## Prerequisites

Stage 0 is the workspace itself. Before stage 1, confirm:

```sh
make distclean && make PROGRAM=BOUNCE run
```

boots MAME with `BOUNCE.SYSTEM` running. If that works, every stage
afterward is the same loop with a different source.
