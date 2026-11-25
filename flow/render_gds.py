# Render a GDS to PNG with KLayout in batch mode:
#   klayout -zz -r flow/render_gds.py -rd gds=in.gds -rd lyp=layers.lyp -rd out=out.png
import pya  # noqa: F821  (provided by KLayout)

gds = globals().get("gds")
lyp = globals().get("lyp")
out = globals().get("out", "layout.png")
size = int(globals().get("size", "1400"))

view = pya.LayoutView()
view.load_layout(gds, True)
if lyp:
    view.load_layer_props(lyp)
view.set_config("background-color", "#101010")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.max_hier()
view.zoom_fit()
view.save_image(out, size, size)
print(f"wrote {out}")
