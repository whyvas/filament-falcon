#!/usr/bin/env python3
"""Regenerate every wiring diagram (PNG + SVG) in docs/electronics/.
    python3 -m venv ~/.venvs/ff && ~/.venvs/ff/bin/pip install matplotlib numpy
    ~/.venvs/ff/bin/python docs/electronics/src/make_all.py
"""
import runpy, pathlib
HERE = pathlib.Path(__file__).resolve().parent
for name in ("d01_simple_joystick.py", "d02_board_wiring.py", "d03_ws2812_power.py", "d04_seat_actuator.py"):
    runpy.run_path(str(HERE / name), run_name="__main__")
