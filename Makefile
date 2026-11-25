# Kalman filter ASIC -- common tasks (`make help`).
#
# Simulation and lint need Icarus Verilog and/or Verilator plus Yosys on PATH
# (e.g. OSS CAD Suite).  The physical flow needs LibreLane 3; point LIBRELANE
# at however you start it, for example the extracted AppImage:
#   make flow LIBRELANE="$$HOME/tools/librelane/squashfs-root/AppRun -- librelane"

PYTHON    ?= .venv/bin/python
LIBRELANE ?= librelane
PDK       ?= ihp-sg13g2
RUN_TAG   ?= main
SIM       ?= icarus

RTL      := rtl/kf_top.v rtl/kf_sequencer.v rtl/kf_rom.v rtl/kf_regfile.v rtl/kf_au.v
FLOW_DIR := flow/$(PDK)
RUN_DIR  := $(FLOW_DIR)/runs/$(RUN_TAG)

.PHONY: help venv rom lint test test-verilator test-long synth flow gls clean

help:
	@echo "make venv            create .venv with the Python tooling (uses uv)"
	@echo "make rom             assemble fw/kf_2d.s into rtl/kf_rom.v"
	@echo "make lint            Verilator -Wall lint + Yosys structural checks"
	@echo "make test            model tests + RTL cocotb tests (SIM=icarus|verilator)"
	@echo "make test-long       5000-iteration RTL regression"
	@echo "make synth           quick generic Yosys synthesis with statistics"
	@echo "make flow            RTL-to-GDS with LibreLane on $(PDK) -> $(RUN_DIR)"
	@echo "make gls             gate-level simulation of the final netlist of $(RUN_DIR)"
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

# The netlist and the PDK cell models come from the run's resolved config.
gls:
	@test -f $(RUN_DIR)/resolved.json || { echo "no run in $(RUN_DIR); run 'make flow' first"; exit 1; }
	GL_NETLIST=$(RUN_DIR)/final/nl/kf_top.nl.v \
	GL_CELLS=$$($(PYTHON) -c "import json; c = json.load(open('$(RUN_DIR)/resolved.json'))['CELL_VERILOG_MODELS']; print(':'.join(c))") \
	SIM=icarus $(PYTHON) -m pytest tb -k kf_top -m "not slow"

clean:
	rm -rf build
