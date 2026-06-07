# Stage 1 solutions

## 1. Change the greeting

Trivial — replace the string. The forgotten-terminator question is the
interesting half.

```
MSG         ASC   "WELCOME TO APPLE II ASM"
            DFB   $0D,$00
```

**If you omit the `$00`:** the loop never sees a zero byte at `MSG`'s
end and keeps reading past it. It prints whatever happens to be in
memory after the message — typically garbage, then eventually a `$00`
byte somewhere in the unused part of the image where the loop
finally terminates. On a fresh image the unused bytes are zeros so
you'd usually be fine, but it's accidental: the loop's contract is
"the message is null-terminated," not "the assembler zero-pads for
us."

## 2. Add a second line

The cleanest approach is to lift the print loop into a small
subroutine and call it twice with different message pointers — but
that needs zero-page indirect addressing, which we haven't covered
yet. The straightforward fix duplicates the loop:

```
START       LDX   #0
:LOOP1      LDA   MSG,X
            BEQ   :NEXT
            ORA   #$80
            JSR   COUT
            INX
            BNE   :LOOP1

:NEXT       LDX   #0
:LOOP2      LDA   MSG2,X
            BEQ   :WAIT
            ORA   #$80
            JSR   COUT
            INX
            BNE   :LOOP2

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JMP   DISKIIBOOT

MSG         ASC   "HELLO, APPLE IIE!"
            DFB   $0D,$00
MSG2        ASC   "BUILT WITH MERLIN32."
            DFB   $0D,$00
```

About `$0D`: `COUT` interprets it as carriage return, which on the
Apple II also implies line feed (move to start of *next* line). So
the first `DFB $0D` in `MSG` is what gets us a clean line break before
the second message starts. Without it, the two lines would butt up
against each other.

Stage 4 will introduce subroutines properly, at which point you'll
rewrite this as a single `PRINT` routine taking a pointer.

## 3. Inverse video

**Removing `ORA #$80`:** the bytes of `MSG` (`$48`, `$45`, ...) get
written to the screen with bits 7-6 = `00`, which is the *inverse*
display attribute. You see "HELLO, APPLE IIE!" in black-on-white
instead of white-on-black.

**Switching to single quotes:** `ASC 'HELLO, APPLE IIE!'` emits
`$C8 $C5 $CC ...` — bits 7-6 = `11`, normal text. Now even without
`ORA #$80`, the message displays normally:

```
* No ORA #$80 needed any more
:LOOP       LDA   MSG,X
            BEQ   :WAIT
            JSR   COUT
            INX
            BNE   :LOOP
...
MSG         ASC   'HELLO, APPLE IIE!'
            DFB   $0D,$00
```

Both work, but the `ORA #$80` style is more common in real Apple II
code because messages are often built up dynamically (read from a
file, concatenated, etc.) and forcing the high bit at print time is
easier than ensuring every byte source produces the right delimiter.

If you want a mix — some chars inverse, some normal — store them
literally in the data and let `COUT` pass each byte through. `COUT`
inspects bit 7 of the char itself and uses that as the attribute.

For full inverse video without the `ORA`, you can also write directly
to screen memory (stage 2's topic) and set the bit pattern you want
per-character.
