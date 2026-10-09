"""Minimal 3MF writer for multi-part, multi-colour objects.

write_3mf(path, name, parts) where parts = [(part_name, trimesh.Trimesh, extruder, hex_colour), ...]

All parts go into ONE object (so slicers keep them aligned as one multi-part object):
  * 3MF core:      one <object> whose triangles carry per-triangle base-material colours
  * PrusaSlicer /  Metadata/Slic3r_PE_model.config splits the object into volumes by
    Orca / Bambu:  triangle range, each with its own name and extruder number.
"""
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


def _esc(s):
    return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;")


def write_3mf(path, name, parts, offset_xy=(10.0, 10.0)):
    allv = np.vstack([m.vertices for _, m, _, _ in parts])
    shift = np.array([offset_xy[0] - allv[:, 0].min(), offset_xy[1] - allv[:, 1].min(), -allv[:, 2].min()])
    mats = []
    for pn, _, _, col in parts:
        if col not in mats:
            mats.append(col)
    vs, ts, cfg_vols = [], [], []
    vbase, tbase = 0, 0
    for pn, m, ext, col in parts:
        v = m.vertices + shift
        f = m.faces
        vs.append("\n".join(f'     <vertex x="{a:.4f}" y="{b:.4f}" z="{c:.4f}"/>' for a, b, c in v))
        pi = mats.index(col)
        ts.append("\n".join(f'     <triangle v1="{a + vbase}" v2="{b + vbase}" v3="{c + vbase}" pid="1" p1="{pi}"/>' for a, b, c in f))
        cfg_vols.append((pn, tbase, tbase + len(f) - 1, ext))
        vbase += len(v)
        tbase += len(f)
    model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
 <metadata name="Title">{_esc(name)}</metadata>
 <metadata name="Designer">The Filament Falcon (github.com/whyvas/filament-falcon)</metadata>
 <metadata name="Application">filament-falcon cad/tools/build.py</metadata>
 <resources>
  <basematerials id="1">
{chr(10).join(f'   <base name="{_esc(parts[[p[3] for p in parts].index(c)][0])}" displaycolor="{c}"/>' for c in mats)}
  </basematerials>
  <object id="2" type="model" name="{_esc(name)}" pid="1" pindex="0">
   <mesh>
    <vertices>
{chr(10).join(vs)}
    </vertices>
    <triangles>
{chr(10).join(ts)}
    </triangles>
   </mesh>
  </object>
 </resources>
 <build>
  <item objectid="2"/>
 </build>
</model>
"""
    cfg = ['<?xml version="1.0" encoding="UTF-8"?>', "<config>", ' <object id="2" instances_count="1">',
           f'  <metadata type="object" key="name" value="{_esc(name)}"/>']
    for pn, a, b, ext in cfg_vols:
        cfg += [f'  <volume firstid="{a}" lastid="{b}">',
                f'   <metadata type="volume" key="name" value="{_esc(pn)}"/>',
                '   <metadata type="volume" key="volume_type" value="ModelPart"/>',
                f'   <metadata type="volume" key="extruder" value="{ext}"/>',
                "  </volume>"]
    cfg += [" </object>", "</config>"]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT)
        z.writestr("_rels/.rels", RELS)
        z.writestr("3D/3dmodel.model", model)
        if len(parts) > 1:
            z.writestr("Metadata/Slic3r_PE_model.config", "\n".join(cfg) + "\n")
