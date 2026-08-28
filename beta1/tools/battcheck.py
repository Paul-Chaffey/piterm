#!/usr/bin/env python3
"""Compare the two halves of the CMOS/RTC battery-backup test.

    tools/battcheck.py                    share/RESBAT1 and share/RESBAT2
    tools/battcheck.py share/RESBAT1      just phase 1, before the power cut

test/fbbatt.bas writes a known time and two CMOS markers and spools
RESBAT1; the machine is then powered OFF at the mains for five minutes or
more; test/fbbatt2.bas reads both back into RESBAT2.

Three questions, and they fail separately (specification.md 5.5b-sexies):

  writable   does the chip accept a write with the machine powered?
             Asked SEPARATELY of the CMOS RAM and of the clock, because on
             this machine they answer differently: the RAM takes a
             *CONFIGURE and the clock rejects OSWORD &0F (5.5b-septies).
  retained   did the CMOS RAM survive the power cut?
  running    did the OSCILLATOR run on the battery, or did the clock
             merely freeze at the value that was written? Retention of
             RAM and a running clock are separate things on this chip.
"""
import sys, os, re
from datetime import datetime

SHARE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "share")

# The Master's OSWORD &0E string: "Fri,21 Aug 2026.16:00:00". A chip
# holding nothing reads "Mar,DB  ?? 197B.F3:48:22" in the same shape, so
# the parse and not the length is what separates them.
CLOCK = "%a,%d %b %Y.%H:%M:%S"


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as fh:
        # The Beeb spools with CR line endings and can leave stray high
        # bytes in a corrupt date, so decode leniently.
        raw = fh.read().decode("latin-1")
    return raw.replace("\r\n", "\n").replace("\r", "\n")


def marker(text, section, name):
    """The value of one *STATUS setting inside a named == section ==."""
    body = re.split(r"^== .* ==$", text, flags=re.M)
    heads = re.findall(r"^== (.*) ==$", text, flags=re.M)
    for head, chunk in zip(heads, body[1:]):
        if head.startswith(section):
            m = re.search(r"^%s\s+(\d+)\s*$" % name, chunk, flags=re.M)
            return int(m.group(1)) if m else None
    return None


def tagged(text, tag):
    m = re.search(r"^== %s ==\s*(.*?)\s*$" % tag, text, flags=re.M)
    return m.group(1) if m else None


def clock(s, like=None):
    """Parse one OSWORD &0E string.

    The chip holds two digits of year and this MOS prints the century as
    19 unconditionally, so a clock set to 2026 reads back as 1926. When a
    reference datetime is given, the century is normalised to it - without
    that, a successful write compares as a failure and a running clock
    compares as one that went backwards by a hundred years.
    """
    if not s:
        return None
    try:
        t = datetime.strptime(s.strip(), CLOCK)
    except ValueError:
        return None
    if like is not None and t.year != like.year and t.year % 100 == like.year % 100:
        t = t.replace(year=like.year)
    return t


def expected(text):
    m = re.search(r"^== (?:MARKERS|EXPECT) ==\s*Delay\s+(\d+)\s+Repeat\s+(\d+)",
                  text, flags=re.M)
    return (int(m.group(1)), int(m.group(2))) if m else (45, 17)


def main():
    args = sys.argv[1:]
    p1 = args[0] if args else os.path.join(SHARE, "RESBAT1")
    p2 = args[1] if len(args) > 1 else os.path.join(SHARE, "RESBAT2")

    one = read(p1)
    if one is None:
        sys.exit("no %s - phase 1 has not run" % p1)
    two = read(p2)

    dly, rpt = expected(one)
    wrote = tagged(one, "WROTE")
    # One line per OSWORD &0F reason code phase 1 tried: 24 first, and 15
    # then 8 only if 24 left the year wrong. Any of them getting the year
    # right means the clock took a write.
    tries = re.findall(r"^== CLOCK AFTER (\S+) ==\s*(.*?)\s*$", one, flags=re.M)
    after = tries[-1][1] if tries else None
    before = tagged(one, "CLOCK BEFORE")

    print("phase 1  %s" % p1)
    print("  clock before write   %s" % (before or "?"))
    print("  wrote                %s" % (wrote or "?"))
    for ty, got_s in tries:
        print("  clock after type %-3s %s" % (ty, got_s))
    w = clock(wrote)
    got = (marker(one, "STATUS AFTER", "Delay"),
           marker(one, "STATUS AFTER", "Repeat"))
    print("  Delay/Repeat after   %s / %s   (wrote %d / %d)"
          % (got[0], got[1], dly, rpt))

    clock_ok = False
    if w is not None:
        for ty, got_s in tries:
            c = clock(got_s, w)
            if c is not None and c.year == w.year:
                clock_ok = True
                after = got_s
                print("  type %s took" % ty)
    cmos_ok = got == (dly, rpt)
    print()
    stale = bool(tries) and "24" not in [t for t, _ in tries]
    print("  WRITABLE: CMOS RAM %s, clock %s"
          % ("yes" if cmos_ok else "NO",
             "yes" if clock_ok else ("not asked properly" if stale else "NO")))

    # The two halves of the chip fail separately and did (5.5b-septies):
    # the RAM took both markers while the clock rejected both writes and
    # went on ticking at year 197B. Judging the RAM by the clock was what
    # produced the wrong "the chip will not accept a write" on 2026-08-21.
    if not cmos_ok and not clock_ok:
        print("  Neither half takes a write with the machine powered. That")
        print("  is not a retention fault - the battery question does not")
        print("  arise until this passes. See spec 5.5b-quinquies.")
        return
    if stale:
        print("  THIS RECORD PREDATES THE FIX and says nothing about the")
        print("  clock: OSWORD &0F has no type 0, and type 8 wants \"hh:mm:ss\"")
        print("  alone, not the 24-character string it was handed. Re-run")
        print("  FBBATT - it uses type 24 now. See spec 5.5b-octies.")
    elif not clock_ok:
        print("  The clock rejects a write while the RAM accepts one, so")
        print("  the clock cannot answer the oscillator question below.")
        print("  CMOS retention is still testable, and is what matters for")
        print("  configuration surviving a power cut.")
    if not cmos_ok:
        print("  The markers did not take, so retention cannot be read from")
        print("  them. Check *CONFIGURE is reaching the chip at all.")

    if two is None:
        print()
        print("no %s yet - power OFF at the mains for five minutes or" % p2)
        print("more, power on WITHOUT holding R, and RUN FBBATT2.")
        return

    now = tagged(two, "CLOCK NOW")
    n = clock(now, w)
    got2 = (marker(two, "STATUS NOW", "Delay"),
            marker(two, "STATUS NOW", "Repeat"))
    print()
    print("phase 2  %s" % p2)
    print("  clock now            %s" % (now or "?"))
    print("  Delay/Repeat now     %s / %s   (wrote %d / %d)"
          % (got2[0], got2[1], dly, rpt))

    retained = cmos_ok and got2 == (dly, rpt)
    print()
    if cmos_ok:
        print("  RETAINED: CMOS %s" % ("yes" if retained else "NO"))
        if not retained:
            print("            A boot with R held restores the DEFAULT")
            print("            configuration, which reads exactly like a")
            print("            failure to retain. If R was held, this run")
            print("            proves nothing - redo phase 1 and cycle the")
            print("            power without it.")
    if not clock_ok:
        print("  RUNNING:  unaskable - the clock never took the write")
    elif n is None:
        print("  RUNNING:  NO - the clock does not even read as a date now")
    elif n <= w:
        print("  RUNNING:  NO - frozen at or before what was written")
    else:
        d = n - w
        print("  RUNNING:  clock advanced %s (%.1f minutes) since the write"
              % (d, d.total_seconds() / 60.0))
        print("            That must be about how long the machine spent off")
        print("            plus how long it has been on since. Much less and")
        print("            the oscillator is stopping when power goes.")
    print()
    if retained and clock_ok and n is not None and n > w:
        print("  VERDICT: battery backup is working, both halves.")
    elif retained:
        print("  VERDICT: the cell is backing up the CMOS RAM, which is what")
        print("  configuration needs. The clock is a separate fault in the")
        print("  same chip - it reads, it ticks, it will not be set.")
    elif cmos_ok:
        print("  VERDICT: the RAM takes a write and does not hold it. Flat or")
        print("  reversed cell, or an open circuit between it and the chip -")
        print("  measure across the cell IN the holder with the machine off.")
    else:
        print("  VERDICT: inconclusive - see the writable line above.")


if __name__ == "__main__":
    main()
