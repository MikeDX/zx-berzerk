# Berzerk ZX Spectrum
#
# Targets:
#   make / make run       remapped arcade host → build/berzerk.sna + ZEsarUX
#   make spectrum-asm     ref/berzerk.asm → src/arcade/berzerk.asm
#   make headless         arcade-map trace (validation)
#   make shell / run-shell  Phase-1 hand-ported shell
#   make clean

PROJECT     := berzerk
BUILD       := build
HOST_SRC    := src/arcade/host.asm
SHELL_SRC   := src/main.asm

SJASMPLUS   ?= $(firstword \
                $(wildcard $(CURDIR)/tools/bin/sjasmplus) \
                $(shell command -v sjasmplus 2>/dev/null))

ZESARUX     ?= $(firstword \
                $(wildcard /Applications/Games/zesarux.app/Contents/MacOS/zesarux) \
                $(wildcard /Applications/zesarux.app/Contents/MacOS/zesarux) \
                $(shell command -v zesarux 2>/dev/null))

MACHINE     ?= 48k
SNA         := $(BUILD)/$(PROJECT).sna
TAP         := $(BUILD)/$(PROJECT).tap
LST         := $(BUILD)/$(PROJECT).lst
SYM         := $(BUILD)/$(PROJECT).sym

SHELL_SNA   := $(BUILD)/shell.sna
SHELL_TAP   := $(BUILD)/shell.tap

.PHONY: all assemble run tap clean check-tools spectrum-asm headless headless-trace \
	shell run-shell convert

all: assemble

assemble: check-tools spectrum-asm $(SNA) $(TAP)
	@test -x tools/.venv/bin/python || { \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	tools/.venv/bin/python tools/smoke_sna.py 100000

spectrum-asm:
	python3 tools/emit_spectrum_asm.py -o src/arcade/berzerk.asm --map-inc src/arcade/mem_map.inc

headless:
	@test -x tools/.venv/bin/python || { \
	  echo "creating tools/.venv + z80…"; \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	tools/.venv/bin/python tools/headless_berzerk.py --insns 200000

headless-trace:
	@test -x tools/.venv/bin/python || { \
	  echo "creating tools/.venv + z80…"; \
	  python3 -m venv tools/.venv && tools/.venv/bin/pip install -q z80; }
	mkdir -p $(BUILD)
	tools/.venv/bin/python tools/headless_berzerk.py --insns 1000000 --json $(BUILD)/arcade_access.json

check-tools:
	@test -n "$(SJASMPLUS)" || { \
	  echo "error: sjasmplus not found. Place a binary at tools/bin/sjasmplus or install on PATH."; \
	  exit 1; }
	@test -x "$(SJASMPLUS)" || { echo "error: $(SJASMPLUS) is not executable"; exit 1; }

$(BUILD)/.dir:
	mkdir -p $(BUILD)
	@touch $@

$(SNA) $(TAP): $(HOST_SRC) \
	src/arcade/mem_map.inc src/arcade/berzerk.asm \
	src/arcade/hooks.asm src/arcade/blit.asm \
	src/zx/screen.asm src/zx/input.asm \
	tools/sjasm/BasicLib.asm $(BUILD)/.dir
	$(SJASMPLUS) --nologo --fullpath \
	  --lst=$(LST) --sym=$(SYM) \
	  -i$(CURDIR) \
	  $(HOST_SRC)
	@test -f $(SNA) && test -f $(TAP)
	@echo "built $(SNA) $(TAP)"

run: assemble
	@test -n "$(ZESARUX)" || { \
	  echo "error: ZEsarUX not found. Install from https://github.com/chernandezba/zesarux"; \
	  exit 1; }
	@echo "launching $(ZESARUX) $(SNA)"
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --snap "$(CURDIR)/$(SNA)"

tap: assemble
	@test -n "$(ZESARUX)" || { echo "error: ZEsarUX not found."; exit 1; }
	@echo "launching $(ZESARUX) $(TAP)"
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --tape "$(CURDIR)/$(TAP)"

# ---- Phase-1 hand-ported shell (optional) ---------------------------------
shell: check-tools $(SHELL_SNA) $(SHELL_TAP)

$(SHELL_SNA) $(SHELL_TAP): $(SHELL_SRC) \
	src/zx/screen.asm src/zx/input.asm \
	src/game/consts.asm src/game/vars.asm src/game/tables.asm src/game/romdata.asm \
	src/game/draw.asm src/game/pattern.asm src/game/util.asm src/game/entity.asm src/game/maze.asm \
	src/game/bolts.asm src/game/player.asm src/game/robots.asm src/game/otto.asm \
	src/game/hud.asm src/game/game.asm \
	tools/sjasm/BasicLib.asm $(BUILD)/.dir
	$(SJASMPLUS) --nologo --fullpath \
	  --lst=$(BUILD)/shell.lst --sym=$(BUILD)/shell.sym \
	  -i$(CURDIR) \
	  $(SHELL_SRC)
	@test -f $(SHELL_SNA) && test -f $(SHELL_TAP)
	@echo "built $(SHELL_SNA) $(SHELL_TAP)"

run-shell: shell
	@test -n "$(ZESARUX)" || { echo "error: ZEsarUX not found"; exit 1; }
	@"$(ZESARUX)" --noconfigfile --machine $(MACHINE) --snap "$(CURDIR)/$(SHELL_SNA)"

convert:
	python3 tools/convert_ref.py --emit src/arcade
	python3 tools/convert_ref.py src/game/romdata.asm

clean:
	rm -rf $(BUILD)
