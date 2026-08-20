#!/usr/bin/env python3
"""findings:0; errors:2"""
import subprocess,sys
from pathlib import Path
a=sys.argv
if len(a)<3 or a[1]!='--root': raise SystemExit(2)
try:
    tool=Path(__file__).resolve().parents[1]/'scripts/doc-governance.py'
    rc=subprocess.call([sys.executable,tool,'--root',a[2],'audit','--check','xref',*a[3:]])
except OSError: raise SystemExit(2)
raise SystemExit(rc)
