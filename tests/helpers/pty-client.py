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
    pty-client.py <socket> <session> [--press KEY ...] [--hold SECONDS]

--press writes bytes to the pty MASTER, which is the only way to trigger a key
binding. `tmux send-keys` writes to the pane's pty instead — that is input to
the program running there, and tmux never sees it as a keypress. Trying to
trigger prefix+M-s with send-keys did exactly nothing for that reason.

Key syntax: `C-a` for control characters, `M-s` for meta (ESC prefix), anything
else is sent literally.

Writes the client's pid to stdout once tmux reports it attached, so the caller
can kill it. Exits non-zero if the client never attaches, rather than leaving
the caller to assume it did.
"""

import os
import pty
import re
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


def encode_key(key):
    """Turn a tmux-style key name into the bytes a terminal would send."""
    if key.startswith("C-") and len(key) == 3:
        # Control characters are the letter with the top three bits cleared:
        # C-a is 0x01, C-b is 0x02, and so on.
        return bytes([ord(key[2].lower()) & 0x1F])
    if key.startswith("M-") and len(key) == 3:
        # Meta is conventionally sent as ESC followed by the key.
        return b"\x1b" + key[2].encode()
    named = {
        "Enter": b"\r",
        "Escape": b"\x1b",
        "Space": b" ",
        "BSpace": b"\x7f",
        "Tab": b"\t",
    }
    if key in named:
        return named[key]
    return key.encode()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sock, session = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]

    keys, hold, capture, until = [], 3.0, False, None
    i = 0
    while i < len(args):
        if args[i] == "--press":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                keys.append(args[i])
                i += 1
        elif args[i] == "--hold":
            hold = float(args[i + 1])
            i += 2
        elif args[i] == "--capture":
            capture = True
            i += 1
        elif args[i] == "--until":
            # Hold until this text appears rather than for a fixed time. A
            # status-line message is drawn whenever the work behind it finishes,
            # which on a slow machine is after any hold you would have guessed.
            until = args[i + 1]
            capture = True
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
    # Generous: a loaded CI runner can take several seconds to get a client up,
    # and failing here silently looks like "the binding did nothing".
    deadline = time.time() + 30
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
    # a wedged client stops responding and looks like a hang. With --capture the
    # drained bytes are kept and printed at the end, which is how a test reads
    # what the STATUS LINE actually said. `tmux show-messages` is not that: it
    # returns the server's command log, which is why an earlier attempt at this
    # fell back to a stubbed tmux and could only assert that display-message had
    # been called, not what a person would have seen.
    os.set_blocking(fd, False)
    seen = bytearray()

    def drain():
        try:
            chunk = os.read(fd, 65536)
            if capture and chunk:
                seen.extend(chunk)
        except (BlockingIOError, OSError):
            pass

    for key in keys:
        os.write(fd, encode_key(key))
        # Terminals are asynchronous: tmux has to read the byte, match it against
        # the key table, and run whatever it is bound to. Pressing the next key
        # immediately can outrun that.
        time.sleep(float(os.environ.get("PTY_KEY_DELAY", "0.6")))
        drain()

    if not capture:
        print(pid, flush=True)

    end = time.time() + hold
    while time.time() < end:
        drain()
        if until is not None and until in seen.decode("utf-8", "replace"):
            break
        time.sleep(0.1)

    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)

    if capture:
        # Strip escape sequences so a caller can grep for plain text; the status
        # line arrives wrapped in cursor positioning and colour codes.
        text = seen.decode("utf-8", "replace")
        text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
        text = re.sub(r"\x1b[\]P^_].*?(\x07|\x1b\\)", "", text, flags=re.S)
        text = re.sub(r"\x1b[()][A-Za-z0-9]", "", text)
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
