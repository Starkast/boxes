#!/usr/bin/env python3
"""Drive an unattended OpenBSD/arm64 install over the QEMU serial console.

The installer is booted from the miniroot image; this script talks to it over a
QEMU chardev socket, drops to (S)hell, fetches the autoinstall response file
from the local HTTP server and runs `install -a -f`. Output is read from the
chardev's logfile (which QEMU always drains), while the socket is used to type
input -- and MUST be drained too, or OpenBSD's pl011 driver busy-waits on a full
TX FIFO and the guest hangs.
"""
import re
import socket
import sys
import threading
import time

SOCK, LOGF = sys.argv[1], sys.argv[2]

sock = socket.socket(socket.AF_UNIX)
sock.connect(SOCK)


def _drain_sock():
    try:
        while sock.recv(65536):
            pass
    except OSError:
        pass


threading.Thread(target=_drain_sock, daemon=True).start()

log = open(LOGF, "rb")
buf = bytearray()


def drain():
    data = log.read()
    if data:
        buf.extend(data)
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def expect(pattern, timeout, label=""):
    rx = re.compile(pattern.encode())
    deadline = time.time() + timeout
    while time.time() < deadline:
        drain()
        if rx.search(buf):
            print(f"\n[+] {label or pattern}", flush=True)
            return True
        time.sleep(0.3)
    print(f"\n[!] timeout waiting for {label or pattern}", flush=True)
    return False


def send(text, settle=1.0):
    sock.sendall(text.encode())
    time.sleep(settle)
    drain()


def forget():
    del buf[:]  # so the next expect() only sees new output


# 1) Reach the installer banner, then drop to a shell. The menu prompt has no
#    trailing newline and must be answered promptly, so send "s" right away and
#    confirm with an echoed marker (its output line, not the command echo).
if not expect(r"installation program", 300, "installer banner"):
    sys.exit(2)
time.sleep(1.5)
forget()
for attempt in range(1, 6):
    send("s\r", 1.5)
    send("echo OBSD_SHELL_OK\r", 1.2)
    if expect(r"OBSD_SHELL_OK\r?\n# ", 6, f"shell #{attempt}"):
        break
    time.sleep(1)
else:
    sys.exit(3)

# 2) Bring up the network (DHCP via QEMU's user networking).
forget()
send("ifconfig vio0 autoconf\r", 4.0)
send("ifconfig vio0\r", 1.0)
if not expect(r"inet 10\.0\.2\.", 40, "DHCP lease"):
    sys.exit(4)

# 3) Fetch the response file (retry; abort a hung transfer with Ctrl-C).
for attempt in range(1, 6):
    send("\x03", 0.5)
    forget()
    send("ftp -o install.conf http://10.0.2.2:8000/install.conf\r", 2.0)
    if expect(r"\d+ bytes received", 20, f"response file #{attempt}"):
        break
else:
    sys.exit(5)

# 4) Run the unattended install, then power off.
print("\n[*] install -a -f install.conf", flush=True)
forget()
send("install -a -f install.conf\r", 2.0)
if not expect(r"CONGRATULATIONS", 1500, "install completion"):
    sys.exit(6)
time.sleep(2)
forget()
send("halt -p\r", 2.0)
expect(r"(halted|Powering off|press any key)", 60, "halt")
time.sleep(3)
drain()
print("\n[*] install stage complete", flush=True)
