#!/usr/bin/env python3
"""Run app-hosted AI tests; --live opts into paid synthetic QA requests.

Credentials are taken only from AMOUNTLY_AI_QA_EMAIL/PASSWORD in the environment,
never command-line arguments. No financial records are created. Build the
AmountlyIntegration scheme first; see IntegrationTests/README.md.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--products', default='/tmp/amountly-ai-verification-build/Build/Products')
parser.add_argument('--device', required=True)
parser.add_argument('--live', action='store_true')
parser.add_argument('--inspect-ui', action='store_true')
args = parser.parse_args()
products = Path(args.products).resolve()
source = next(p for p in products.glob('AmountlyIntegration_*.xctestrun'))
config = plistlib.loads(source.read_bytes())
env = {'AMOUNTLY_XCTEST': '1'}
if args.inspect_ui:
    env['AMOUNTLY_AI_UI_INSPECTION'] = '1'
if args.live:
    for key in ['AMOUNTLY_AI_QA_EMAIL', 'AMOUNTLY_AI_QA_PASSWORD']:
        if not os.environ.get(key):
            raise SystemExit('Live AI tests require QA credentials in the environment.')
        env[key] = os.environ[key]
    env['AMOUNTLY_AI_LIVE_TESTING'] = '1'
for name, target in config.items():
    if name.startswith('__'):
        continue
    target.setdefault('EnvironmentVariables', {}).update(env)
    target['ParallelizationEnabled'] = False
fd, raw_path = tempfile.mkstemp(prefix='amountly-ai-', suffix='.xctestrun', dir=products)
path = Path(raw_path)
with os.fdopen(fd, 'wb') as out:
    plistlib.dump(config, out)
result = f'/tmp/amountly-ai-native-{int(time.time())}.xcresult'
log = Path('/tmp/amountly-ai-native.log')
try:
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as out:
        code = subprocess.call(['xcodebuild', 'test-without-building', '-xctestrun', str(path),
            '-destination', f'platform=iOS Simulator,id={args.device}', '-parallel-testing-enabled', 'NO',
            '-only-testing:AmountlyIntegrationTests/' + ('AICaptureInspectionTests' if args.inspect_ui else 'AIParityTests'), '-resultBundlePath', result], stdout=out, stderr=subprocess.STDOUT)
    print(f'AI native tests exit={code}; log={log}; results={result}')
finally:
    path.unlink(missing_ok=True)
raise SystemExit(code)
