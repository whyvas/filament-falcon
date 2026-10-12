# More ways to use VR in the Falcon

The spacewalk (see [VR_SETUP.md](VR_SETUP.md)) is the main VR feature. These are the other ideas, with
what is built and what is left. Everything keeps the same architecture: VR is a **separate client process**
on localhost, so the cockpit's four screens never depend on a headset.

## Built

1. **EVA chase drone (crew camera).** A small free-flying camera that orbits slowly behind the spacewalker
   (`CamFeedView` kind `EVA DRONE`, `CamFeedView.drone_xform`). It is on the kids' console EVA page next to
   the HELMET CAM, and on Commander → EVA (button DRONE). Unlike the helmet cam, it shows the astronaut
   (helmet, visor, lamps, PLSS, tether) against the ship and Earth, so the crew always knows where their
   spacewalker is, even out of sight of the windows.
2. **Wrist cuff checklist (in the headset).** Real EVA suits have a checklist on the left wrist. The VR client
   puts a little screen on the left glove with O2, battery, CO2, jet gas, tether length and the current task,
   so no floating HUD is needed in the headset (`EvaClient.cuff`). In the on-screen mode the helmet-cam overlay
   shows the same telemetry.
3. Small touches that came with the spacewalk: knocking leaves a frost ring, a palm on the glass a frost
   hand print that fades (seen from inside); the crew hears the knock; Quindar "beeps" on the suit radio.

## Not built yet (ideas, roughly in order of fun per effort)

| Idea | What it would be | Notes |
|---|---|---|
| **VR docking training** | The spacewalker floats near the station's port and calls corrections ("left 2 m!") while the Pilot docks; or the VR player flies a small training pod with the Touch sticks. | Re-uses the docking mission + the EVA client; the pod would be a second `ShipSim` in the client. |
| **Handheld orbit map** | Grip a tablet in VR showing the NAV orbit map (the console's NAV page rendered to a `SubViewport` on a quad on the left hand). Point with the right hand to set the nav target for Ops. | The NAV page already draws itself; needs a world-space UI with pointer input. |
| **Big picture window** | A huge virtual cupola: the VR player sits at a "viewing window" behind the cockpit and watches the flight in 3D, with the voice callouts. Good for a 4th kid who just wants to look. | Same client, no EVA sim: just an `XROrigin3D` riding in the ship frame + the vignette for ship rotation. |
| **VR cockpit seat** | A full virtual Falcon cockpit built from the CAD panel layouts (`cad/tools/layouts.py`, the same source as the virtual panels): every switch and button pressable with the hands, sending the same input actions as the physical boards. A remote crew member could fly from another room. | Biggest job: 3D panels from the layouts, hand-poke interaction, and a seat role in `InputHub`. The virtual-panel generator already knows every control's position and type. |
| **Zero-g interior** | Float inside the cabin/airlock before an EVA: pre-breathe, put on the jetpack, depressurize, open the hatch. | Needs an interior model; short, but a great "suit up" ritual for kids. |
| **Mixed reality hatch** | Quest 3 passthrough: the real cockpit frame stays visible until the hatch opens, then space fades in. | Needs `XR_FB_passthrough` through WiVRn (check support first) and a careful safety review. |
