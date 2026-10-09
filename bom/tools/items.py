# (category, item, spec/notes, used_for, qty, have, store, asin_or_url, est_price, search_terms)
# store: 'Amazon.ca' (asin), 'Kent' (url, price verified via kent.ca), 'Kent*' (search only, estimate), 'Owned', 'Amazon.ca*' (search only, estimate), 'Local*' (metal shop, estimate)
OWN='Owned'
CK='Note: you may already own some of these (tick Have it if so).'
I=[]
def a(*r): I.append(r)
C='Computer & displays (owned)'
a(C,'Gaming PC (Ryzen 9 5900X, RX 6800 XT 16 GB, 32 GB RAM)','Linux Mint; RX 6800 XT: 2x DP 1.4, 1x HDMI 2.1, 1x USB-C, max 4 displays','Runs the Godot game (3 windows)',1,True,OWN,'',0,'')
a(C,'Sceptre C275B-144R 27" curved monitor','1920x1080 144 Hz, 1800R, VESA 100 M4, HDMI/DP/DVI, 3.80 kg','PILOT window (left kid), in the pod',1,True,OWN,'',0,'')
a(C,'Sceptre C275W-1920RN 27" curved monitor','1920x1080 75 Hz, 1800R, VESA 75 M4, HDMI + VGA only, 3.40 kg','OPS window (right kid), in the pod',1,True,OWN,'',0,'')
a(C,'ViewSonic TD2220 22" touchscreen','21.5" 1920x1080, optical 2-point touch over USB-B, VGA + DVI-D only, VESA 100','Centre console touchscreen (in the cradle)',1,True,OWN,'',0,'')
a(C,'HY300 mini projectors','Only in the projector-dome feasibility study (docs/mechanical/projector_dome_study.md); not in the core build','Optional dome / ambient projection',3,True,OWN,'',0,'')
a(C,'3-axis joysticks with top button (X, Y, twist pots + button)','"A couple" owned; assumed potentiometer sticks (see electronics README). Mounting pattern still to measure','PILOT and OPS sticks',2,True,OWN,'',0,'')

C='Video & USB cabling'
a(C,'DisplayPort 1.4 cable, 3 m (10 ft), VESA certified','Latching connectors; 3-5 m per displays.md - measure from the PC location','GPU DP1 -> C275B-144R (1080p 144 Hz)',1,False,'Amazon.ca','B0BRPZHK36',None,'displayport 1.4 cable 10 ft')
a(C,'HDMI cable, 3 m (10 ft)','High speed; C275W only has HDMI/VGA','GPU HDMI -> C275W-1920RN (1080p 75 Hz)',1,False,'Amazon.ca','B014I8T0YQ',None,'hdmi cable 10 ft')
a(C,'DisplayPort -> DVI-D adapter cable, passive, 3 m (10 ft)','Single-link DVI-D, 1080p60, passive DP++ is fine. One-piece cable = no separate DVI cable needed. Alternative if you already have the TD2220 DVI cable: StarTech DP2DVI2 passive adapter https://www.amazon.ca/dp/B0035PS57C','GPU DP2 -> TD2220 DVI-D in',1,False,'Amazon.ca','B06WD33P34',None,'displayport to dvi-d cable 10 ft')
a(C,'USB-A to USB-B cable, 3 m (10 ft)','USB 2.0; <= 5 m (or use an active extension)','PC -> TD2220 touch (HID)',1,False,'Amazon.ca','B07ZRBRDHG',None,'usb a to usb b cable 10 ft')
a(C,'USB-A to USB-C data cables 1.8 m (6 ft), 3-pack','Must be DATA cables; plug into each board\'s "USB" port (not "UART")','3x ESP32-S3 boards -> PC / hub',1,False,'Amazon.ca','B0CLZ9J2F5',None,'usb a to usb c data cable 6 ft 3 pack')
a(C,'Powered USB 3.0 hub, 7-port, with power adapter','Electronics README: a powered USB 3 hub is fine','3x ESP32-S3 + TD2220 touch',1,False,'Amazon.ca','B00SCX6I8A',None,'powered usb 3.0 hub 7 port')
a(C,'Expandable braided sleeve 25 mm (1"), 7.6 m (25 ft)','BOM: 5 m of 25-30 mm sleeve','200 mm U service loops at the pod + cradle pivots',1,False,'Amazon.ca','B073YLYBJF',None,'braided cable sleeve 1 inch 25 ft')

C='Controllers & logic'
a(C,'ESP32-S3-DevKitC-1-N8R8, 5-pack','Must be the S3 DevKitC-1 with both "USB" + "UART" ports. 3 needed + 2 spares','Falcon Pilot / Ops / Command',1,False,'Amazon.ca','B0D93FLZLH',None,'ESP32-S3-DevKitC-1 N8R8')
a(C,'74HC165 shift register DIP-16, 25 pcs','10 needed (3 Pilot, 3 Ops, 4 Command) + 2 spares','Switch inputs',1,False,'Amazon.ca','B0D2THXFQ6',None,'SN74HC165N DIP-16')
a(C,'DIP IC socket assortment (incl. 14- and 16-pin)','12x DIP-16 for the 74HC165s + 1x DIP-14 for the 74AHCT125','Socketed chips on the perfboards',1,False,'Amazon.ca','B01GOLSUAU',None,'dip ic socket assortment')
a(C,'10 kOhm bussed resistor network SIP-9 (A103J), 20 pcs','12 needed (one per 74HC165, 8 pull-ups)','74HC165 input pull-ups',1,False,'Amazon.ca','B0D4BXJ1SX',None,'10k bussed resistor network sip 9 A103J')
a(C,'100 nF ceramic capacitors, 100 pcs','52 needed: 20 at chips/boards + 32 at the WS2812D-F5 LEDs','Decoupling',1,False,'Amazon.ca','B09JWTW1GT',None,'100nf ceramic capacitor 104 100pcs')
a(C,'Electrolytic capacitor assortment 0.1-1000 uF (10-50 V)','Covers 5x 10 uF (boards + overhead cable end) and 1x 1000 uF 10 V+ across the LED strip input','Bulk decoupling',1,False,'Amazon.ca','B07KC99W2K',None,'electrolytic capacitor assortment 1000uf')
a(C,'74AHCT125N DIP-14 level shifter, 10 pcs','1 needed (3.3 V -> 5 V LED data)','WS2812B data line from Falcon Command',1,False,'Amazon.ca','B0C6FNV224',None,'74AHCT125N DIP-14')
a(C,'Resistor kit 1/4 W 1%, 50 values','Covers 2x 330 Ohm (LED data), 2x 100 Ohm (CLK series), 6x 10 kOhm (opto pull-up, spares)','Misc. resistors',1,False,'Amazon.ca','B07P3MFG5D',None,'resistor assortment kit 1/4w metal film')
a(C,'2.2 kOhm 1/2 W resistors, 10 pcs','1 needed (PC817 LED from 12 V)','Isolated seat/pod sense',1,False,'Amazon.ca','B0185FKB2S',None,'2.2k ohm 1/2w resistor')
a(C,'PC817 optocoupler DIP-4, 20 pcs','1-2 needed (cradle reclined / pod down READ contacts)','Isolated position sense into Falcon Command',1,False,'Amazon.ca','B01JG8EJVW',None,'pc817 optocoupler dip')
a(C,'Perfboard 7 x 9 cm, 10 pcs','3 needed (one carrier per DevKitC-1, fits the printed enclosure)','ESP32 carrier boards',1,False,'Amazon.ca','B07GJ788H4',None,'perfboard 7x9 cm')
a(C,'2.54 mm male + female pin header kit','Female headers to socket each DevKitC-1','ESP32 carrier boards',1,False,'Amazon.ca','B01GY36RJY',None,'2.54mm male female pin header kit')
a(C,'JST-XH 2.54 mm connector kit with pre-crimped leads','No crimper needed','Panel harness connectors',1,False,'Amazon.ca','B08G18PWQ6',None,'jst xh connector kit pre crimped')
a(C,'Dupont jumper wires, 120 pcs','Bench testing + short links','Prototyping',1,False,'Amazon.ca','B01EV70C78',None,'dupont jumper wires')
a(C,'Cat6 patch cable 7.6 m (25 ft)','Measure Command board -> overhead (pod top band) first; route through the pod pivot service loop','Falcon Command -> overhead 74HC165 chain (CLK, LOAD, DATA, 3V3, GND)',1,False,'Amazon.ca','B007NZGPAY',None,'cat6 patch cable 25 ft')
a(C,'22 AWG stranded hookup wire kit (6 colours)','Not in the source parts lists, but needed to wire ~60 switches/LEDs to the boards','Switch + LED wiring',1,False,'Amazon.ca','B089CQHRDT',None,'22 awg stranded hookup wire kit')

C='Panel controls'
a(C,'Mini toggle switch MTS-102, 6 mm (1/4") bushing, 10 pcs','26 needed: 22 ON-OFF (use 2 of 3 pins) + 4 under printed missile guards (ENG ARM, JUMP ARM, EJECT +1). '+CK,'Pilot/Ops/overhead toggles',3,False,'Amazon.ca','B0CX9FDTJ8',None,'mts-102 mini toggle switch 6mm')
a(C,'Mini toggle MTS-103 ON-OFF-ON, 6 mm bushing, 10 pcs','2 needed (+1 spare). '+CK,'Pilot FLAPS',1,False,'Amazon.ca','B0D47RXXMK',None,'mts-103 on-off-on mini toggle')
a(C,'22 mm momentary push buttons (LA38, 5 colours), 6 pcs','8 needed (6 + 2 spares); 3 mm panel. '+CK,'IGNITION, BOOST, ENGAGE, START, PAUSE, CAUTION RESET',2,False,'Amazon.ca','B09F39MBKD',None,'22mm momentary push button')
a(C,'19 mm momentary metal push buttons, 2 pcs','3 needed (2 + 1 spare). '+CK,'FIRE SUPPR, INTERCOM',2,False,'Amazon.ca','B0GGYZJFHD',None,'19mm momentary push button metal')
a(C,'16 mm momentary metal push buttons, 5 pcs','10 needed (8 + 2 spares). '+CK,'HORN, VIEW, SCAN PING, NAV TGT, 4 failure buttons',2,False,'Amazon.ca','B081JJBN4G',None,'16mm momentary push button metal')
a(C,'EC11 rotary encoder with push switch + knob, 10 pcs','5 needed (4 + 1 spare), 7 mm panel hole. '+CK,'FLIGHT ASSIST, OPS MODE, MISSION, DIMMER',1,False,'Amazon.ca','B07VCNNV88',None,'ec11 rotary encoder with knob')
a(C,'B10K linear potentiometer, 16 mm, 6 mm D shaft','1 needed; check pack size on the listing','Pilot throttle lever (printed quadrant)',1,False,'Amazon.ca','B0CLP8SVJN',None,'b10k linear potentiometer 6mm d shaft')
a(C,'KW11 lever micro switch, 10 pcs','2 needed in the printed gear lever box','LANDING GEAR lever',1,False,'Amazon.ca','B0F9XYYSPZ',None,'kw11 micro switch lever')
a(C,'19 mm key switch, 2 position, key removable in OFF','MASTER POWER (game input). Rotary 2-position metal key switch, 1NO1NC. Check key is removable in OFF only','CMD_A MASTER POWER',1,False,'Amazon.ca','B09M849WCK',None,'19mm key switch 2 position')

C='LED backlighting'
a(C,'WS2812B LED strip 5 V, 60 LED/m, 5 m, IP30 (no sleeve)','BTF-LIGHTING ECO; this ASIN is the Black PCB / IP30 / 5 m 60 LED/m variant (checked). 10 mm wide strip fits the 12 mm channels; ~136 label LEDs + panel hops','Backlit labels, one continuous strip',1,False,'Amazon.ca','B0F8VDHK22',None,'ws2812b 5m 60 led ip30')
a(C,'WS2812D-F5 5 mm through-hole addressable RGB LEDs, ~40 pcs','32 status holes + spares; spliced into the same data line. NOT found on amazon.ca (only plain 4-pin RGB). Try AliExpress / Digi-Key, or use plain LEDs + 74HC595 (firmware change)','Status/indicator LEDs (*_LED ids)',1,False,'Amazon.ca*','',20.00,'WS2812D-F5 5mm addressable RGB LED')
a(C,'5 mm LED holders / bezels, 50 pcs','32 needed. '+CK,'Status LED holes',1,False,'Amazon.ca','B0DJR583BY',None,'5mm led holder bezel')
a(C,'Mean Well LRS-50-5 (5 V 10 A) power supply','Firmware caps strip at 8 A; inject power at start/middle/end','LED strip power',1,False,'Amazon.ca','B019GYOCMM',None,'mean well lrs-50-5')
a(C,'Inline 5x20 mm fuse holders + fast-blow fuse kit','Use a 10 A fuse at the PSU output','LED PSU output fuse',1,False,'Amazon.ca','B07X8WL5TC',None,'inline fuse holder 5x20 kit')
a(C,'16 AWG red/black 2-conductor wire, 15 m (50 ft)','LED power trunk. Prefer pure copper (check listing)','LED 5 V trunk',1,False,'Amazon.ca','B0CNRTZ4N3',None,'16 awg red black wire copper')
a(C,'18 AWG red/black silicone wire, 7.6 m (25 ft)','Injection drops; 2nd roll for the 12 V switch circuits of the interlock','LED injection + interlock switch wiring',2,False,'Amazon.ca','B07HGTKQ89',None,'18 awg red black silicone wire')
a(C,'JST-SM 3-pin pigtails (WS2812), 60 pcs','Panel-to-panel strip hops, removable panels','LED strip connectors',1,False,'Amazon.ca','B0CP94DL4F',None,'jst sm 3 pin connector ws2812')

C='Printed parts: filament & inserts'
a(C,'PETG filament 1.75 mm BLACK, 1 kg','Estimate 5.3 kg incl. 15 % waste (see Notes sheet) -> 6 spools. Panels, enclosures, mounts, harness hub (PETG required there)','All black printed parts',6,False,'Amazon.ca','B0D41Y3WWZ',None,'petg filament 1.75 black 1kg')
a(C,'PETG filament 1.75 mm WHITE, 1 kg','Estimate only ~0.06 kg (letters/inserts) - 1 spool is plenty','Backlit letters / letter inserts',1,False,'Amazon.ca','B0CMC78XKT',None,'petg filament 1.75 white 1kg')
a(C,'Brass heat-set inserts kit M2-M6 (360 pcs)','Harness hub 5x M3 each; pivot cable clamps M4','Harness hub, pivot cable clamps',1,False,'Amazon.ca','B0CNRSJ1B2',None,'heat set inserts kit m3 m4')
a(C,'Metric socket screw assortment M2-M5 (1760 pcs)','Covers M3x20 (hub), M3x12, M4x12/16/20/25 (TD2220, monitors, clamps). Check M4 lengths vs your VESA inserts','Printed-part and display screws',1,False,'Amazon.ca','B0C38YFL3D',None,'m2 m3 m4 m5 socket head screw assortment')
a(C,'Self-tapping screw assortment M2 / M2.5 / M3','12x M2.5x6 (perfboards) + 12x M3x10 (enclosure lids)','ESP32 enclosures',1,False,'Amazon.ca','B09CT54JJZ',None,'self tapping screw assortment m2.5 m3')

C='Frame lumber & sheet goods'
a(C,'2x4 SPF stud 8 ft (2438 mm), kiln dried','22 used by the cut list + 2 spares. 38 x 89 mm (1.5" x 3.5"). Pick straight boards. Kent web price (store shown: Edmundston) - Moncton may differ','Frame (see frame/cut_list.md)',24,False,'Kent','https://kent.ca/en/2-x-4-x-8-spf-stud-kiln-dried-1016318',3.98,'2x4x8 stud')
a(C,'2x4 SPF 10 ft (3048 mm), kiln dried','The two 2450 mm sills. Kent web price from category listing','Base sills',2,False,'Kent','https://kent.ca/en/shop/building-materials/lumber-plywood/dimensional-lumber-studs',5.88,'2x4x10')
a(C,'Plywood 18 mm (3/4") 4x8 ft (1220 x 2440), spruce standard','13.5 m2 net + ~30 % waste. Seat boxes/backs, consoles, cradle deck, pod cheeks (2 layers), pod bands, dais','Frame panels',6,False,'Kent','https://kent.ca/en/3-4-x-4-x-8-18-5mm-spruce-plywood-standard-1015824',64.98,'3/4 plywood 4x8')
a(C,'Plywood 12 mm (1/2") 4x8 ft, spruce standard','9.2 m2 net. Casings, skins, nose box, pod back sheet + chin, crush-zone ramp','Frame skins',4,False,'Kent','https://kent.ca/en/1-2-x-4-x-8-12-5mm-spruce-plywood-standard-1015823',39.98,'1/2 plywood 4x8')
a(C,'6 mm (1/4") hardboard or plywood, 4x8 ft','Small covers / templates. Price shown is Kent 1/4" meranti ply (hardboard is cheaper)','Covers, templates',1,False,'Kent','https://kent.ca/en/1-4-x-4-x-8-meranti-plywood-1015821',24.99,'1/4 hardboard 4x8')

C='Fasteners & general hardware'
a(C,'Construction screws 5 x 80 mm (#10 x 3"), 1 box','2x4 joints, 2 per joint min.','Frame',1,False,'Kent*','',25.00,'construction screws #10 x 3')
a(C,'Wood screws 4 x 40 mm (#8 x 1-1/2"), 1 box','Ply to 2x4','Frame',1,False,'Kent*','',15.00,'wood screws #8 x 1-1/2')
a(C,'Wood screws 4 x 25 mm (#8 x 1"), 1 box','Skins, clips, limit-switch brackets; also the 30x M4x25 countersunk screws for the TD2220 trim laps','Frame, trim ring',1,False,'Kent*','',12.00,'wood screws #8 x 1')
a(C,'PVA wood glue, 1 L','Cheek laminations, boxes','Frame',1,False,'Kent*','',15.00,'wood glue 1 l')
a(C,'M5 four-prong T-nuts, M5 x 8 mm, 200 pcs','Drill the barrel hole (~7 mm, check) on the 40 mm grid, press in from the back','Panel bays',1,False,'Amazon.ca','B0FF4HDSK3',None,'m5 tee nut 4 prong 200')
a(C,'M5 x 20 flanged button-head socket screws, black, 50 pcs','200 needed -> 4 packs (flanged, washers optional)','Panels into T-nuts',4,False,'Amazon.ca','B0FR1FQ1B7',None,'m5 x 20 button head socket screw black')
a(C,'M5 flat washers, 200 pcs','Optional with flanged screws','Panels',1,False,'Amazon.ca','B0GX28963L',None,'m5 flat washers 200')
a(C,'M6 x 50 carriage bolts + fender washers + nylocks','2 printed monitor standoffs x 4 bolts through the pod back sheet','Monitor standoffs',8,False,'Kent*','',1.50,'m6 x 50 carriage bolt')
a(C,'2 mm stainless safety cable with loops, 300 mm (12"), 5 pcs','REQUIRED: one per monitor, VESA screw -> eye screw in the back sheet, <= 50 mm slack (the pod parks monitors face-down). Plus 2 eye screws (Kent)','Monitor safety tethers',1,False,'Amazon.ca','B0FQP7W6J3',None,'2mm stainless safety cable loops 12 inch')
a(C,'Pivot bolts M6 x 30 + M4 x 40 with nylocks','Throttle lever pivot (M6x30), gear lever pivot (M4x40)','Throttle + gear lever',1,False,'Kent*','',4.00,'m6 x 30 bolt')

C='Motion system: pivots, shafts, bearings'
a(C,'25 mm linear shaft, 1000 mm, 2 pcs','Cradle shaft (one per side). Case-hardened chrome rod is hard to cut - bright steel h9 from a metal supplier is the BOM spec and cuts easily','Cradle pivot',1,False,'Amazon.ca','B0G5ZDQB47',None,'25mm shaft 1000mm')
a(C,'25 mm bright steel round bar (h9), 2 x ~250 mm','Pod shaft stubs (tower post outer -> inner). Local metal supplier / cut from bar','Pod pivot',1,False,'Local*','',30.00,'25mm steel round bar')
a(C,'SHF25 shaft supports, 4 pcs','6 needed (cradle shaft on 2 pedestals, pod shaft on inner tower posts + 2 spare positions) -> 2 packs','Cradle + pod shafts',2,False,'Amazon.ca','B0D9RTBQF2',None,'shf25 shaft support')
a(C,'UCP205 pillow block bearings 25 mm, 2-pack','Under the rear ends of the cradle rails','Cradle pivot',1,False,'Amazon.ca','B08HJYZK1X',None,'ucp205 pillow block bearing 25mm')
a(C,'UCF205 4-bolt flange bearing 25 mm','In the pod cheeks (one each side)','Pod pivot',2,False,'Amazon.ca','B0BLLVF9DB',None,'ucf205 flange bearing 25mm')
a(C,'25 mm steel double-split shaft collars, 2 pcs','4 needed -> 2 packs','Stop shafts walking',2,False,'Amazon.ca','B0G2Q98L26',None,'25mm shaft collar steel')
a(C,'6 mm steel plate 120 x 120 mm with 4 holes','Under the pod bearings / supports on the tower posts. Metal shop or cut from flat bar','Pod pivot',4,False,'Local*','',10.00,'6mm steel plate')
a(C,'M10 x 90 coach screws + washers','Bearings and shaft supports to the frame (~4 per bearing/support)','Bearings',20,False,'Kent*','',1.25,'m10 x 90 lag screw')
a(C,'M8 x 60 bolts + nylocks + washers','Actuator clevises (use your actuators\' pin size) + strut brackets','Actuators, struts',8,False,'Kent*','',1.50,'m8 x 60 bolt')

C='Motion system: drive & locks'
a(C,'Cradle linear actuator 12 V, 10" (254 mm) stroke, 1500 N (330 lbf), self-locking','Spec: ~364 mm (14.3") retracted pin-to-pin +-10 mm, <= 10 mm/s, internal limits, PUSH to recline; worst case ~775 N each. Listing (checked 2026-10-08): 250 mm stroke, retracted 370 mm (within +-10), extended 620 mm, self-locking, built-in limits, 4 A, brackets + polarity switch included','Seat recline (2 per cradle)',2,False,'Amazon.ca','B0FKMS7Y12',None,'12v linear actuator 10 inch stroke 330 lbs')
a(C,'Pod linear actuator 12 V, 12" (305 mm) stroke, 1000 N (225 lbf), self-locking','Spec: ~415 mm (16.3") retracted, <= 10 mm/s, PULL to raise; 141 N normally, 390 N each if both struts fail. Listing: 300 mm stroke, retracted 405 mm (10 mm short of 415 - adjust anchor in frame_model.py or confirm), self-locking, built-in limits, IP65','Pod rotate up/down',2,False,'Amazon.ca','B0CPHS87F8',None,'12v linear actuator 12 inch stroke 225 lbs')
a(C,'Gas struts (pair), 10" (254 mm) extended, 120 lb / 534 N, 10 mm ball-stud ends','SPEC: F1 = 590 N, ~240 mm extended, >= 70 mm stroke; buy 550-600 N or an adjustable-valve strut. This listing (254 mm extended, 169 mm compressed = 85 mm stroke) is the closest found but only 534 N (~10 % low) - an adjustable 600 N strut is better (see search link)','Pod counterbalance',1,False,'Amazon.ca','B0D7ZRQNJ9',None,'adjustable gas strut 600N 250mm')
a(C,'10 mm ball-stud gas strut mounting brackets','If the struts do not include ball-stud brackets','Strut anchors',1,False,'Amazon.ca','B07SJ6B3QP',None,'10mm ball stud gas strut bracket')
a(C,'Steel angle brackets 50 x 50 x 5 mm with M8 hole','Strut and actuator anchors on the tower posts / casings (heavy, not shelf brackets)','Strut + actuator anchors',4,False,'Kent*','',8.00,'heavy steel angle bracket')
a(C,'6 mm steel latch plates with UP and DOWN notches','Laser cut / filed from cheek template drawing 06; bolted to the cheeks','Pod mechanical locks',2,False,'Local*','',25.00,'laser cutting steel plate moncton')
a(C,'Spring-loaded steel pawl (barrel bolt / gate latch)','Engages the latch plates, one per casing','Pod mechanical locks',2,False,'Amazon.ca','B07GZHSCP6',None,'spring loaded barrel bolt latch heavy duty')
a(C,'Bowden cables + levers (bike brake lever set)','Release both pawls from the lever box left of dad\'s seat (second hand needed for pod motion)','Pod lock release',1,False,'Amazon.ca','B0B8C66T4Q',None,'bicycle brake lever cable set')
a(C,'Steel stop pins 12 mm (or 1/2" bolts) for hard stops','Pod UP / DOWN hard stops on the cheeks hitting steel angles','Pod hard stops',4,False,'Kent*','',4.00,'1/2 inch clevis pin')
a(C,'Rubber bumper / stop pads with screws (assorted)','Bumpers on the pod stop pins; cradle recline stop (10 mm) and upright stop (6 mm) pads','Hard stops',1,False,'Amazon.ca','B0D1XSZ8SF',None,'rubber bumper pads with screws')

C='Motion system: hardwired interlock'
a(C,'12 V 20 A (240 W) enclosed power supply','BOM: 12 V 20 A, enclosed, mains fused. Only one motion runs at a time (2 actuators)','Actuator power',1,False,'Amazon.ca','B07RJMG3FB',None,'12v 20a power supply enclosed')
a(C,'Inline ATC fuse holder 12 AWG with 20/30/40 A fuses','Use the 20 A blade fuse, right at the PSU','Actuator circuit fuse',1,False,'Amazon.ca','B0BHY1RQQR',None,'12 awg inline atc fuse holder')
a(C,'19 mm key switch, 2 position (MOTION key) - drives a 30 A relay','Key out = no motion. Same part as MASTER POWER','CMD_B MOTION key',1,False,'Amazon.ca','B09M849WCK',None,'19mm key switch 2 position')
a(C,'22 mm mushroom E-stop, NC, latching, twist release','In series with the whole motion circuit','CMD_B STOP',1,False,'Amazon.ca','B019DSZWPC',None,'22mm emergency stop nc')
a(C,'DPDT (ON)-OFF-(ON) momentary toggle, 12 mm bushing','Hold-to-run FLT / BRD (CREW POS); relays carry the motor current. Check bushing/hole size','CMD_B hold-to-run',1,False,'Amazon.ca','B0C22K75FZ',None,'dpdt momentary toggle on off on')
a(C,'12 V 30/40 A automotive relays SPDT 5-pin, 10 pcs','5 needed: 4 as two H-bridges (cradle, pod) + 1 for the key. Add relay sockets/harnesses','Motor switching',1,False,'Amazon.ca','B0DNJVMMF9',None,'12v 30a relay spdt 5 pin')
a(C,'V-15 roller-lever micro switches 15 A, 10 pcs','10 needed (8 motor-path limits/lock switches + 2 READ contacts) + printed limit_switch_mount; 2nd pack = spares','Limit + lock switches',2,False,'Amazon.ca','B0F8HJ4V9J',None,'v-156-1c25 roller lever micro switch 15a')
a(C,'6A10 rectifier diodes (6 A, 1000 V), 20 pcs','8 needed across the motor-path limit switches (frame BOM says 1N5408 3 A; 6A10 per electronics README is the stronger choice)','Limit switch drive-back diodes',1,False,'Amazon.ca','B079KF3VJG',None,'6a10 diode')
a(C,'Pressure-sensitive safety edge (NC), ~900 mm, with mounting profile','Along the pod chin, in series with "pod DOWN". Not found on amazon.ca - industrial / gate-operator supplier; price is a placeholder','Pod pinch protection',1,False,'Industrial*','',150.00,'pressure sensitive safety edge NC')
a(C,'14 AWG red/black 2-conductor wire, 15 m (50 ft)','20 m needed -> 2 rolls. Use pure copper (not CCA) for motor current','Actuator power path',2,False,'Amazon.ca','B0CXY76JGX',None,'14 awg red black copper wire 50 ft')
a(C,'Heat-shrink ring terminal kit, 260 pcs (22-10 AWG)','Plus heat shrink; printed cable clips','Interlock wiring',1,False,'Amazon.ca','B0B569WMNP',None,'heat shrink ring terminal kit')

C='Motion system: guards'
a(C,'Strip brush 25 mm in aluminium holder, ~5 m','4 m for the cheek slots (2 edges each) + 1 m for the nose-box actuator slots. Not found as a good match on amazon.ca; placeholder price','Slot guards',1,False,'Amazon.ca*','',60.00,'strip brush aluminum holder 25mm')
a(C,'High-density foam 25 mm (1") x 610 x 1830 mm','Pod chin (behind the safety edge) and pod lower edges; cover with the vinyl below','Pod edge padding',1,False,'Amazon.ca','B0DQXC46NQ',None,'high density foam 1 inch 24 x 72')

C='Seats & harnesses'
a(C,'Buckle kit: 25 mm side-release buckles + 9 m webbing (REDAPRIC)','REQUIRED LINK per design. WARNING: plastic (POM) luggage/backpack buckles, seller quotes ~50-136 kg breaking load, NOT safety-rated. Positioning harness only (see docs/mechanical/README.md safety note). Use the kit webbing for nothing structural. 2 kid seats x 4 buckles = 8 of 10. No featured offer on 2026-10-08 (other sellers only): price is a placeholder','Kid 4-point harness + printed harness_hub',1,False,'Amazon.ca','B0B3J1GCVQ',13.00,'1 inch side release buckle kit')
a(C,'Rated 25 mm (1") webbing, >= 700 kg','BOM asks polyester >= 700 kg; this is 1" nylon tubular climbing webbing Listing: UIAA/CE certified, 17.8 kN (4000 lb). Choose the 10 yd length variant','Kid harness straps (sewn bar-tack loops)',1,False,'Amazon.ca','B0B7RHCFMV',None,'1 inch rated webbing 4000 lb polyester')
a(C,'Welded steel O-rings 50 mm (2") OD','Listing: 50 mm ID, 5 mm wire, 304 stainless, 6-pack, NOT load-rated (BOM asks 50 mm OD, 6 mm wire, rated - a rated welded ring from a rigging supplier is better)','Harness hub load ring (2 needed)',1,False,'Amazon.ca','B0D781P6JB',None,'welded steel o ring 2 inch heavy duty')
a(C,'Welded steel D-rings 25 mm (1")','Optional - you asked for D-rings; frame BOM v0.2 only uses the O-ring. Useful as strap adjust/anchor points','Harness adjusters (optional)',1,False,'Amazon.ca','B0CS9SL864',None,'welded steel d ring 1 inch')
a(C,'3/8" (M10) forged eye bolts + fender washers + nylocks','Forged, not bent-wire. Anchors THROUGH the cradle rails / seat-back frames, never plywood alone','Harness anchors',10,False,'Kent*','',6.00,'forged eye bolt 3/8')
a(C,'2-point adjustable lap belt','Dad: fixed seat, no recline','Commander seat',1,False,'Amazon.ca','B0BFPZ5ZGW',None,'2 point lap belt adjustable')
a(C,'High-density upholstery foam 50 mm (2") x 610 x 1830 mm','Cushions: kids 340 x 380, dad 520 x 480; offcut stacked as the 60-80 mm booster for the 6 yr','Seat cushions',1,False,'Amazon.ca','B078SJ86G7',None,'high density foam 2 inch 24 x 72')
a(C,'Marine vinyl, black, 1.5 m x 1.37 m (5 ft x 54")','Covers for 3 cushions + pod chin foam','Upholstery',1,False,'Amazon.ca','B0744QFFS8',None,'marine vinyl fabric black')

C='Seats & harnesses - ALTERNATIVE (not in totals)'
a(C,'ALTERNATIVE: complete 4-point harness, 50 mm (2") straps, metal buckle','Instead of the DIY buckle-kit harness: a bought go-kart/sim 4-point harness with metal latch (frame BOM v0.1 recommendation). Check it fits a kid (6-12 yr) torso. Excluded from Grand total and Amazon cart','Kid seats (instead of buckle kit + webbing + O-rings)',2,False,'Amazon.ca','B08TB7NLJB',None,'4 point harness metal buckle 2 inch')
