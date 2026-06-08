# Stage 6 solutions

## 1. Wrap-around movement

Replace each `BEQ :WAIT` in the direction handlers with a wrap.

```
:L          LDX   COL
            BNE   :L_OK
            LDA   #MAX_COL
            STA   COL
            JMP   :MOVED
:L_OK       DEC   COL
            JMP   :MOVED

:R          LDX   COL
            CPX   #MAX_COL
            BNE   :R_OK
            LDA   #0
            STA   COL
            JMP   :MOVED
:R_OK       INC   COL
            JMP   :MOVED
```

Same pattern for `:U` and `:D`. The '@' now teleports off the right
edge and reappears on the left, etc. Useful for games like Pac-Man.

## 2. Walls

Add a "wall lookup" function: given a candidate (row, col), return
true if it's a wall. For a single column of wall at COL=10:

```
* IN:  candidate COL in X, ROW in Y
* OUT: A = $FF if wall, $00 if clear
IS_WALL     CPX   #10
            BNE   :CLR
            LDA   #$FF
            RTS
:CLR        LDA   #0
            RTS
```

Then in each handler, compute the candidate, check, and conditionally
commit:

```
:L          LDX   COL
            BEQ   :WAIT
            DEX               ;candidate
            LDY   ROW
            STX   :TMPX
            JSR   IS_WALL
            BNE   :WAIT       ;blocked
            LDX   :TMPX
            STX   COL
            JMP   :MOVED
:TMPX       DFB   0
```

For a more flexible wall layout — a whole map — store the map in
memory as 24 bytes of bitmasks (one bit per col) and look up the
bit. That's enough for a maze game.

For *displayed* walls, you'd also want to plot a wall character
(`#` say) at each wall cell at startup so the player can see what's
impassable.

## 3. Pickup

Place a `$` at a fixed spot (cols 5, row 8). On every move, after
updating `COL`/`ROW` but before drawing '@', read the screen byte
at the new position. If it's `$`+$80, the player just walked over
the pickup.

```
* At init, after HOME:
            LDA   #8
            JSR   BASCALC
            LDY   #5
            LDA   #'$'+$80
            STA   (BASL),Y

* In :MOVED, after erase and step bump, before redraw:
            LDA   ROW
            JSR   BASCALC
            LDY   COL
            LDA   (BASL),Y
            CMP   #'$'+$80
            BNE   :NO_PICKUP
            JSR   GOT_IT
:NO_PICKUP  JMP   :LOOP

GOT_IT      LDA   #22
            JSR   BASCALC
            LDY   #15
            LDX   #0
:GL         LDA   GOTMSG,X
            BEQ   :GD
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :GL
:GD         RTS

GOTMSG      ASC   "GOT IT!"
            DFB   $00
```

`LDA (BASL),Y` reads from screen memory. The Apple II text page is
fully readable; whatever character is there comes back. That's the
key technique — the screen is your "world map" for cheap.

For multiple pickups, scatter several `$` characters at init and
let the same "step on $" test handle all of them. Add a pickup
counter; when it hits the total, print "YOU WIN!"

This pattern (use the screen as the world model) is how Rogue,
ZZT, and many other 80s games stored their levels. It's free
graphics + free collision detection in one.
