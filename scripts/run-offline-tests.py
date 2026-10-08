#!/usr/bin/env python3
"""Run explicitly selected native tests with mocks; no credentials or hosted data."""
import argparse
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--products', required=True)
parser.add_argument('--device', required=True)
args = parser.parse_args()
products = Path(args.products).resolve()
sources = sorted(products.glob('AmountlyIntegration_*-arm64.xctestrun'))
if not sources:
    raise SystemExit('Build AmountlyIntegration for the arm64 simulator first.')
config = plistlib.loads(sources[-1].read_bytes())
for name, target in config.items():
    if name.startswith('__'):
        continue
    target.setdefault('EnvironmentVariables', {}).update({
        'AMOUNTLY_XCTEST': '1', 'AMOUNTLY_AI_LIVE_TESTING': '0',
    })
    # Never inherit any live/test-account credentials from a generated bundle.
    for key in list(target['EnvironmentVariables']):
        if key.startswith('AMOUNTLY_AI_QA_') or key.startswith('AMOUNTLY_LOCAL_'):
            del target['EnvironmentVariables'][key]
    target['ParallelizationEnabled'] = False
fd, name = tempfile.mkstemp(prefix='AmountlyIntegration-offline-', suffix='.xctestrun', dir=products)
local = Path(name)
with os.fdopen(fd, 'wb') as output:
    plistlib.dump(config, output)
command = ['xcodebuild', 'test-without-building', '-xctestrun', str(local),
           '-destination', f'platform=iOS Simulator,id={args.device}', '-parallel-testing-enabled', 'NO']
for test in [
    'RenderParityTests',
    'AIParityTests/testTimeFormsKeepExactMinutesAndExplicitRange',
    'AIParityTests/testDashboardUsesBoundedAllowlistedSummaryWithoutReceiptLinks',
    'AIParityTests/testReceiptOCRProvidesSourceTextWithoutGuessingAmounts',
]:
    command.append('-only-testing:AmountlyIntegrationTests/' + test)
try:
    code = subprocess.call(command)
finally:
    local.unlink(missing_ok=True)
raise SystemExit(code)
