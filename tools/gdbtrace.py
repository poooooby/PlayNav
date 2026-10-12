"""Trace calls in the running game (Azahar's GDB stub) with timestamps: a breakpoint at each
address; on a stop, log r0-r3 and lr, lift it, single-step, re-arm and run on. The game runs
at full speed between stops. Development only.

    python tools/gdbtrace.py <seconds> <out.txt> <addr>[:name] ...

Example (Super Training's home-screen messages; r2 is the line of text file 27):
    python tools/gdbtrace.py 600 trace.txt 761340:show 7bb6dc:cheer_hidden 7bb5cc:cheer_reset 7bbf84:finish
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gdbrsp import Rsp  # noqa: E402


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    secs, out = float(argv[1]), argv[2]
    points = {}
    for spec in argv[3:]:
        addr, _, name = spec.partition(":")
        points[int(addr, 16)] = name or addr
    log = open(out, "w", buffering=1)
    t0 = time.time()
    with Rsp(timeout=2.0) as g:
        g.halt_reason()
        for a in points:
            log.write("Z0 %x: %s\n" % (a, g.cmd("Z0,%x,4" % a)))
        g.cont()
        try:
            while time.time() - t0 < secs:
                try:
                    g._recv()
                except Exception:
                    continue
                r = g.regs()
                pc = r[15]
                log.write("%8.2f %-14s r0=%08x r1=%08x r2=%08x r3=%08x lr=%08x\n" % (
                    time.time() - t0, points.get(pc, "%08x" % pc), r[0], r[1], r[2], r[3], r[14]))
                g.cmd("z0,%x,4" % pc)
                g._send("s")
                g._recv()
                g.cmd("Z0,%x,4" % pc)
                g.cont()
        finally:
            # halt the running game to lift the breakpoints (leaving the block resumes it)
            g.sock.sendall(b"\x03")
            try:
                g._recv()
            except Exception:
                pass
            for a in points:
                try:
                    g.cmd("z0,%x,4" % a)
                except Exception:
                    pass
    log.write("done\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
