"""A small GDB remote-serial-protocol client for Azahar's (Citra's) GDB stub.

Development only: reads the running game's memory so hidden numbers (timers, odds, tables
built by code) can be measured. Never writes game bytes into the mod; only the numbers.

Usage:
  python tools/gdbrsp.py ping                       [--port 24689]
  python tools/gdbrsp.py regs
  python tools/gdbrsp.py read <addr hex> <len>      (hex dump)
  python tools/gdbrsp.py dump <addr hex> <len> <out.bin>
  python tools/gdbrsp.py cont                       (resume a stopped target)

As a module: `with Rsp(port) as r: r.read(addr, n)`.
Azahar: Emulation > Configure > Debug > Enable GDB stub (port 24689 by default). The game
stops while a client is attached; leaving a `with Rsp()` block (and every CLI command)
continues it. `python tools/gdbrsp.py cont` frees a game left stopped.
"""
import socket
import sys


class RspError(Exception):
    pass


class Rsp:
    def __init__(self, port=24689, host="127.0.0.1", timeout=5.0, resume=True):
        self.resume = resume
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self.buf = b""

    def __enter__(self):
        return self

    def __exit__(self, *a):
        # the stub stops the game while a client is attached: always let it run again
        if self.resume:
            try:
                self.cont()
            except Exception:
                pass
        self.close()

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def _send(self, data):
        body = data.encode("latin-1")
        packet = b"$" + body + b"#" + ("%02x" % (sum(body) & 0xFF)).encode()
        for _ in range(3):
            self.sock.sendall(packet)
            ack = self._read_byte()
            if ack == b"+":
                return
        raise RspError("no ack for %r" % data)

    def _read_byte(self):
        while not self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RspError("connection closed")
            self.buf += chunk
        b, self.buf = self.buf[:1], self.buf[1:]
        return b

    def _recv(self):
        # skip to '$'
        while self._read_byte() != b"$":
            pass
        body = b""
        while True:
            c = self._read_byte()
            if c == b"#":
                break
            body += c
        self._read_byte()
        self._read_byte()
        self.sock.sendall(b"+")
        # run-length decoding: X*n repeats X (n - 29) more times
        out, i = b"", 0
        while i < len(body):
            if body[i:i + 1] == b"*" and out:
                out += out[-1:] * (body[i + 1] - 29)
                i += 2
            else:
                out += body[i:i + 1]
                i += 1
        return out.decode("latin-1")

    def cmd(self, data):
        self._send(data)
        return self._recv()

    def halt_reason(self):
        return self.cmd("?")

    def regs(self):
        raw = self.cmd("g")
        if raw.startswith("E"):
            raise RspError("g: " + raw)
        # ARM: r0..r15 as little-endian 32-bit words, then more
        words = [int.from_bytes(bytes.fromhex(raw[i:i + 8]), "little") for i in range(0, min(len(raw), 16 * 8), 8)]
        return words

    def read(self, addr, n, chunk=0x800):
        out = b""
        while n > 0:
            k = min(n, chunk)
            raw = self.cmd("m%x,%x" % (addr, k))
            if raw.startswith("E") and len(raw) == 3:
                raise RspError("m %08x: %s" % (addr, raw))
            out += bytes.fromhex(raw)
            addr += k
            n -= k
        return out

    def cont(self):
        self._send("c")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    port = int(argv[argv.index("--port") + 1]) if "--port" in argv else 24689
    with Rsp(port) as r:
        what = argv[1]
        # the stub answers other packets only after the stop reason has been asked
        reason = r.halt_reason()
        if what == "ping":
            print("halt reason:", reason)
            print("supported:", r.cmd("qSupported:swbreak+;hwbreak+")[:200])
        elif what == "regs":
            for i, v in enumerate(r.regs()):
                print("r%-2d %08x" % (i, v))
        elif what == "read":
            addr, n = int(argv[2], 16), int(argv[3], 0)
            data = r.read(addr, n)
            for i in range(0, len(data), 16):
                row = data[i:i + 16]
                print("%08x  %-48s %s" % (addr + i, row.hex(" "), "".join(chr(c) if 32 <= c < 127 else "." for c in row)))
        elif what == "dump":
            addr, n, out = int(argv[2], 16), int(argv[3], 0), argv[4]
            open(out, "wb").write(r.read(addr, n))
            print("wrote", out)
        elif what == "cont":
            r.cont()
            print("continued")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
