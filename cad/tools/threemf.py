"""Minimal 3MF writer for multi-colour panels and single-colour parts.

write_3mf(path, name, parts) where parts = [(part_name, trimesh.Trimesh, extruder, hex_colour), ...]

One part  -> one mesh <object> with its base material.
Two+ parts -> every part is its OWN mesh <object> (own base material via pid/pindex), and one
  assembly <object> holds them as <components> with identity transforms, so they share the
  exact same coordinates (letters sit in the through-holes of the body).  Build item = the
  assembly.  Slicer metadata pre-assigns the extruders:
  * Bambu Studio / OrcaSlicer: Metadata/model_settings.config - one object, one <part> per
    component (subtype normal_part) with its own extruder -> "two parts in one assembly".
  * PrusaSlicer: Metadata/Slic3r_PE_model.config - PrusaSlicer flattens the components into one
    object; the volumes are given by triangle ranges in component order, each with its extruder.
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
IDENT = "1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1"


def _esc(s):
    return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;")


def _mesh_xml(m, shift):
    v = m.vertices + shift
    vs = "\n".join(f'     <vertex x="{a:.4f}" y="{b:.4f}" z="{c:.4f}"/>' for a, b, c in v)
    ts = "\n".join(f'     <triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in m.faces)
    return f"   <mesh>\n    <vertices>\n{vs}\n    </vertices>\n    <triangles>\n{ts}\n    </triangles>\n   </mesh>"


def write_3mf(path, name, parts, offset_xy=(10.0, 10.0)):
    allv = np.vstack([m.vertices for _, m, _, _ in parts])
    shift = np.array([offset_xy[0] - allv[:, 0].min(), offset_xy[1] - allv[:, 1].min(), -allv[:, 2].min()])
    bases = "\n".join(f'   <base name="{_esc(pn)}" displaycolor="{col}FF"/>' for pn, _, _, col in parts)
    objs = []
    for i, (pn, m, ext, col) in enumerate(parts):
        objs.append(f'  <object id="{i + 2}" type="model" name="{_esc(pn)}" pid="1" pindex="{i}">\n{_mesh_xml(m, shift)}\n  </object>')
    multi = len(parts) > 1
    top = len(parts) + 2 if multi else 2
    if multi:
        comps = "\n".join(f'    <component objectid="{i + 2}"/>' for i in range(len(parts)))
        objs.append(f'  <object id="{top}" type="model" name="{_esc(name)}">\n   <components>\n{comps}\n   </components>\n  </object>')
    model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
 <metadata name="Title">{_esc(name)}</metadata>
 <metadata name="Designer">The Filament Falcon (github.com/whyvas/filament-falcon)</metadata>
 <metadata name="Application">filament-falcon cad/tools/build.py</metadata>
 <resources>
  <basematerials id="1">
{bases}
  </basematerials>
{chr(10).join(objs)}
 </resources>
 <build>
  <item objectid="{top}"/>
 </build>
</model>
"""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT)
        z.writestr("_rels/.rels", RELS)
        z.writestr("3D/3dmodel.model", model)
        if not multi:
            return
        # PrusaSlicer
        cfg = ['<?xml version="1.0" encoding="UTF-8"?>', "<config>", f' <object id="{top}" instances_count="1">',
               f'  <metadata type="object" key="name" value="{_esc(name)}"/>']
        t0 = 0
        for pn, m, ext, _ in parts:
            cfg += [f'  <volume firstid="{t0}" lastid="{t0 + len(m.faces) - 1}">',
                    f'   <metadata type="volume" key="name" value="{_esc(pn)}"/>',
                    '   <metadata type="volume" key="volume_type" value="ModelPart"/>',
                    f'   <metadata type="volume" key="extruder" value="{ext}"/>', "  </volume>"]
            t0 += len(m.faces)
        cfg += [" </object>", "</config>"]
        z.writestr("Metadata/Slic3r_PE_model.config", "\n".join(cfg) + "\n")
        # Bambu Studio / OrcaSlicer
        bb = ['<?xml version="1.0" encoding="UTF-8"?>', "<config>", f'  <object id="{top}">',
              f'    <metadata key="name" value="{_esc(name)}"/>', f'    <metadata key="extruder" value="{parts[0][2]}"/>']
        for i, (pn, m, ext, _) in enumerate(parts):
            bb += [f'    <part id="{i + 2}" subtype="normal_part">', f'      <metadata key="name" value="{_esc(pn)}"/>',
                   f'      <metadata key="matrix" value="{IDENT}"/>', f'      <metadata key="extruder" value="{ext}"/>',
                   f'      <mesh_stat edges_fixed="0" degenerate_facets="0" facets_removed="0" facets_reversed="0" backwards_edges="0"/>',
                   "    </part>"]
        bb += ["  </object>", "</config>"]
        z.writestr("Metadata/model_settings.config", "\n".join(bb) + "\n")
