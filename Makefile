# Kalman filter ASIC -- common tasks (`make help`).
#
# Simulation and lint need Icarus Verilog and/or Verilator plus Yosys on PATH
# (e.g. OSS CAD Suite).  The physical flow and the power analysis need
# LibreLane 3 / OpenSTA; point LIBRELANE and STA at however you start them,
# for example the extracted LibreLane AppImage:
#   LL=$HOME/tools/librelane/squashfs-root/AppRun
#   make flow LIBRELANE="$LL -- librelane"
#   make power STA="$LL -- sta"

PYTHON    ?= .venv/bin/python
LIBRELANE ?= librelane
STA       ?= sta
PDK       ?= ihp-sg13g2
RUN_TAG   ?= main
SIM       ?= icarus

RTL      := rtl/kf_top.v rtl/kf_rom.v rtl/kf_regfile.v rtl/kf_rdport.v rtl/kf_booth.v rtl/kf_mul.v \
            rtl/kf_dot.v rtl/kf_rcp.v rtl/kf_add.v rtl/kf_prefix.v rtl/kf_clkgate.v
FLOW_DIR := flow/$(PDK)
RUN_DIR  := $(FLOW_DIR)/runs/$(RUN_TAG)

.PHONY: help venv rom lint test test-verilator test-long synth flow summary gls equiv power clean

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
	@echo "make power           activity-based power of the final netlist of $(RUN_DIR)"
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

power:
	STA="$(STA)" $(PYTHON) flow/power.py --breakdown $(RUN_DIR)

clean:
	rm -rf build
