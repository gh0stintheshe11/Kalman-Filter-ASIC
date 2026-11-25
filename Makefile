# Kalman filter ASIC -- common tasks (`make help`).
#
# Simulation and lint need Icarus Verilog and/or Verilator plus Yosys on PATH
# (e.g. OSS CAD Suite; `make lec` also its yosys-abc).  The physical
# flows, the power analysis and the IHP signoff decks need LibreLane 3
# (OpenROAD/OpenSTA, KLayout); set LL to however you start its tools, for
# example the extracted LibreLane AppImage:
#   make flow LL="$HOME/tools/librelane/squashfs-root/AppRun --"
# The IHP decks are taken from the PDK that LibreLane uses (PDK_ROOT/PDK, or
# LibreLane's ciel cache).

PYTHON    ?= .venv/bin/python
LL        ?=
LIBRELANE ?= $(LL) librelane
STA       ?= $(LL) sta
KLAYOUT_PYTHON ?= $(LL) python3
PDK       ?= ihp-sg13g2
RUN_TAG   ?= main
SIM       ?= icarus
JOBS      ?= 4
PDK_DIR   ?= $(if $(PDK_ROOT),$(PDK_ROOT)/$(PDK),$(lastword $(sort $(wildcard $(HOME)/.ciel/ciel/$(PDK)/versions/*/$(PDK)))))

RTL      := rtl/kf_top.v rtl/kf_rom.v rtl/kf_regfile.v rtl/kf_rdport.v rtl/kf_booth.v rtl/kf_mul.v \
            rtl/kf_dot.v rtl/kf_rcp.v rtl/kf_add.v rtl/kf_prefix.v rtl/kf_clkgate.v
FLOW_DIR := flow/$(PDK)
RUN_DIR  := $(FLOW_DIR)/runs/$(RUN_TAG)
CHIP_DIR := flow/chip
CHIP_RUN := $(CHIP_DIR)/runs/$(RUN_TAG)
KLAYOUT_ENV = PYTHONPATH=$(CURDIR)/build/pylib KLAYOUT_PATH=$(PDK_DIR)/libs.tech/klayout

.PHONY: help venv rom lint test test-verilator test-long synth flow summary gls equiv lvs lec ir power \
        chip chip-summary chip-gls chip-lec chip-drc chip-shorts chip-ir pinout render bondpad clean

help:
	@echo "make venv            create .venv with the Python tooling (uses uv)"
	@echo "make rom             assemble fw/kf_2d.s into rtl/kf_rom.v"
	@echo "make lint            Verilator -Wall lint + Yosys structural checks"
	@echo "make test            model, unit, chip and random-program tests (SIM=icarus|verilator)"
	@echo "make test-long       5000-iteration RTL regression"
	@echo "make synth           quick generic Yosys synthesis with statistics"
	@echo "make flow            RTL-to-GDS with LibreLane on $(PDK) -> $(RUN_DIR)"
	@echo "make summary         signoff table of $(RUN_DIR)"
	@echo "make gls [SDF=1]     gate-level simulation of the final netlist of $(RUN_DIR)"
	@echo "make equiv           prove the cell-level read port equal to rtl/kf_rdport.v"
	@echo "make lvs             IHP KLayout LVS deck on the core macro (transistor level)"
	@echo "make lec             prove the final netlist of $(RUN_DIR) equivalent to the RTL"
	@echo "make ir              static IR drop of the core macro, every net switching 20 %"
	@echo "make power           activity-based power of the final netlist of $(RUN_DIR)"
	@echo "make chip            the whole die with LibreLane's Chip flow -> $(CHIP_RUN)"
	@echo "make chip-gls [SDF=1] the chip's gate-level netlist through its pads"
	@echo "make chip-lec        prove the chip's final netlist equivalent to the RTL"
	@echo "make chip-drc        IHP DRC deck on the chip GDS: FEOL, BEOL, density, antenna, extra rules"
	@echo "make chip-shorts     pad ring on the full chip GDS: shorts, opens, I/O cell pins (KLayout)"
	@echo "make chip-ir         static IR drop of the chip, supply at the pads, 20 % activity"
	@echo "make pinout          pinout/bonding diagram and pad table from the chip DEF"
	@echo "make render          layout images of the macro and the chip (docs/img)"
	@echo "make bondpad         regenerate the bond pad (flow/chip/bondpad_70x70.gds/.lef)"
	@echo "make clean           remove build/"

venv:
	uv venv .venv --python 3.13 --managed-python
	uv pip install --python $(PYTHON) -e ".[dev]"

rom: rtl/kf_rom.v

rtl/kf_rom.v: fw/kf_2d.s kfasic/asm.py
	$(PYTHON) -m kfasic.asm $< --verilog $@ --hex build/kf_2d.hex --listing build/kf_2d.lst

lint: rtl/kf_rom.v
	verilator --lint-only -Wall --top-module kf_top $(RTL)
	yosys -q -p "read_verilog $(RTL); synth -top kf_top -flatten; check -assert"

test: rtl/kf_rom.v
	SIM=$(SIM) $(PYTHON) -m pytest -m "not slow"

test-verilator:
	$(MAKE) test SIM=verilator

test-long: rtl/kf_rom.v
	SIM=$(SIM) $(PYTHON) -m pytest -m slow

synth: rtl/kf_rom.v
	@mkdir -p build
	yosys -q -p "read_verilog $(RTL); synth -top kf_top -flatten; tee -o build/synth_stat.txt stat"
	@cat build/synth_stat.txt

flow: rtl/kf_rom.v
	cd $(FLOW_DIR) && $(LIBRELANE) --pdk $(PDK) --run-tag $(RUN_TAG) --overwrite config.yaml

summary:
	$(PYTHON) flow/summary.py $(RUN_DIR)

# The netlist and the PDK cell models come from the run's resolved config.
# SDF=1 back-annotates the delays of the typical corner (or SDF_CORNER, e.g.
# nom_fast_1p32V_m40C for the shortest paths) and runs at the run's clock
# period: a dynamic check of the clock gating, resets and hold paths.
RUN_CFG = $(PYTHON) -c "import json, sys; c = json.load(open('$(RUN_DIR)/resolved.json')); print(eval(sys.argv[1]))"
SDF_CORNER ?= $$($(RUN_CFG) "c['DEFAULT_CORNER']")
gls:
	@test -f $(RUN_DIR)/resolved.json || { echo "no run in $(RUN_DIR); run 'make flow' first"; exit 1; }
	GL_NETLIST=$(RUN_DIR)/final/nl/kf_top.nl.v \
	GL_CELLS=$$($(RUN_CFG) "':'.join(c['CELL_VERILOG_MODELS'])") \
	$(if $(SDF),GL_SDF=$(RUN_DIR)/final/sdf/$(SDF_CORNER)/kf_top__$(SDF_CORNER).sdf \
	KF_CLK_NS=$$($(RUN_CFG) "c['CLOCK_PERIOD']")) \
	SIM=icarus $(PYTHON) -m pytest tb -k kf_top -m "not slow"

# The PDK cell models come from a run's resolved config.
equiv:
	@test -f $(RUN_DIR)/resolved.json || { echo "no run in $(RUN_DIR); run 'make flow' first"; exit 1; }
	$(PYTHON) $(FLOW_DIR)/equiv_rdport.py \
		$$($(PYTHON) -c "import json; print(json.load(open('$(RUN_DIR)/resolved.json'))['CELL_VERILOG_MODELS'][0])")

# IHP's KLayout LVS deck, transistor level, on the core macro (the chip's
# LVS is the flow's Netgen LVS: the deck does not match the IHP I/O cells).
lvs: build/pylib/docopt.py
	@test -f $(RUN_DIR)/final/gds/kf_top.gds || { echo "no GDS in $(RUN_DIR); run 'make flow' first"; exit 1; }
	$(KLAYOUT_ENV) $(KLAYOUT_PYTHON) flow/lvs.py $(RUN_DIR)/final/gds/kf_top.gds \
		$(RUN_DIR)/final/pnl/kf_top.pnl.v kf_top --pdk $(PDK_DIR) --workdir build/lvs

# Static IR drop with OpenROAD's PDNSim at a stated activity (flow/irdrop.py);
# for the chip with the supply at the pads.
ir:
	@test -f $(RUN_DIR)/final/odb/kf_top.odb || { echo "no run in $(RUN_DIR); run 'make flow' first"; exit 1; }
	OPENROAD="$(LL) openroad" $(PYTHON) flow/irdrop.py $(RUN_DIR)

chip-ir:
	@test -f $(CHIP_RUN)/final/odb/kf_chip.odb || { echo "no run in $(CHIP_RUN); run 'make chip' first"; exit 1; }
	OPENROAD="$(LL) openroad" $(PYTHON) flow/irdrop.py $(CHIP_RUN)

# Needs Yosys and yosys-abc on PATH (OSS CAD Suite).
lec:
	@test -f $(RUN_DIR)/resolved.json || { echo "no run in $(RUN_DIR); run 'make flow' first"; exit 1; }
	$(PYTHON) flow/lec.py $(RUN_DIR)

chip-lec:
	@test -f $(CHIP_RUN)/resolved.json || { echo "no run in $(CHIP_RUN); run 'make chip' first"; exit 1; }
	$(PYTHON) flow/lec.py $(CHIP_RUN)

power:
	STA="$(STA)" $(PYTHON) flow/power.py --breakdown $(RUN_DIR)

# ---- the chip ---------------------------------------------------------------
chip: rtl/kf_rom.v
	cd $(CHIP_DIR) && $(LIBRELANE) --pdk $(PDK) --run-tag $(RUN_TAG) --overwrite config.yaml

chip-summary:
	$(PYTHON) flow/summary.py $(CHIP_RUN)

CHIP_CFG = $(PYTHON) -c "import json, sys; c = json.load(open('$(CHIP_RUN)/resolved.json')); print(eval(sys.argv[1]))"
chip-gls:
	@test -f $(CHIP_RUN)/resolved.json || { echo "no run in $(CHIP_RUN); run 'make chip' first"; exit 1; }
	GL_CHIP_NETLIST=$(CHIP_RUN)/final/nl/kf_chip.nl.v \
	GL_CELLS=$$($(CHIP_CFG) "':'.join(c['CELL_VERILOG_MODELS'])") \
	$(if $(SDF),GL_CHIP_SDF=$(CHIP_RUN)/final/sdf/$(SDF_CORNER)/kf_chip__$(SDF_CORNER).sdf \
	KF_CLK_NS=$$($(CHIP_CFG) "c['CLOCK_PERIOD']")) \
	SIM=icarus $(PYTHON) -m pytest tb -k chip

build/pylib/docopt.py:
	uv pip install --target build/pylib docopt

chip-drc: build/pylib/docopt.py
	@test -f $(CHIP_RUN)/final/gds/kf_chip.gds || { echo "no GDS in $(CHIP_RUN); run 'make chip' first"; exit 1; }
	rm -rf build/drc && $(KLAYOUT_ENV) $(KLAYOUT_PYTHON) $(PDK_DIR)/libs.tech/klayout/tech/drc/run_drc.py \
		--path $(CHIP_RUN)/final/gds/kf_chip.gds --topcell kf_chip --run_dir build/drc \
		--antenna --no_recommended --mp $(JOBS) --density_thr $(JOBS)

# What Magic's extraction for the chip LVS cannot see, as it models the I/O
# cells by their LEF abstracts: shorts and opens around the pad ring, on the
# full layout (flow/shorts.py).
chip-shorts:
	@test -f $(CHIP_RUN)/final/gds/kf_chip.gds || { echo "no GDS in $(CHIP_RUN); run 'make chip' first"; exit 1; }
	$(KLAYOUT_PYTHON) flow/shorts.py $(CHIP_RUN)/final/gds/kf_chip.gds $(CHIP_RUN)/final/pnl/kf_chip.pnl.v

pinout:
	$(PYTHON) flow/chip/pinout.py $(CHIP_RUN)/final/def/kf_chip.def --png docs/img/pinout.png

render:
	$(LL) klayout -zz -r flow/render_gds.py -rd gds=$(RUN_DIR)/final/gds/kf_top.gds \
		-rd lyp=$(PDK_DIR)/libs.tech/klayout/tech/sg13g2.lyp -rd out=$(CURDIR)/docs/img/layout.png
	$(LL) klayout -zz -r flow/render_gds.py -rd gds=$(CHIP_RUN)/final/gds/kf_chip.gds \
		-rd lyp=$(PDK_DIR)/libs.tech/klayout/tech/sg13g2.lyp -rd out=$(CURDIR)/docs/img/chip.png

bondpad:
	KLAYOUT_PATH=$(PDK_DIR)/libs.tech/klayout $(LL) klayout -n sg13g2 -zz -r flow/chip/make_bondpad.py \
		-rd out=$(CURDIR)/flow/chip/bondpad_70x70

clean:
	rm -rf build
