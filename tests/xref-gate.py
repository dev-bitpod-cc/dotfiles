#!/usr/bin/env python3
import argparse, subprocess, sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--root', required=True)
p.add_argument('files', nargs='*')
try:
    a = p.parse_args()
    tool = Path(__file__).resolve().parents[1] / 'scripts/doc-governance.py'
    raise SystemExit(subprocess.call([sys.executable, str(tool), '--root', a.root, 'audit', '--check', 'xref', *a.files]))
except (OSError, SystemExit) as error:
    if isinstance(error, SystemExit):
        raise
    print(f'xref core error: {error}', file=sys.stderr)
    raise SystemExit(2)
