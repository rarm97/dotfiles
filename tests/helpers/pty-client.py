#!/usr/bin/env python3
"""Attach a real tmux client to a private socket, on a pseudo-terminal.

Several things tmux does are only reachable through an attached client:
switch-client (which is how tmux-resurrect restores active windows), key
bindings, and anything that draws on the status line. None of them can be
exercised by driving tmux from the command line, because a CLI invocation has
no client attached.

`script -q /dev/null tmux attach` is the usual shell trick for this and it did
not stick when tried here — list-clients kept reporting 0. Allocating the pty
directly is unambiguous: we can see the child's file descriptors are the tty.

Usage:
    pty-client.py <socket> <session> [--keys KEY ...] [--hold SECONDS]

Writes the client's pid to stdout once tmux reports it attached, so the caller
can kill it. Exits non-zero if the client never attaches, rather than leaving
the caller to assume it did.
"""

import os
import pty
import signal
import subprocess
import sys
import time


def clients(sock):
    r = subprocess.run(
        ["tmux", "-L", sock, "list-clients", "-F", "#{client_name}"],
        capture_output=True, text=True,
    )
    return [x for x in r.stdout.split("\n") if x.strip()]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sock, session = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]

    keys, hold = [], 3.0
    i = 0
    while i < len(args):
        if args[i] == "--keys":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                keys.append(args[i])
                i += 1
        elif args[i] == "--hold":
            hold = float(args[i + 1])
            i += 2
        else:
            i += 1

    # fork_pty gives the child a controlling terminal, which is the whole point:
    # tmux attach refuses to run without one.
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("tmux", ["tmux", "-L", sock, "attach", "-t", session])
        os._exit(1)

    # Wait for tmux itself to report the client, rather than sleeping and hoping.
    deadline = time.time() + 10
    attached = False
    while time.time() < deadline:
        if clients(sock):
            attached = True
            break
        time.sleep(0.2)

    if not attached:
        os.kill(pid, signal.SIGKILL)
        sys.exit("pty-client: no client attached after 10s")

    # Drain the client's output so tmux is never blocked on a full pty buffer;
    # a wedged client stops responding and looks like a hang.
    os.set_blocking(fd, False)

    def drain():
        try:
            os.read(fd, 65536)
        except (BlockingIOError, OSError):
            pass

    for key in keys:
        subprocess.run(["tmux", "-L", sock, "send-keys", "-t", session, key])
        time.sleep(0.3)
        drain()

    print(pid, flush=True)

    end = time.time() + hold
    while time.time() < end:
        drain()
        time.sleep(0.1)

    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)


if __name__ == "__main__":
    main()
