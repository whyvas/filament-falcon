"""Rough filament estimate from the exported 3MF meshes (trimesh).
printed volume per part = shell + 25 % of the remaining interior,
shell = min(V, surface_area * 1.2 mm)  (3 perimeters x 0.4 mm; same thickness used as a proxy for top/bottom skins).
mass = volume * 1.27 g/cm3 (PETG; PLA 1.24) ; +15 % for purge tower, brim, failed prints."""
import trimesh, glob, os, json
D=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','cad','export','3mf')
qty={'toggle_guard_base':3,'toggle_guard_lid_RED':3,'engage_button_collar':1,'alignment_pins_x8':1,
 'throttle_housing':1,'throttle_lever':1,'throttle_grip':1,'gear_lever_box':1,'gear_lever_arm':1,'gear_lever_wheel_knob':1,
 'joystick_housing':2,'joystick_adapter_plate':2,'harness_hub_base':2,'harness_hub_lid':2,
 'pivot_cable_clamp_base':8,'pivot_cable_clamp_cap':8,'limit_switch_mount':10,
 'esp32_enclosure_base':3,'esp32_enclosure_lid_PILOT':1,'esp32_enclosure_lid_OPS':1,'esp32_enclosure_lid_COMMAND':1,
 'cable_clips_set':3}
white={'gear_lever_wheel_knob'}
def pv(m,infill=0.25,t=1.2):
    V=m.volume/1000; shell=min(V,m.area/100*t/10); return shell+(V-shell)*infill, V
tot={'black':0,'white':0}; rows=[]
def meshes(f):
    # panels: one 3MF with a body object and a letters object; parts: one object
    sc=trimesh.load(f)
    if 'panels' in f:
        for g in sc.geometry.values():
            yield os.path.basename(f)[:-4]+(' letters WHITE' if 'letters' in g.metadata.get('name','') or g.volume<sum(x.volume for x in sc.geometry.values())/4 else ' body'), g
    else:
        yield os.path.basename(f)[:-4], trimesh.load(f,force='mesh')
for f, (n, m) in ((f, x) for f in sorted(glob.glob(D+'/panels/*.3mf'))+sorted(glob.glob(D+'/parts/*.3mf')) for x in meshes(f)):
    infill = 0.5 if n.startswith('monitor') else (0.45 if n.startswith('harness') else 0.25)
    add(n, m, qty.get(n, 1), 'white' if n in white else 'black', infill)
for r in rows: print(r)
res={c:dict(cm3=round(v,0),kg=round(v*1.27/1000*1.15,2)) for c,v in tot.items()}
print(json.dumps(res)); json.dump(res,open('/workspace/ff-bom/filament_estimate.json','w'))
