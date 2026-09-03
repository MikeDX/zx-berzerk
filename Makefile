# Berzerk ZX Spectrum
#
# Targets:
#   make / make run       Phase-1 hand-ported shell
#   make spectrum-asm     ref/berzerk.asm → src/arcade/berzerk.asm (Spectrum map)
#   make headless         arcade-map trace (validation)
#   make arcade           legacy binary relocate + host
#   make run-arcade       boot legacy host in ZEsarUX
#   make convert          regenerate listing artefacts
#   make clean

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

.PHONY: all assemble arcade run run-arcade tap clean check-tools convert smoke-arcade \
	headless headless-trace spectrum-asm

all: assemble

assemble: check-tools $(SNA) $(TAP)

# Primary path: remapped assemblable game from the arcade listing.
spectrum-asm:
	python3 tools/emit_spectrum_asm.py -o src/arcade/berzerk.asm --map-inc src/arcade/mem_map.inc

arcade: check-tools convert-reloc $(BUILD)/arcade.sna $(BUILD)/arcade.tap

# Faithful arcade-map run (docs/PORT.md). Prefer this over binary reloc experiments.
headless:
	@test -x tools/.venv/bin/python || { \
	  echo "creating tools/.venv + z80…"; \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	tools/.venv/bin/python tools/headless_berzerk.py --insns 200000

headless-trace: 
	@test -x tools/.venv/bin/python || { \
	  echo "creating tools/.venv + z80…"; \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	tools/.venv/bin/python tools/headless_berzerk.py --insns 1000000 --json $(BUILD)/arcade_access.json

smoke-arcade: convert-reloc
	@test -x tools/.venv/bin/python || { \
	  echo "creating tools/.venv + z80…"; \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	tools/.venv/bin/python tools/smoke_arcade.py

convert:
	python3 tools/convert_ref.py --emit src/arcade
	python3 tools/convert_ref.py src/game/romdata.asm

convert-reloc: convert
	python3 tools/reloc_rom.py src/arcade

$(BUILD)/arcade.sna $(BUILD)/arcade.tap: src/arcade/host.asm \
	src/arcade/host_mem.inc src/arcade/rom_reloc.asm \
	src/arcade/hooks.asm src/arcade/blit.asm \
	src/zx/screen.asm src/zx/input.asm \
	tools/sjasm/BasicLib.asm $(BUILD)/.dir
	$(SJASMPLUS) --nologo --fullpath \
	  --lst=$(BUILD)/arcade.lst --sym=$(BUILD)/arcade.sym \
	  -i$(CURDIR) \
	  src/arcade/host.asm
	@test -f $(BUILD)/arcade.sna && test -f $(BUILD)/arcade.tap
	@echo "built $(BUILD)/arcade.sna $(BUILD)/arcade.tap"

run-arcade: arcade
	@test -n "$(ZESARUX)" || { echo "error: ZEsarUX not found"; exit 1; }
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --snap "$(CURDIR)/$(BUILD)/arcade.sna"

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
	src/game/consts.asm src/game/vars.asm src/game/tables.asm src/game/romdata.asm \
	src/game/draw.asm src/game/pattern.asm src/game/util.asm src/game/entity.asm src/game/maze.asm \
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
