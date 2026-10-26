#!/usr/bin/env python3
"""Bring the mouse cursor back after the touchscreen was used (X11).

Cinnamon (muffin) / GNOME (mutter) hide the cursor screen-wide (XFixesHideCursor, owned by the
window manager, so another client cannot undo it) when the last-used input device is a
touchscreen, and show it again only when the Virtual core pointer switches to a mouse
(XI_DeviceChanged / SlaveSwitch). With the touchscreen isolated from the core pointer
(touch_isolate.sh) moving the mouse never switches, so the cursor would stay hidden.

This nudges the core pointer 1 px and back through XTEST: the core pointer switches to its
XTEST slave (a "mouse"), the window manager shows the cursor, nothing visibly moves.

usage: x11_show_cursor.py        (needs $DISPLAY, libX11 + libXtst; exit 0 = nudged)
"""
import ctypes
import ctypes.util
import sys


def main() -> int:
    x11_name = ctypes.util.find_library("X11") or "libX11.so.6"
    xtst_name = ctypes.util.find_library("Xtst") or "libXtst.so.6"
    try:
        x11 = ctypes.CDLL(x11_name)
        xtst = ctypes.CDLL(xtst_name)
    except OSError as e:
        print("x11_show_cursor: %s" % e, file=sys.stderr)
        return 2
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
    xtst.XTestFakeRelativeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
    xtst.XTestQueryExtension.argtypes = [ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_int)] * 4
    dpy = x11.XOpenDisplay(None)
    if not dpy:
        print("x11_show_cursor: cannot open display", file=sys.stderr)
        return 1
    a, b, c, d = (ctypes.c_int() for _ in range(4))
    if not xtst.XTestQueryExtension(dpy, ctypes.byref(a), ctypes.byref(b), ctypes.byref(c), ctypes.byref(d)):
        print("x11_show_cursor: no XTEST extension", file=sys.stderr)
        x11.XCloseDisplay(dpy)
        return 1
    xtst.XTestFakeRelativeMotionEvent(dpy, 1, 0, 0)
    xtst.XTestFakeRelativeMotionEvent(dpy, -1, 0, 0)
    x11.XSync(dpy, 0)
    x11.XCloseDisplay(dpy)
    return 0


if __name__ == "__main__":
    sys.exit(main())
