#!/usr/bin/env python3
"""Run native tests with synthetic loopback credentials; never read hosted .env files."""
import argparse, json, os, plistlib, subprocess, time
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--fixtures', required=True)
p.add_argument('--products', default='/tmp/amountly-ios-build/Build/Products')
p.add_argument('--device',required=True)
p.add_argument('--only')
a=p.parse_args()
f=json.loads(Path(a.fixtures).read_text())
if f.get('url') != 'http://127.0.0.1:54321': raise SystemExit('Refusing non-local fixture configuration')
products=Path(a.products).resolve()
source=next(x for x in products.glob('AmountlyIntegration_*.xctestrun') if not x.name.endswith('-local.xctestrun'))
config=plistlib.loads(source.read_bytes())
env={'AMOUNTLY_LOCAL_TESTING':'1','AMOUNTLY_XCTEST':'1','AMOUNTLY_LOCAL_URL':'http://127.0.0.1:54331','AMOUNTLY_LOCAL_ANON_KEY':f['anonKey'],'AMOUNTLY_TEST_FIXTURES':json.dumps(f,separators=(',',':'))}
for name,target in config.items():
 if name.startswith('__'): continue
 target.setdefault('EnvironmentVariables',{}).update(env)
 target['ParallelizationEnabled']=False
local=products/'AmountlyIntegration-local.xctestrun'
fd=os.open(local,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'wb') as out: plistlib.dump(config,out)
result=f'/tmp/amountly-native-{int(time.time())}.xcresult'
log=Path('/tmp/amountly-native-integration.log')
command=['xcodebuild','test-without-building','-xctestrun',str(local),'-destination',f'platform=iOS Simulator,id={a.device}','-parallel-testing-enabled','NO','-resultBundlePath',result]
if a.only: command.append('-only-testing:'+a.only)
try:
 fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'w') as out: code=subprocess.call(command,stdout=out,stderr=subprocess.STDOUT)
 print(f'Native integration exit={code}; log={log}; results={result}')
finally: local.unlink(missing_ok=True)
raise SystemExit(code)
