#!/usr/bin/env python3
"""Extract Safe batch JSON that SafeTxUtil emitted to the console into real files.

`forge --zksync` cannot run the vm.serialize* / vm.writeJson / vm.ffi cheatcodes -- they
revert with "Invalid opcode, Not enough gas" at the very first serialize call. On those
chains SafeTxUtil instead builds the identical JSON with plain string concatenation and
logs it between markers:

    SAFE_TX_JSON_BEGIN <absolute path>
    {"version":"1.0", ...}
    SAFE_TX_JSON_END

This reads a forge run's stdout and writes each block to its path. forge may echo logs
more than once (simulation plus summary); repeats carry identical content, so the last
write wins and the result is stable either way.

Usage:  forge script ... | python3 extract-console-safe-json.py [--dry-run]
"""

import json
import os
import re
import sys

BEGIN = "SAFE_TX_JSON_BEGIN"
END = "SAFE_TX_JSON_END"

# forge indents console output and may prefix trace glyphs; strip them before matching.
TRACE_PREFIX = re.compile(r"^[\s│├└─╰╭|]*")


def clean(line):
    return TRACE_PREFIX.sub("", line.rstrip("\n")).strip()


def main():
    dry_run = "--dry-run" in sys.argv

    path = None
    buf = []
    written = {}
    malformed = []

    for raw in sys.stdin:
        line = clean(raw)

        if line.startswith(BEGIN):
            path = line[len(BEGIN):].strip()
            buf = []
            continue

        if line.startswith(END):
            if path is not None:
                written[path] = "".join(buf)
            path = None
            buf = []
            continue

        if path is not None and line:
            buf.append(line)

    if path is not None:
        print(f"WARN: unterminated {BEGIN} for {path} -- output truncated?", file=sys.stderr)

    for out_path, payload in sorted(written.items()):
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError as exc:
            malformed.append((out_path, str(exc)))
            continue

        n = len(parsed.get("transactions", []))
        if dry_run:
            print(f"  WOULD WRITE {os.path.basename(out_path)} ({n} txs)")
            continue

        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w") as fh:
            json.dump(parsed, fh, indent=4)
            fh.write("\n")
        print(f"  wrote {os.path.basename(out_path)} ({n} txs)")

    if malformed:
        print(f"ERROR: {len(malformed)} block(s) were not valid JSON:", file=sys.stderr)
        for out_path, err in malformed:
            print(f"  {out_path}: {err}", file=sys.stderr)
        return 1

    if not written:
        print("  no console JSON blocks found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
