#!/usr/bin/env python3
"""Capture one joystick input for the bind wizard.

Reads the Linux joystick API (/dev/input/jsX) and prints the first fresh
press/deflection, then exits:
    BTN 3      button number
    AXIS +2    axis number with direction

Startup baselines the current state (drained for ~200ms) so resting
trigger axes (e.g. Xbox LT/RT sitting at -32767) and held buttons do not
fire immediately: only 0->1 button transitions and axis deviations beyond
THRESHOLD count. Exits 1 silently on disconnect — the QML side simply
retries the step.
"""

import select
import struct
import sys
import time

THRESHOLD = 12000
DRAIN_SECS = 0.25


def read_event(f):
    data = f.read(8)
    if len(data) < 8:
        return None
    t, value, kind, number = struct.unpack("IhBB", data)
    return value, kind & 0x7F, number


def main(path):
    try:
        f = open(path, "rb")
    except OSError:
        return 1

    buttons = {}
    axes = {}
    deadline = time.time() + DRAIN_SECS
    # Phase 1: baseline current state.
    while time.time() < deadline:
        ready, _, _ = select.select([f], [], [], max(0.0, deadline - time.time()))
        if not ready:
            break
        ev = read_event(f)
        if ev is None:
            return 1
        value, kind, number = ev
        if kind == 1:
            buttons[number] = value
        elif kind == 2:
            axes[number] = value

    # Phase 2: first fresh input wins.
    while True:
        ready, _, _ = select.select([f], [], [])
        if not ready:
            continue
        ev = read_event(f)
        if ev is None:
            return 1
        value, kind, number = ev
        if kind == 1:
            if value == 1 and buttons.get(number, 0) == 0:
                print("BTN %d" % number, flush=True)
                return 0
            buttons[number] = value
        elif kind == 2:
            base = axes.get(number, 0)
            if abs(value - base) > THRESHOLD:
                print("AXIS %s%d" % ("+" if value > base else "-", number), flush=True)
                return 0
            axes[number] = value


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: joybind.py /dev/input/jsX", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
