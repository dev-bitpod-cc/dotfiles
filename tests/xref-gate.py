#!/usr/bin/env python3
"""Xref wrapper: finding stdout/exit 0; scanner or argument error exit 2."""
import subprocess, sys
from pathlib import Path
a = sys.argv
if len(a) < 3 or a[1] != '--root':
    raise SystemExit(2)
try:
    tool = Path(__file__).resolve().parents[1] / 'scripts/doc-governance.py'
    raise SystemExit(subprocess.call([sys.executable, str(tool), '--root', a[2], 'audit', '--check', 'xref', *a[3:]]))
except OSError as error:
    print(f'xref core error: {error}', file=sys.stderr)
    raise SystemExit(2)
