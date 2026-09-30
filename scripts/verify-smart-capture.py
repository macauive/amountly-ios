#!/usr/bin/env python3
"""Run the capture regression and AI boundary suite.

The old heuristic parsers have been removed. This now tests the actual shared
AI contracts and HTTP client rather than extracting private SwiftUI parsers.
Live QA and app-hosted checks use run-ai-tests.py separately.
"""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
raise SystemExit(subprocess.call([
    'swift', 'test', '--scratch-path', '/tmp/amountly-ai-rules-build',
    '--filter', 'AIContractTests',
], cwd=root))
