#!/usr/bin/env python3
"""Opt-in native receipt UI tests against disposable loopback fixtures only."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--fixtures', required=True)
parser.add_argument('--products', required=True)
parser.add_argument('--device', required=True)
args = parser.parse_args()
fixture_file = Path(args.fixtures)
if fixture_file.stat().st_mode & 0o077:
    raise SystemExit('Fixture credentials must be owner-only.')
fixture = json.loads(fixture_file.read_text())
if fixture.get('url') != 'http://127.0.0.1:54321':
    raise SystemExit('Refusing non-local fixture configuration.')
products = Path(args.products).resolve()
source = sorted(products.glob('AmountlyUI_*-arm64.xctestrun'))[-1]
config = plistlib.loads(source.read_bytes())
for name, target in config.items():
    if name.startswith('__'):
        continue
    target.setdefault('EnvironmentVariables', {}).update({
        'AMOUNTLY_LOCAL_UI_TESTING': '1',
        'AMOUNTLY_TEST_FIXTURES': json.dumps(fixture),
    })
    target['ParallelizationEnabled'] = False

# Fixture setup, before UI automation: place only the generated synthetic PNG
# in Files. No personal files or production receipt bytes are copied.
container = Path(subprocess.check_output([
    'xcrun', 'simctl', 'get_app_container', args.device, 'macaulay.alpha', 'data',
], text=True).strip())
source_image = container / 'Documents/qa-synthetic-receipt.png'
if not source_image.is_file():
    raise SystemExit('Run --prepare-receipt-ui with the integration runner first.')
groups = Path.home() / 'Library/Developer/CoreSimulator/Devices' / args.device / 'data/Containers/Shared/AppGroup'
destinations = []
for metadata in groups.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
    if plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier') == 'group.com.apple.FileProvider.LocalStorage':
        destinations.append(metadata.parent / 'File Provider Storage/qa-synthetic-receipt.png')
if len(destinations) != 1:
    raise SystemExit('Open Files once to initialize its local test container.')
destination = destinations[0]
destination.parent.mkdir(exist_ok=True)
if destination.exists():
    raise SystemExit('Remove the previous synthetic picker fixture before rerunning.')
shutil.copyfile(source_image, destination)
fd, name = tempfile.mkstemp(prefix='AmountlyUI-private-', suffix='.xctestrun', dir=products)
with os.fdopen(fd, 'wb') as output:
    plistlib.dump(config, output)
log_fd, log_name = tempfile.mkstemp(prefix='amountly-receipt-ui-', suffix='.log', dir='/private/tmp')
result = str(Path(log_name).with_suffix('.xcresult'))
try:
    with os.fdopen(log_fd, 'w') as output:
        code = subprocess.call([
            'xcodebuild', 'test-without-building', '-xctestrun', name,
            '-destination', f'platform=iOS Simulator,id={args.device}',
            '-parallel-testing-enabled', 'NO', '-resultBundlePath', result,
            '-only-testing:AmountlyUITests/ReceiptWorkflowUITests',
        ], stdout=output, stderr=subprocess.STDOUT)
finally:
    Path(name).unlink(missing_ok=True)
    destination.unlink(missing_ok=True)
print(f'Native UI exit={code}; log={log_name}; results={result}')
raise SystemExit(code)
