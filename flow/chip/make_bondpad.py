"""Generate the 70 x 70 um bond pad used by the pad ring (KLayout batch mode).

    KLAYOUT_PATH=$PDK_ROOT/$PDK/libs.tech/klayout \
    klayout -n sg13g2 -zz -r flow/chip/make_bondpad.py -rd out=flow/chip/bondpad_70x70

writes <out>.gds and <out>.lef.  The pad is the PDK's 'bondpad' PCell
(library SG13_dev, square, Metal3 to TopMetal2 with the passivation
opening) with its lower-left corner at the origin, as LibreLane's pad-ring
step expects: it places the pad 70 um outside each I/O cell, where the top
edge of the pad abuts the I/O cell's 'pad' pin (Metal2..TopMetal2 along
the outer edge).  The LEF describes the pad as a COVER macro with one pin
on all five metals.  It has no OBS: the pin already keeps other nets out,
and OBS on the same layers as the pin only make Magic's extraction report
the pin metal as overlapping an obstruction (Checker.IllegalOverlap).
The GDS is written without timestamps, so regenerating it is reproducible.
"""
# pylint: disable=import-error,undefined-variable
import pya

SIZE = 70.0
NAME = "bondpad_70x70"

layout = pya.Layout()
layout.dbu = 0.001
lib = pya.Library.library_by_name("SG13_dev")
decl = lib.layout().pcell_declaration("bondpad")
pcell = layout.add_pcell_variant(lib, decl.id(), {"diameter": f"{SIZE}u", "shape": "square"})
pad = layout.convert_cell_to_static(pcell)        # a plain cell with a unique name
layout.cell(pad).name = f"{NAME}_pcell"
layout.delete_cell(pcell)
top = layout.create_cell(NAME)
half = int(round(SIZE / 2 / layout.dbu))
top.insert(pya.CellInstArray(pad, pya.Trans(half, half)))
bbox = top.dbbox()
assert abs(bbox.left) < 1e-6 and abs(bbox.bottom) < 1e-6, bbox
assert abs(bbox.width() - SIZE) < 1e-6 and abs(bbox.height() - SIZE) < 1e-6, bbox
opts = pya.SaveLayoutOptions()
opts.gds2_write_timestamps = False
layout.write(f"{out}.gds", opts)  # noqa: F821  (out comes from -rd)

metals = ("Metal3", "Metal4", "Metal5", "TopMetal1", "TopMetal2")
rect = f"RECT 0 0 {SIZE:.1f} {SIZE:.1f} ;"
lef = ["VERSION 5.8 ;", "BUSBITCHARS \"[]\" ;", "DIVIDERCHAR \"/\" ;", "",
       f"MACRO {NAME}", "  CLASS COVER ;", "  ORIGIN 0 0 ;", f"  FOREIGN {NAME} 0 0 ;",
       f"  SIZE {SIZE:.1f} BY {SIZE:.1f} ;", "  SYMMETRY X Y R90 ;",
       "  PIN pad", "    DIRECTION INOUT ;", "    USE SIGNAL ;", "    PORT"]
for m in metals:
    lef += [f"      LAYER {m} ;", f"        {rect}"]
lef += ["    END", "  END pad", f"END {NAME}", "", "END LIBRARY", ""]
with open(f"{out}.lef", "w") as f:  # noqa: F821
    f.write("\n".join(lef))
print(f"wrote {out}.gds and {out}.lef")  # noqa: F821
