"""Parse firmware/include/config_*.h so the diagrams always match the firmware."""
import re, pathlib
INC = pathlib.Path(__file__).resolve().parents[3] / "firmware" / "include"


def pins():
    return {k: int(v) for k, v in re.findall(r"#define\s+(PIN_\w+)\s+(\d+)", (INC / "board_pins.h").read_text())}


def board(fname):
    t = (INC / fname).read_text()
    P = pins()
    P.update({k: int(v) for k, v in re.findall(r"#define\s+(PIN_\w+)\s+(\d+)", t)})
    r = lambda x: P.get(x, int(x) if x.isdigit() else x)
    b = {"name": re.search(r'FF_BOARD_NAME\s+"([^"]+)"', t).group(1),
         "chips": int(re.search(r"FF_SR_CHIPS\s+(\d+)", t).group(1)),
         "axes": [], "sr": {}, "gpio": {}, "enc": [], "enc_btn": {}, "pins": P}
    for m in re.finditer(r'FF_AXIS\(\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\d+),\s*"(\w+)"\)', t):
        b["axes"].append((r(m.group(1)), m.group(2), m.group(3), m.group(6)))
    for m in re.finditer(r'FF_BTN\(\s*(\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*"(\w+)"\)', t):
        src, ref, hid, kind, act = m.groups()
        if src == "SRC_SR":
            b["sr"][int(ref)] = (act, int(hid), kind)
        elif src.startswith("SRC_GPIO"):
            b["gpio"][r(ref)] = (act, int(hid), kind)
        else:
            b["enc_btn"].setdefault(int(ref), []).append((src, act, int(hid)))
    for m in re.finditer(r'FF_ENC\(\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\d+),\s*"(\w*)"\)', t):
        b["enc"].append((r(m.group(1)), r(m.group(2)), m.group(4), m.group(6)))
    return b


BOARDS = {"pilot": "config_pilot.h", "ops": "config_ops.h", "command": "config_command.h"}
