# Berzerk ZX Spectrum
#
# Targets:
#   make        assemble → build/berzerk.tap + build/berzerk.sna
#   make run    assemble, then open snapshot in ZEsarUX
#   make tap    assemble, then open .tap in ZEsarUX
#   make clean  remove build artefacts

PROJECT     := berzerk
BUILD       := build
SRC         := src/main.asm

SJASMPLUS   ?= $(firstword \
                $(wildcard $(CURDIR)/tools/bin/sjasmplus) \
                $(shell command -v sjasmplus 2>/dev/null))

# Prefer a real ZEsarUX binary (Homebrew/cask may live under Applications/Games)
ZESARUX     ?= $(firstword \
                $(wildcard /Applications/Games/zesarux.app/Contents/MacOS/zesarux) \
                $(wildcard /Applications/zesarux.app/Contents/MacOS/zesarux) \
                $(shell command -v zesarux 2>/dev/null))

MACHINE     ?= 48k
SNA         := $(BUILD)/$(PROJECT).sna
TAP         := $(BUILD)/$(PROJECT).tap
LST         := $(BUILD)/$(PROJECT).lst
SYM         := $(BUILD)/$(PROJECT).sym

.PHONY: all assemble run tap clean check-tools

all: assemble

assemble: check-tools $(SNA) $(TAP)

check-tools:
	@test -n "$(SJASMPLUS)" || { \
	  echo "error: sjasmplus not found. Place a binary at tools/bin/sjasmplus or install on PATH."; \
	  exit 1; }
	@test -x "$(SJASMPLUS)" || { echo "error: $(SJASMPLUS) is not executable"; exit 1; }

$(BUILD)/.dir:
	mkdir -p $(BUILD)
	@touch $@

# sjasmplus writes SNA/TAP via directives inside main.asm
$(SNA) $(TAP): $(SRC) \
	src/zx/screen.asm src/zx/input.asm \
	src/game/consts.asm src/game/vars.asm src/game/tables.asm src/game/sprites.asm \
	src/game/draw.asm src/game/util.asm src/game/entity.asm src/game/maze.asm \
	src/game/bolts.asm src/game/player.asm src/game/robots.asm src/game/otto.asm \
	src/game/hud.asm src/game/game.asm \
	tools/sjasm/BasicLib.asm $(BUILD)/.dir
	$(SJASMPLUS) --nologo --fullpath \
	  --lst=$(LST) --sym=$(SYM) \
	  -i$(CURDIR) \
	  $(SRC)
	@test -f $(SNA) && test -f $(TAP)
	@echo "built $(SNA) $(TAP)"

run: assemble
	@test -n "$(ZESARUX)" || { \
	  echo "error: ZEsarUX not found. Install from https://github.com/chernandezba/zesarux"; \
	  exit 1; }
	@echo "launching $(ZESARUX) $(SNA)"
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --snap "$(CURDIR)/$(SNA)"

tap: assemble
	@test -n "$(ZESARUX)" || { \
	  echo "error: ZEsarUX not found."; \
	  exit 1; }
	@echo "launching $(ZESARUX) $(TAP)"
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --tape "$(CURDIR)/$(TAP)"

clean:
	rm -rf $(BUILD)
