"""3MF writer. Each part is its own object with its own colour and extruder.

write_3mf(path, name, parts) where parts = [(part_name, trimesh.Trimesh, extruder, hex_colour), ...]

One mesh painted with per-triangle colours is what slicers were opening as a single
uniform colour. Separate <object> entries are what PrusaSlicer, OrcaSlicer and
Bambu Studio assign to different filaments:

  * 3MF core basematerials: one display colour per object
  * Metadata/Slic3r_PE_model.config: PrusaSlicer extruder per object
  * Metadata/model_settings.config + project_settings.config: Orca / Bambu
    extruder and the two filament colours (multi-material on)
"""
import json
import zipfile
import numpy as np

CT = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="config" ContentType="text/xml"/>
</Types>"""
RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>"""
MODEL_RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/Metadata/model_settings.config" Id="rel-1" Type="http://schemas.bambulab.com/package/2021/model-settings"/>
 <Relationship Target="/Metadata/project_settings.config" Id="rel-2" Type="http://schemas.bambulab.com/package/2021/project-settings"/>
</Relationships>"""


def _esc(s):
    return str(s).replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;")


def _hex(col):
    c = col.strip()
    if not c.startswith("#"):
        c = "#" + c
    return c.upper()


def write_3mf(path, name, parts, offset_xy=(10.0, 10.0)):
    allv = np.vstack([m.vertices for _, m, _, _ in parts])
    shift = np.array([offset_xy[0] - allv[:, 0].min(), offset_xy[1] - allv[:, 1].min(), -allv[:, 2].min()])
    # One basematerial per part, in part order, so object pindex == extruder slot - 1.
    mats = []
    objects = []
    prusa = ['<?xml version="1.0" encoding="UTF-8"?>', "<config>"]
    bambu_objects = []
    instances = []
    for i, (pn, m, ext, col) in enumerate(parts):
        oid = i + 2  # 1 is the basematerials resource
        col = _hex(col)
        mats.append((pn, col))
        v = m.vertices + shift
        f = m.faces
        vs = "\n".join(f'     <vertex x="{a:.4f}" y="{b:.4f}" z="{c:.4f}"/>' for a, b, c in v)
        ts = "\n".join(
            f'     <triangle v1="{a}" v2="{b}" v3="{c}" pid="1" p1="{i}"/>' for a, b, c in f)
        objects.append(f"""  <object id="{oid}" type="model" name="{_esc(pn)}" pid="1" pindex="{i}">
   <mesh>
    <vertices>
{vs}
    </vertices>
    <triangles>
{ts}
    </triangles>
   </mesh>
  </object>""")
        last = max(0, len(f) - 1)
        prusa += [
            f' <object id="{oid}" instances_count="1">',
            f'  <metadata type="object" key="name" value="{_esc(pn)}"/>',
            f'  <metadata type="object" key="extruder" value="{int(ext)}"/>',
            f'  <volume firstid="0" lastid="{last}">',
            f'   <metadata type="volume" key="name" value="{_esc(pn)}"/>',
            '   <metadata type="volume" key="volume_type" value="ModelPart"/>',
            f'   <metadata type="volume" key="extruder" value="{int(ext)}"/>',
            '   <metadata type="volume" key="matrix" value="1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1"/>',
            "  </volume>",
            " </object>",
        ]
        bambu_objects.append(f"""  <object id="{oid}">
    <metadata key="name" value="{_esc(pn)}"/>
    <metadata key="extruder" value="{int(ext)}"/>
    <part id="{oid}" subtype="normal_part">
      <metadata key="name" value="{_esc(pn)}"/>
      <metadata key="matrix" value="1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1"/>
      <metadata key="extruder" value="{int(ext)}"/>
      <mesh_stat edges_fixed="0" degenerate_facets="0" facets_removed="0" facets_reversed="0" backwards_edges="0"/>
    </part>
  </object>""")
        instances.append(f"""    <model_instance>
      <metadata key="object_id" value="{oid}"/>
      <metadata key="instance_id" value="0"/>
      <metadata key="identify_id" value="{100 + oid}"/>
    </model_instance>""")
    prusa += ["</config>"]
    colours = [c for _, c in mats]
    # Two slots minimum so a slicer that reads this project enables multi-material.
    while len(colours) < 2:
        colours.append("#F2F2F2")
    project = {
        "filament_colour": colours,
        "filament_type": ["PETG"] * len(colours),
        "filament_vendor": ["Generic"] * len(colours),
        "filament_diameter": ["1.75"] * len(colours),
        "filament_density": ["1.27"] * len(colours),
        "filament_cost": ["20"] * len(colours),
        "filament_settings_id": ["Generic PETG"] * len(colours),
        "extruder_colour": colours,
    }
    model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:slic3rpe="http://schemas.slic3r.org/3mf/2017/06">
 <metadata name="Title">{_esc(name)}</metadata>
 <metadata name="Designer">The Filament Falcon (github.com/whyvas/filament-falcon)</metadata>
 <metadata name="Application">filament-falcon cad/tools/build.py</metadata>
 <metadata name="slic3rpe:Version3mf">1</metadata>
 <resources>
  <basematerials id="1">
{chr(10).join(f'   <base name="{_esc(pn)}" displaycolor="{col}"/>' for pn, col in mats)}
  </basematerials>
{chr(10).join(objects)}
 </resources>
 <build>
{chr(10).join(f'  <item objectid="{i + 2}" transform="1 0 0 0 1 0 0 0 1 0 0 0" printable="1"/>' for i in range(len(parts)))}
 </build>
</model>
"""
    bambu = f"""<?xml version="1.0" encoding="UTF-8"?>
<config>
{chr(10).join(bambu_objects)}
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value="{_esc(name)}"/>
    <metadata key="locked" value="false"/>
    <metadata key="filament_map_mode" value="Auto For Flush"/>
{chr(10).join(instances)}
  </plate>
  <assemble>
{chr(10).join(f'   <assemble_item object_id="{i + 2}" instance_id="0" transform="1 0 0 0 1 0 0 0 1 0 0 0" offset="0 0 0"/>' for i in range(len(parts)))}
  </assemble>
</config>
"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT)
        z.writestr("_rels/.rels", RELS)
        z.writestr("3D/_rels/3dmodel.model.rels", MODEL_RELS)
        z.writestr("3D/3dmodel.model", model)
        z.writestr("Metadata/Slic3r_PE_model.config", "\n".join(prusa) + "\n")
        z.writestr("Metadata/model_settings.config", bambu)
        z.writestr("Metadata/project_settings.config", json.dumps(project, indent=1) + "\n")
