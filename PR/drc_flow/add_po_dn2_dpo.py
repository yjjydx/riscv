#!/usr/bin/env python3
"""Create a fixed derived GDS with DPO (17/1) shapes for PO.DN.2."""

from collections import Counter
from fractions import Fraction
from pathlib import Path
import math
import os
import struct

BASE = Path("data/riscv_m2fill_test.gds2")
OUT = Path("data/riscv_po_dn2_fix.gds2")
TMP = Path("data/riscv_po_dn2_fix.gds2.tmp")
TOP = "riscv"
LAYER = 17
DATATYPE = 1


def records(blob):
    off = 0
    while off < len(blob):
        if off + 4 > len(blob):
            raise ValueError("truncated GDS record header")
        size, rtype, dtype = struct.unpack_from(">HBB", blob, off)
        if size < 4 or size % 2 or off + size > len(blob):
            raise ValueError("invalid GDS record at byte %d" % off)
        yield off, size, rtype, dtype, blob[off + 4 : off + size]
        off += size


def decode_real8(raw):
    if raw == b"\0" * 8:
        return 0.0
    sign = -1.0 if raw[0] & 0x80 else 1.0
    exponent = (raw[0] & 0x7F) - 64
    mantissa = int.from_bytes(raw[1:], "big") / float(1 << 56)
    return sign * mantissa * (16.0**exponent)


def dbu_per_um(blob):
    for _, _, rtype, dtype, payload in records(blob):
        if rtype == 0x03 and dtype == 0x05 and len(payload) == 16:
            meters_per_dbu = decode_real8(payload[8:16])
            value = 1e-6 / meters_per_dbu
            rounded = round(value)
            if not math.isclose(value, rounded, rel_tol=0.0, abs_tol=1e-6):
                raise ValueError("non-integer DBU/um: %.12g" % value)
            return rounded
    raise ValueError("GDS UNITS record not found")


def rec(rtype, dtype, payload=b""):
    if len(payload) % 2:
        payload += b"\0"
    return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload


def grid(frac_um, dbu):
    value = frac_um * dbu
    if value.denominator != 1:
        raise ValueError("coordinate is off GDS grid")
    if not -(1 << 31) <= value.numerator < (1 << 31):
        raise ValueError("coordinate exceeds signed int32")
    return value.numerator


def expected_shapes(dbu):
    result = []
    x0, x1 = Fraction(48, 5), Fraction(52, 5)
    for y in range(5, 486, 10):
        y0 = Fraction(5 * y - 2, 5)
        y1 = Fraction(5 * y + 2, 5)
        points = ((x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0))
        result.append(tuple(grid(v, dbu) for point in points for v in point))
    return result


def boundary(xy):
    payload = struct.pack(">" + "i" * len(xy), *xy)
    return b"".join(
        (
            rec(0x08, 0x00),
            rec(0x0D, 0x02, struct.pack(">h", LAYER)),
            rec(0x0E, 0x02, struct.pack(">h", DATATYPE)),
            rec(0x10, 0x03, payload),
            rec(0x11, 0x00),
        )
    )


def inspect_top(blob):
    in_struct = False
    name = None
    top_seen = 0
    top_end = None
    element = None
    shapes = []
    for off, _, rtype, _, payload in records(blob):
        if rtype == 0x05:
            in_struct, name = True, None
        elif in_struct and rtype == 0x06:
            name = payload.rstrip(b"\0").decode("ascii")
            if name == TOP:
                top_seen += 1
        elif in_struct and name == TOP and rtype == 0x08:
            element = {"layer": None, "datatype": None, "xy": None}
        elif element is not None and rtype == 0x0D:
            element["layer"] = struct.unpack(">h", payload)[0]
        elif element is not None and rtype == 0x0E:
            element["datatype"] = struct.unpack(">h", payload)[0]
        elif element is not None and rtype == 0x10:
            count = len(payload) // 4
            element["xy"] = struct.unpack(">" + "i" * count, payload)
        elif element is not None and rtype == 0x11:
            if element["layer"] == LAYER and element["datatype"] == DATATYPE:
                shapes.append(tuple(element["xy"]))
            element = None
        elif in_struct and rtype == 0x07:
            if name == TOP:
                top_end = off
            in_struct, name, element = False, None, None
    if top_seen != 1 or top_end is None:
        raise ValueError("expected exactly one top structure named %s" % TOP)
    return top_end, Counter(shapes)


def main():
    # Python 3.5 Path.resolve() requires the output path to already exist.
    if os.path.abspath(str(BASE)) == os.path.abspath(str(OUT)):
        raise SystemExit("base and output paths must differ")
    blob = BASE.read_bytes()
    dbu = dbu_per_um(blob)
    end, before = inspect_top(blob)
    expected = expected_shapes(dbu)
    inserted = b"".join(boundary(xy) for xy in expected)
    fixed = blob[:end] + inserted + blob[end:]
    _, after = inspect_top(fixed)
    if after != before + Counter(expected):
        raise SystemExit("post-write DPO verification failed")
    TMP.write_bytes(fixed)
    # Python 3.5 os.replace() does not accept pathlib.Path objects.
    os.replace(str(TMP), str(OUT))
    print("BASE=%s" % BASE)
    print("OUTPUT=%s" % OUT)
    print("DBU_PER_UM=%d" % dbu)
    print("TOP=%s ADDED_DPO_17_1=%d" % (TOP, len(expected)))
    print("DPO_BOX=X9.6..10.4 Y4.6..485.4 um")


if __name__ == "__main__":
    main()
