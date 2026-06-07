# Apple IIe 6502 assembly workspace.
#
# Tools required on PATH:
#   Merlin32   the assembler
#   a2fuse     ProDOS image creation + file import
#   mame       the apple2e driver (only needed for `make run`)
#
# Layout:
#   src/         Merlin32 sources (*.S)
#   build/       assembled binaries (gitignored)
#   dist/        ProDOS disk images (gitignored)

SHELL       := /bin/bash

# Program being built.  PROGRAM is the source basename (src/$(PROGRAM).S);
# INSTALL_NAME is the filename written onto the ProDOS disk.  Keep TYP and
# ORG in the .S file in sync with FILE_TYPE and LOAD_ADDR here.
#
# A ".SYSTEM" name with FILE_TYPE = $FF makes ProDOS auto-launch the file
# at boot, loading at LOAD_ADDR ($2000 by convention for SYS files).
# Override PROGRAM on the command line to build a different source from
# src/, e.g. `make PROGRAM=HELLO run`.  INSTALL_NAME defaults to
# $(PROGRAM).SYSTEM so SYS files auto-launch at boot.
PROGRAM       := BOUNCE
INSTALL_NAME   = $(PROGRAM).SYSTEM
FILE_TYPE     := 0xff
LOAD_ADDR     := 0x2000

SRC_DIR     := src
BUILD_DIR   := build
DIST_DIR    := dist

SRC         := $(SRC_DIR)/$(PROGRAM).S
BIN         := $(BUILD_DIR)/$(PROGRAM)

VOLUME      := WORK
IMAGE       := $(DIST_DIR)/$(VOLUME).po

MAME_SYS    := apple2e
MAME_ROMS   := $(HOME)/mame/roms
# Per-workspace MAME state directory.  Without these overrides MAME
# splatters cfg/, nvram/, inp/, sta/, snap/, diff/ into the cwd.
MAME_STATE  := .mame-state
MAME_FLAGS  := -rompath $(MAME_ROMS) \
               -cfg_directory $(MAME_STATE)/cfg \
               -nvram_directory $(MAME_STATE)/nvram \
               -input_directory $(MAME_STATE)/inp \
               -state_directory $(MAME_STATE)/sta \
               -snapshot_directory $(MAME_STATE)/snap \
               -diff_directory $(MAME_STATE)/diff \
               -comment_directory $(MAME_STATE)/comments \
               -window -skip_gameinfo

.PHONY: all build install run clean distclean tools-check help

all: install

help:
	@echo "targets:"
	@echo "  make build      assemble $(SRC) -> $(BIN)"
	@echo "  make install    build + (re)create $(IMAGE), put binary on it"
	@echo "  make run        install + boot MAME with the image attached"
	@echo "  make clean      remove $(BUILD_DIR)"
	@echo "  make distclean  remove $(BUILD_DIR) and $(DIST_DIR)"

tools-check:
	@command -v Merlin32 >/dev/null || { echo >&2 "missing Merlin32 on PATH"; exit 1; }
	@command -v a2fuse   >/dev/null || { echo >&2 "missing a2fuse on PATH";   exit 1; }

build: tools-check $(BIN)

# Merlin32 writes its output beside the source, named the same as the
# source minus the .S extension.  We assemble inside build/ so the tree
# stays tidy, then drop the staged source copy and the FileInformation
# index Merlin32 leaves behind.
$(BIN): $(SRC)
	@mkdir -p $(BUILD_DIR)
	@cp $(SRC) $(BUILD_DIR)/$(PROGRAM).S
	@cd $(BUILD_DIR) && Merlin32 -V . $(PROGRAM).S
	@rm -f $(BUILD_DIR)/$(PROGRAM).S $(BUILD_DIR)/_FileInformation.txt
	@test -f $@ || { echo >&2 "Merlin32 did not produce $@"; exit 1; }
	@printf "built %s (%d bytes)\n" "$@" "$$(wc -c < $@)"

# Always rebuild the disk image from scratch so the only SYS file on it
# is the one $(INSTALL_NAME) is currently set to.  Otherwise stale SYS
# files from previous `make PROGRAM=...` runs accumulate and ProDOS
# auto-launches whichever happens to be first in directory order.
.PHONY: image
image: | $(DIST_DIR)
	@rm -f $(IMAGE)
	a2fuse create --name $(VOLUME) --bootable $(IMAGE)
	a2fuse rm $(IMAGE) BASIC.SYSTEM

$(IMAGE): image

install: $(BIN) image
	a2fuse put --force $(IMAGE) $(BIN) $(INSTALL_NAME) --type '$(FILE_TYPE)' --aux-type '$(LOAD_ADDR)'
	@echo
	@a2fuse catalog $(IMAGE)

$(DIST_DIR):
	@mkdir -p $@

run: install roms-check
	@mkdir -p $(MAME_STATE)/cfg $(MAME_STATE)/nvram $(MAME_STATE)/inp \
	          $(MAME_STATE)/sta $(MAME_STATE)/snap $(MAME_STATE)/diff \
	          $(MAME_STATE)/comments
	mame $(MAME_SYS) -flop1 $(IMAGE) $(MAME_FLAGS)

roms-check:
	@command -v mame >/dev/null || { echo >&2 "missing mame on PATH (brew install mame, then install apple2e ROMs)"; exit 1; }
	@mame -rompath $(MAME_ROMS) -verifyroms $(MAME_SYS) >/dev/null 2>&1 || { \
	    echo >&2 "MAME cannot verify '$(MAME_SYS)' ROMs in $(MAME_ROMS)"; \
	    echo >&2 "  run: mame -rompath $(MAME_ROMS) -verifyroms $(MAME_SYS)"; \
	    exit 1; }

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -rf $(DIST_DIR)
