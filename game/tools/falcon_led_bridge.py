#!/usr/bin/env python3
"""Filament Falcon LED bridge.

The game (Godot has no serial API) sends LED protocol lines over UDP to 127.0.0.1:<port>.
This helper forwards them to the Falcon Command board's USB CDC serial port.

Protocol (see shared/led_protocol.md):
    SEG <LABEL_ID> <r> <g> <b> [SOLID|BLINK|FAST|PULSE|OFF]
    ALL <r> <g> <b> [MODE]   CLEAR   IDLE   BRIGHT <n>   ANIM BOOT|ALERT|STOP
Opening the port asserts DTR, which the board treats as "game connected"; closing it returns
the strip to the idle glow. The board is silent except for ERR/EVT lines (logged to stderr).
Lines starting with '#' are bridge-internal (heartbeat) and are not forwarded.

Exits quietly when pyserial is missing, and exits by itself when the game goes away.
Usage: falcon_led_bridge.py [--udp-port 47800] [--serial auto|/dev/ttyACM0] [--baud 115200]
                            [--parent-pid N] [--dry-run]
"""
import argparse
import glob
import os
import socket
import sys
import time


def find_port():
    """Port lookup order from shared/led_protocol.md."""
    if os.path.exists("/dev/falcon-command"):          # udev rule in firmware/udev/
        return "/dev/falcon-command"
    hits = sorted(glob.glob("/dev/serial/by-id/*Falcon_Command*"))
    if hits:
        return hits[0]
    try:  # any port with USB VID:PID 1209:0005 (Windows COMx too)
        from serial.tools import list_ports
        for p in list_ports.comports():
            if p.vid == 0x1209 and p.pid == 0x0005:
                return p.device
    except Exception:  # noqa: BLE001
        pass
    return None


def parent_alive(pid):
    if not pid:
        return True
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--udp-port", type=int, default=47800)
    ap.add_argument("--serial", default="auto")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--parent-pid", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true", help="print lines instead of writing serial")
    args = ap.parse_args()

    serial_mod = None
    if not args.dry_run:
        try:
            import serial as serial_mod  # pyserial
        except ImportError:
            print("[led-bridge] pyserial not installed (sudo apt install python3-serial); LEDs disabled",
                  file=sys.stderr)
            return 0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", args.udp_port))
    except OSError as e:
        print(f"[led-bridge] UDP port {args.udp_port} busy ({e}); another bridge running?", file=sys.stderr)
        return 0
    sock.settimeout(1.0)

    ser = None
    last_try = 0.0
    last_packet = time.time()
    print(f"[led-bridge] listening on 127.0.0.1:{args.udp_port}", file=sys.stderr)
    while True:
        if not parent_alive(args.parent_pid) or time.time() - last_packet > 30:
            break
        if ser is None and not args.dry_run and time.time() - last_try > 3.0:
            last_try = time.time()
            port = args.serial if args.serial not in ("", "auto") else find_port()
            if port:
                try:
                    ser = serial_mod.Serial(port, args.baud, timeout=0, write_timeout=0.2)
                    ser.dtr = True
                    ser.write(b"ANIM BOOT\n")
                    print(f"[led-bridge] connected to {port}", file=sys.stderr)
                except Exception as e:  # noqa: BLE001
                    print(f"[led-bridge] cannot open {port}: {e}", file=sys.stderr)
                    ser = None
        if ser is not None:
            try:
                incoming = ser.read(512)
                for ln in incoming.decode("ascii", "replace").splitlines():
                    if ln.strip():
                        print(f"[led-bridge] board: {ln.strip()}", file=sys.stderr)
            except Exception:  # noqa: BLE001
                pass
        try:
            data, _ = sock.recvfrom(4096)
        except socket.timeout:
            continue
        last_packet = time.time()
        for line in data.decode("utf-8", "replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if args.dry_run:
                print(line, flush=True)
                continue
            if ser is not None:
                try:
                    ser.write((line + "\n").encode("ascii", "replace"))
                except Exception as e:  # noqa: BLE001
                    print(f"[led-bridge] serial error: {e}; reconnecting", file=sys.stderr)
                    try:
                        ser.close()
                    except Exception:  # noqa: BLE001
                        pass
                    ser = None
    if ser is not None:
        try:
            ser.write(b"IDLE\n")
            ser.close()
        except Exception:  # noqa: BLE001
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
