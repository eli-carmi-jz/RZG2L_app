#!/usr/bin/env python3
# Receives one file over the USB serial gadget. Protocol: "SIZE <n> <dest>\n" + n raw bytes -> "OK <sha256>\n".
import os, sys

DEV = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyGS0"
os.system("stty -F %s raw -echo -ixon -ixoff -crtscts" % DEV)
fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)


def read_line():
    buf = b""
    while not buf.endswith(b"\n"):
        buf += os.read(fd, 1)
    return buf.decode().strip()


cmd, size, dest = read_line().split(" ", 2)
if cmd != "SIZE":
    os.write(fd, b"ERR bad header\n")
    sys.exit(1)
size = int(size)
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
with open(dest, "wb") as f:
    left = size
    while left:
        chunk = os.read(fd, min(65536, left))
        f.write(chunk)
        left -= len(chunk)
os.chmod(dest, 0o755)
sha = os.popen("sha256sum '%s'" % dest).read().split()[0]
os.write(fd, ("OK %s\n" % sha).encode())
