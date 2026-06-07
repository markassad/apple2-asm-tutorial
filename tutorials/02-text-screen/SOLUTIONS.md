# Stage 2 solutions

## 1. Border with `*`

Two passes: horizontal edges (full top and bottom rows), vertical
edges (column 0 and 39 of each middle row).

```
START       JSR   HOME

* Top row: cols 0..39 with '*'
            LDA   #0
            JSR   BASCALC
            LDY   #0
            LDA   #'*'+$80
:TOP        STA   (BASL),Y
            INY
            CPY   #40
            BNE   :TOP

* Bottom row: cols 0..39 with '*'
            LDA   #23
            JSR   BASCALC
            LDY   #0
            LDA   #'*'+$80
:BOT        STA   (BASL),Y
            INY
            CPY   #40
            BNE   :BOT

* Left and right edges of rows 1..22
            LDA   #1
            STA   ROW
:SIDES      LDA   ROW
            JSR   BASCALC
            LDA   #'*'+$80
            LDY   #0
            STA   (BASL),Y
            LDY   #39
            STA   (BASL),Y
            INC   ROW
            LDA   ROW
            CMP   #23
            BNE   :SIDES

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT
```

You'd factor the `* into corner` boilerplate into a subroutine
later — that's stage 4's topic.

## 2. Row numbers

Two-digit decimal needs a divide-by-10. The classic 6502 idiom is
repeated subtraction:

```
* IN:  A = number 0..99
* OUT: tens digit in X, ones digit in A
DIV10       LDX   #0
:LOOP       CMP   #10
            BCC   :DONE
            SBC   #10            ;C was set by CMP
            INX
            JMP   :LOOP
:DONE       RTS
```

Wrap that, and then on each row:

```
:ROWLOOP    LDA   ROW
            JSR   BASCALC
            LDA   ROW
            JSR   DIV10           ;X=tens, A=ones
            PHA                   ;save ones for a moment
            TXA
            CLC
            ADC   #'0'
            ORA   #$80
            LDY   #4               ;column where 'R' starts is 0, "ROW " ends at 4
            STA   (BASL),Y         ;tens digit at col 4
            PLA
            CLC
            ADC   #'0'
            ORA   #$80
            INY                    ;col 5
            STA   (BASL),Y
            ...
```

Plus write the literal `"ROW "` to cols 0-3 first. Full version:

```
:ROWLOOP    LDA   ROW
            JSR   BASCALC

            LDY   #0
            LDA   #'R'+$80
            STA   (BASL),Y
            INY
            LDA   #'O'+$80
            STA   (BASL),Y
            INY
            LDA   #'W'+$80
            STA   (BASL),Y
            INY
            LDA   #' '+$80
            STA   (BASL),Y

            LDA   ROW
            JSR   DIV10
            PHA
            TXA
            CLC
            ADC   #'0'
            ORA   #$80
            LDY   #4
            STA   (BASL),Y
            PLA
            CLC
            ADC   #'0'
            ORA   #$80
            LDY   #5
            STA   (BASL),Y

            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :ROWLOOP
```

By stage 4 you'd have a `printat` helper that flattens this to
`printat(row, 0, "ROW NN")` with a single call.

## 3. Write to a screen hole

`STA $0478` writes `'X'+$80` (`$D8`) into address `$0478`. **You will
not see it.** The video hardware skips bytes `$78-$7F` of every
`$80`-aligned page in `$0400-$07FF`.

If you fire up the MAME debugger (`F4` or whatever your build uses)
and inspect `$0478`, you'll see `$D8` sitting there. Memory got
written; the display ignored it.

Try writing to `$0478`, `$04F8`, `$0578`, etc. — all are screen
holes. Try `$047F` too (also a hole). Try `$0470` (col 31 of row 14
in interleaved space) — that's *visible*, not a hole.

This is what makes the screen holes useful for slot cards: a
peripheral can stash 8 bytes of working memory inside the text page
without interfering with anything the user can see. The Disk II
controller, for example, parks the current track number and a few
other status bytes in slot 6's hole bytes while reading or writing
a disk. If your code uses screen holes for its own state, you have
to either avoid disk I/O or save and restore them.

`STA $0479` lands in slot 2's hole byte for that `$80`-aligned page.
Same invisibility. If you had a real slot 2 card installed, you'd be
stomping its state — but the Apple IIe MAME driver doesn't put
anything in slot 2 by default.
