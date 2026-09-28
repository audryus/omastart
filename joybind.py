#!/usr/bin/env python3
"""Capture one joystick input for the bind wizard.

Reads the Linux joystick API (/dev/input/jsX) and prints the first fresh
press/deflection, then exits:
    BTN 3      button number
    BTN h0up   hat direction
    AXIS +2    axis number with direction

joydev orders buttons and axes by evdev code, like RetroArch's udev
driver, so the numbers carry over as-is. Hats are the exception: joydev
reports a D-pad hat (ABS_HAT0X/Y) as two plain axes (6/7 on a DS4), while
udev profiles bind it as h0up/h0down/h0left/h0right — the stock DS4
profile does. JSIOCGAXMAP tells which axes are hats.

Every RAW event is echoed for the shell log (the QML side only honours
BTN/AXIS result lines).

Robustness (learned from a drifting DualShock 4):
- Startup waits for REST: no button held and every axis stable within
  JITTER for QUIET_SECS. This stops the previous step's still-held button
  from firing instantly, and keeps a stick held mid-travel out of the
  baseline.
- Baseline is the median of the samples seen while waiting (immune to a
  brief wiggle); axes only count past THRESHOLD from it.
- Gives up after ARM_TIMEOUT seconds (exit 1); the QML side retries with
  a "release everything first" hint.
"""

import array
import fcntl
import select
import struct
import sys
import time

# Capture threshold: gentle pushes peak around ~10000 on worn sticks
# (seen in the wild), while rest wobble stays under ~800 — 6000 splits
# the difference with wide margins on both sides.
THRESHOLD = 6000
JITTER = 1500
QUIET_SECS = 0.35
SETTLE_TIMEOUT = 10.0
ARM_TIMEOUT = 25.0

JSIOCGAXES = 0x80016A11
JSIOCGAXMAP = 0x80406A32   # _IOR('j', 0x32, __u8[ABS_CNT=64])
ABS_HAT0X = 0x10
ABS_HAT3Y = 0x17
# Trigger codes (ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE): a DS4's L2/R2 rest at
# -32767, which is not a held stick.
TRIGGER_CODES = (0x02, 0x05, 0x09, 0x0A)


def read_event(f):
    data = f.read(8)
    if len(data) < 8:
        return None
    _, value, kind, number = struct.unpack("IhBB", data)
    return value, kind & 0x7F, number


def axis_codes(f):
    """joydev axis number -> evdev ABS code."""
    try:
        count = array.array("B", [0])
        fcntl.ioctl(f, JSIOCGAXES, count)
        codes = array.array("B", [0] * 64)
        fcntl.ioctl(f, JSIOCGAXMAP, codes)
    except OSError:
        return {}
    return {number: codes[number] for number in range(count[0])}


def hat_axes(codes):
    """joydev axis number -> (hat index, is_y) for axes that are hats."""
    hats = {}
    for number, code in codes.items():
        if ABS_HAT0X <= code <= ABS_HAT3Y:
            hats[number] = ((code - ABS_HAT0X) // 2, (code - ABS_HAT0X) % 2 == 1)
    return hats


def hat_bind(hat, value):
    index, is_y = hat
    if is_y:
        return "h%d%s" % (index, "down" if value > 0 else "up")
    return "h%d%s" % (index, "right" if value > 0 else "left")


def median(values):
    ordered = sorted(values)
    return ordered[len(ordered) // 2]


def main(path):
    # Unbuffered: a buffered read(8) slurps the whole init burst into
    # Python's buffer, select() then sees an idle fd, and the settle phase
    # ends before the baseline exists (a DS4's L2 resting at -32767 then
    # "fires" instantly as AXIS -2).
    try:
        f = open(path, "rb", buffering=0)
    except OSError:
        return 1
    codes = axis_codes(f)
    hats = hat_axes(codes)
    first = {}

    buttons = {}
    samples = {}
    start = time.time()
    quiet_since = None
    last_seen = {}

    # Phase 1: settle — nothing held, axes quiet.
    while time.time() - start < SETTLE_TIMEOUT:
        remaining = start + SETTLE_TIMEOUT - time.time()
        ready, _, _ = select.select([f], [], [], min(0.05, remaining))
        now = time.time()
        if ready:
            ev = read_event(f)
            if ev is None:
                return 1
            value, kind, number = ev
            if kind == 1:
                buttons[number] = value
                quiet_since = None
            elif kind == 2:
                samples.setdefault(number, []).append(value)
                first.setdefault(number, value)
                prev = last_seen.get(number)
                last_seen[number] = value
                if prev is None or abs(value - prev) > JITTER:
                    quiet_since = None
        held = any(v == 1 for v in buttons.values())
        # A deflected stick (|v| huge) is a hold, not rest: refuse to
        # settle on it, or its release would capture backwards.
        # Triggers that opened at the negative rail are resting there.
        strained = any(abs(v) > 20000 for n, v in last_seen.items()
                       if not (codes.get(n) in TRIGGER_CODES and first.get(n, 0) < -20000))
        if not held and not strained:
            if quiet_since is None:
                quiet_since = now
            if now - quiet_since >= QUIET_SECS:
                break

    base = {}
    for number, values in samples.items():
        base[number] = median(values) if values else 0

    # Phase 2: arm until the deadline.
    deadline = start + SETTLE_TIMEOUT + ARM_TIMEOUT
    while time.time() < deadline:
        remaining = deadline - time.time()
        ready, _, _ = select.select([f], [], [], max(0.0, remaining))
        if not ready:
            continue
        ev = read_event(f)
        if ev is None:
            return 1
        value, kind, number = ev
        print("RAW kind=%d number=%d value=%d" % (kind, number, value), flush=True)
        if kind == 1:
            if value == 1 and buttons.get(number, 0) == 0:
                print("BTN %d" % number, flush=True)
                return 0
            buttons[number] = value
        elif kind == 2:
            if abs(value - base.get(number, 0)) > THRESHOLD:
                if number in hats:
                    print("BTN %s" % hat_bind(hats[number], value), flush=True)
                else:
                    print("AXIS %s%d" % ("+" if value > base.get(number, 0) else "-", number), flush=True)
                return 0
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: joybind.py /dev/input/jsX", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
