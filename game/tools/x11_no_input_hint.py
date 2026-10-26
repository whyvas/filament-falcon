#!/usr/bin/env python3
"""Tell the window manager never to give a window keyboard focus (ICCCM WM_HINTS input=False).

    x11_no_input_hint.py WINDOW_ID [--restore]

The game runs this on the KIDS' CONSOLE window when the Commander has its own screen, so a tap on
the touchscreen can't make Cinnamon move keyboard focus off the Commander window. The window still
gets touches and clicks. --restore sets input=True again. Uses libX11 through ctypes (no extra
packages); exits 0 quietly when there is no X display or libX11.
"""
import ctypes
import ctypes.util
import sys

INPUT_HINT = 1


class XWMHints(ctypes.Structure):
    _fields_ = [
        ("flags", ctypes.c_long), ("input", ctypes.c_int), ("initial_state", ctypes.c_int),
        ("icon_pixmap", ctypes.c_ulong), ("icon_window", ctypes.c_ulong),
        ("icon_x", ctypes.c_int), ("icon_y", ctypes.c_int),
        ("icon_mask", ctypes.c_ulong), ("window_group", ctypes.c_ulong),
    ]


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip())
        return 2
    win = int(argv[1], 0)
    want_input = "--restore" in argv[2:]
    name = ctypes.util.find_library("X11")
    if not name:
        return 0
    x = ctypes.CDLL(name)
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x.XGetWMHints.restype = ctypes.POINTER(XWMHints)
    x.XGetWMHints.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    x.XSetWMHints.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWMHints)]
    x.XFree.argtypes = [ctypes.c_void_p]
    x.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x.XCloseDisplay.argtypes = [ctypes.c_void_p]
    dpy = x.XOpenDisplay(None)
    if not dpy:
        return 0
    cur = x.XGetWMHints(dpy, win)
    hints = XWMHints()
    if cur:
        hints = XWMHints.from_buffer_copy(cur.contents)
        x.XFree(cur)
    hints.flags |= INPUT_HINT
    hints.input = 1 if want_input else 0
    x.XSetWMHints(dpy, win, ctypes.byref(hints))
    x.XSync(dpy, 0)
    x.XCloseDisplay(dpy)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
