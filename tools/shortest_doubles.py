"""Write tests/data/shortest-doubles.txt: doubles as their exact bits beside the text JavaScript's Number toString
gives them, for OWJson.number's test (tests/test_json.gd).

    python tools/shortest_doubles.py

Each line: "<16 hex digits of the double's bits> <the JavaScript text>". The digits are Python's repr (the shortest
that reads back, the closest of those, as ECMAScript's Number::toString asks), laid out as ECMAScript lays them out.
The doubles: edge cases by hand, then a seeded draw of random bit patterns across the whole finite range and of
decimals of 16 and 17 digits in [1e-4, 1e16), where 15 digits most often fail. Standard library only; the same seed
writes the same file.
"""
import os
import random
import struct
from decimal import Decimal

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "tests", "data", "shortest-doubles.txt")
COUNT = 5000


def js_text(x: float) -> str:
    """ECMAScript Number::toString(x) for a finite double, from Python's shortest digits."""
    if x == 0:
        return "0"
    sign = "-" if x < 0 else ""
    t = Decimal(repr(abs(x))).normalize().as_tuple()   # no trailing zeros; value = digits * 10^exponent
    digits = "".join(map(str, t.digits))
    k = len(digits)
    n = k + t.exponent                                  # value = 0.digits * 10^n
    if k <= n <= 21:
        return sign + digits + "0" * (n - k)
    if 0 < n <= 21:
        return sign + digits[:n] + "." + digits[n:]
    if -6 < n <= 0:
        return sign + "0." + "0" * (-n) + digits
    e = n - 1
    e_part = "e" + ("+" if e >= 0 else "-") + str(abs(e))
    if k == 1:
        return sign + digits + e_part
    return sign + digits[0] + "." + digits[1:] + e_part


def bits(x: float) -> str:
    return struct.pack(">d", x).hex()


def from_bits(b: int) -> float:
    return struct.unpack(">d", struct.pack(">Q", b))[0]


def main() -> None:
    rng = random.Random(2301)
    xs = [5e-324, 1e-323, 2.2250738585072014e-308, 2.225073858507201e-308, 1.7976931348623157e308, 1e23, 9e15,
          3.590471669730255, 2966.215418, 0.1, 0.30000000000000004, 123.80196114964559, 263.2953629956518,
          4.35, 0.000123456789012345, 1.0000000000000002, 0.9999999999999999, 1e-7, 1e21, 2.0 ** -1022, 2.0 ** 1023]
    for k in range(-1070, 1024, 37):         # powers of two (the interval below is half as wide) and their neighbours
        p = 2.0 ** k
        xs += [p, from_bits(struct.unpack(">Q", struct.pack(">d", p))[0] - 1)]
    while len(xs) < COUNT // 2:
        b = rng.getrandbits(64)
        x = from_bits(b)
        if x == x and abs(x) != float("inf"):
            xs.append(x)
    while len(xs) < COUNT:
        x = float("%.*e" % (rng.choice((15, 16)), 10 ** rng.uniform(-4, 16)))
        xs.append(-x if rng.random() < 0.1 else x)
    for x in xs:
        assert float(js_text(x)) == x, (x, js_text(x))
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        for x in xs[:COUNT]:
            fh.write("%s %s\n" % (bits(x), js_text(x)))
    print("wrote %d doubles to %s" % (COUNT, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
