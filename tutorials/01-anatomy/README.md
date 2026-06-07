# Stage 1 — Anatomy of a SYS file

**Source:** `src/HELLO.S`
**Build:** `make PROGRAM=HELLO run`

You've already built and booted `HELLO.SYSTEM` — this stage takes it
apart line by line and explains exactly what every piece is doing. By
the end you'll be able to read a small Apple II SYS file from scratch
and know which lines are 6502 instructions, which lines are assembler
directives, and which addresses are special.

## What you'll learn

- How a ProDOS SYS file is structured on disk and in memory
- The three Merlin32 directives you'll see at the top of every file:
  `ORG`, `TYP`, `DSK`
- `EQU` for giving names to fixed addresses
- The 6502's `LDA` / `STA` / `JSR` / `RTS` / `JMP` instructions in
  context
- The high-bit-ASCII trick the Apple II text screen uses
- Why the program ends with a keypress wait and a `JMP $C600`

## The source, annotated

Open `src/HELLO.S` in your editor and follow along.

### Header directives

```
            ORG   $2000
            TYP   $FF
            DSK   HELLO
```

These three lines aren't 6502 instructions — they're *Merlin32
directives*, instructions to the assembler itself. They never appear
in the assembled output.

- **`ORG $2000`** tells Merlin32 "assume this code runs starting at
  address `$2000`." Every label that follows gets its address computed
  from this base. ProDOS, by convention, loads SYS files at `$2000`
  and `JMP`s to that address — so `$2000` is where our code has to
  expect to be.
- **`TYP $FF`** sets the ProDOS file type to `$FF` (SYS). The
  assembler doesn't directly write this to the ProDOS disk —
  `a2fuse put --type '0xff'` does — but Merlin32 records it in
  `_FileInformation.txt` for tools that read it.
- **`DSK HELLO`** tells Merlin32 to name the binary output file
  `HELLO`. Without this you get `Error, Can't find output file Name`.

### EQUates

```
KBD         EQU   $C000
KBDSTRB     EQU   $C010
COUT        EQU   $FDED
DISKIIBOOT  EQU   $C600
```

`EQU` ("equate") is the assembler's `#define` — a name for a literal
value. None of these become bytes in the output; they're just labels
the assembler substitutes wherever you write `KBD` or `COUT`. The
addresses themselves matter:

- **`$C000`** is the keyboard data register. Reading it returns the
  last key pressed, with bit 7 set if a key is "fresh" (not yet
  acknowledged).
- **`$C010`** is the keyboard strobe. *Any* read or write clears the
  "fresh" bit on `$C000`. That's how you tell the hardware "I saw the
  key."
- **`$FDED`** is `COUT`, a routine in the Apple II monitor ROM that
  prints a character to the screen. You call it via `JSR` after putting
  the character in the accumulator. It handles cursor advance, scroll,
  and special characters like `$8D` (carriage return) for you.
- **`$C600`** is the start of the Disk II controller's ROM in slot 6.
  Jumping there reboots from the floppy. (Hardware in other slots
  lives at `$C700`, `$C500`, etc., one page per slot.)

The `$Cnnn` range is mostly hardware I/O — registers and ROM. The
`$Fnnn` range is the Apple II monitor + Applesoft ROM. Both are
*always there* on every Apple II, which is why the original Apple
documentation hands you long tables of addresses and treats them like
a standard library.

### The program

```
START       LDX   #0
:LOOP       LDA   MSG,X
            BEQ   :WAIT
            ORA   #$80
            JSR   COUT
            INX
            BNE   :LOOP

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JMP   DISKIIBOOT
```

Six instructions, two loops. Let's walk through it.

`LDX #0` loads the X register with the immediate value 0. The `#`
prefix means "the literal number 0," not "the byte at address 0."
Without the `#`, `LDX 0` would mean "load X from the byte at
address `$0000`." This `#` distinction trips up everyone learning
6502 — burn it in early.

`:LOOP` is a *local label*. The colon prefix scopes it to the previous
non-local label (`START`). You can have another `:LOOP` later under a
different routine without conflict.

`LDA MSG,X` loads the accumulator from address `MSG + X`. This is
*absolute-indexed* addressing, one of the 6502's seven core addressing
modes. We'll cover the rest in stage 3.

`BEQ :WAIT` branches to `:WAIT` if the zero flag is set. The previous
`LDA` set the zero flag if it loaded a zero byte — and our message
ends with a zero. So this is "if we just hit the message terminator,
jump to the keyboard wait."

`ORA #$80` ORs the accumulator with `$80`, setting bit 7. This is the
high-bit-ASCII trick. The Apple II's text display uses the top two
bits of each byte to choose a *display mode*:

| Bits 7-6 | Meaning |
|---|---|
| `11` | Normal text (white-on-black) |
| `10` | Normal text (alternate page on IIe) |
| `01` | Flashing text on II/II+; MouseText on IIe |
| `00` | Inverse text (black-on-white) |

Our `MSG` is stored as plain ASCII (`$48` for `H`), bits 7-6 = `00` —
which displays as inverse video. We OR `$80` to force bits 7-6 to `10`,
which is normal text. `COUT` does the same thing internally if you
give it a low-bit char, but seeing the OR makes the convention
explicit.

`JSR COUT` is "jump to subroutine." It pushes the address of the
*next* instruction onto the stack and jumps to `COUT`. When `COUT`
eventually executes `RTS`, the CPU pops that address and resumes.

`INX` increments X. `BNE :LOOP` branches if the zero flag is *clear*
— i.e., if X didn't just wrap from `$FF` back to `$00`. Since our
message is well under 256 bytes, this always re-enters the loop.

The wait loop polls `$C000`. While bit 7 is clear ("no fresh key"),
`BPL` (branch if positive, i.e. bit 7 clear) keeps looping. Once a key
arrives, bit 7 sets, we fall through, `STA KBDSTRB` clears the strobe
so the next key can register, and we `JMP DISKIIBOOT` to reboot.

We don't `RTS` here because there's no caller to return to. ProDOS
loaded us and `JMP`-ed in. The stack pointer is wherever ProDOS left
it, and `RTS` would jump somewhere unhelpful. SYS files are expected
to take over and either run forever or chain to another SYS file.
Rebooting is the simplest "I'm done" gesture.

### The data

```
MSG         ASC   "HELLO, APPLE IIE!"
            DFB   $0D,$00
```

`ASC` emits the literal bytes of an ASCII string. The delimiter pair
matters: Merlin32's `ASC "..."` (double quotes) emits the bytes with
the high bit *cleared* (`$48 $45 $4C...`). `ASC '...'` (single quotes)
emits the bytes with the high bit *set* (`$C8 $C5 $CC...`). We used
double quotes so our loop has to OR `$80` explicitly — that pairing
is intentional, since you can also choose to leave the high bit clear
to get inverse video.

`DFB` ("define byte") emits raw bytes. `$0D` is carriage return
(`COUT` will move the cursor to the next line); `$00` is our message
terminator (what `BEQ :WAIT` was checking for).

## How this becomes a disk

When you run `make PROGRAM=HELLO run`:

1. Merlin32 assembles `src/HELLO.S` to `build/HELLO` — 27 raw bytes,
   no ProDOS metadata of its own.
2. `a2fuse create --bootable dist/WORK.po` builds a fresh ProDOS
   image with the Disk II boot blocks, the `PRODOS` kernel, and
   `BASIC.SYSTEM`.
3. `a2fuse rm dist/WORK.po BASIC.SYSTEM` removes BASIC.SYSTEM so our
   file is the first SYS file in the volume directory.
4. `a2fuse put dist/WORK.po build/HELLO HELLO.SYSTEM --type '0xff'
   --aux-type '0x2000'` writes the raw bytes onto the image as a SYS
   file (`$FF`) whose load address is recorded as `$2000` (its
   "auxiliary type").
5. MAME boots the image. The Apple IIe ROM reads block 0 of the disk
   via the slot-6 Disk II ROM at `$C600`. Block 0 contains code that
   loads the rest of the ProDOS boot blocks and then the kernel.
6. The ProDOS kernel scans the volume directory, finds `HELLO.SYSTEM`
   as the first `SYS` file, loads it at the aux address `$2000`, and
   `JMP`s to `$2000`.
7. Our `START` label is at `$2000` (because `ORG $2000` and `START`
   is the first thing). Off we go.

The aux type *is* the load address. Get them out of sync — say, you
`ORG $6000` but tell `a2fuse` `--aux-type '0x2000'` — and ProDOS will
load your bytes at `$2000`, jump to `$2000`, and execute whatever
happens to be there. It'll almost always crash.

## Exercises

Edit `src/HELLO.S` and rebuild with `make PROGRAM=HELLO run` (which
verifies ROMs with `roms-check` first). After each exercise, run it
in MAME to see the change.

1. **Change the greeting.** Replace `HELLO, APPLE IIE!` with something
   else. Keep it ASCII, ≤ 39 chars (so it fits a line). What happens
   if you forget the `$00` terminator at the end?
2. **Add a second line.** After the first message, print
   `BUILT WITH MERLIN32`. Hint: `$0D` is the carriage return — what
   does `COUT` do with it? You'll need a second `MSG` block (call it
   `MSG2`), a second print loop, and a second `BEQ` to know when to
   stop.
3. **Print the message in inverse video.** Remove the `ORA #$80`
   instruction. What changes? Now switch the `ASC "..."` delimiter
   from `"..."` to `'...'`. What does that change? Now you've seen
   both halves of the high-bit-ASCII trick.

Worked solutions are in [SOLUTIONS.md](SOLUTIONS.md). Try each
exercise yourself first — even if it's a one-line change, doing it
will lock the concept in better than reading my version.

## Cheat sheet for stage 1

Things to remember when you reach for them in later stages.

| Want to... | Use |
|---|---|
| Set assembled origin | `ORG $xxxx` |
| Set ProDOS file type | `TYP $xx` (records to `_FileInformation.txt`) |
| Name the output binary | `DSK NAME` |
| Define a constant | `LABEL EQU value` |
| Plain ASCII bytes | `ASC "text"` |
| ASCII with high bit set | `ASC 'text'` |
| Raw bytes | `DFB $xx,$yy,...` |
| Print a char | `LDA char` then `JSR COUT` (high bit set!) |
| Wait for key | `LDA $C000 : BPL backwards` |
| Acknowledge key | `STA $C010` |
| Reboot the disk | `JMP $C600` |
