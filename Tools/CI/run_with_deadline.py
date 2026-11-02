#!/usr/bin/env python3
"""Keep a CI command's deadline inside the workflow's artifact-export budget."""
import argparse
import os
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if args.seconds <= 0 or not command:
        parser.error('a positive deadline and command are required')
    process = subprocess.Popen(command, start_new_session=(os.name == 'posix'))
    started = time.monotonic()
    while True:
        remaining = args.seconds - (time.monotonic() - started)
        if remaining <= 0:
            break
        try:
            return process.wait(timeout=min(60, remaining))
        except subprocess.TimeoutExpired:
            print(f'[CI deadline] command still running, elapsed {int(time.monotonic() - started)}s', flush=True)
    print('[CI deadline] stopping command to preserve logs and result artifacts', flush=True)
    if os.name == 'posix':
        listing = subprocess.run(['ps', '-axo', 'pid,ppid,pgid,etime,stat,comm'], capture_output=True, text=True)
        for row in listing.stdout.splitlines():
            fields = row.split(None, 5)
            if len(fields) >= 3 and fields[2] == str(process.pid):
                print(row, flush=True)
    try:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGINT)
        else:
            process.terminate()
        process.wait(timeout=30)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.wait()
    return 124


if __name__ == '__main__':
    sys.exit(main())
