#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Playlo.xcodeproj -scheme Playlo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath SimulatorData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
# Use a disposable device: hosted images can contain partly migrated simulators.
# bootstatus may return zero even after reporting Data Migration Failed.
DEVICE=$(python3 - <<'PYBOOT'
import json,re,subprocess,sys,uuid

def sim(*args,**kwargs):
 return subprocess.run(['xcrun','simctl',*args],text=True,capture_output=True,**kwargs)

def listing(kind):
 return json.loads(sim('list',kind,'--json',check=True).stdout)[kind]

runtimes=[r for r in listing('runtimes') if r.get('isAvailable') and 'iOS' in r['name']]
assert runtimes,'No available iOS runtime'
runtimes.sort(key=lambda r:tuple(map(int,re.findall(r'[0-9]+',r['version']))),reverse=True)
types=[t for t in listing('devicetypes') if t['name'].startswith('iPhone')]
assert types,'No iPhone device type'
device_type=next((t for t in types if t['name']=='iPhone 17 Pro'),types[-1])
for attempt in range(2):
 runtime=runtimes[min(attempt,len(runtimes)-1)]
 device=sim('create','Playlo-QA-'+uuid.uuid4().hex[:8],device_type['identifier'],runtime['identifier'],check=True).stdout.strip()
 try:
  sim('boot',device,check=True)
  ready=sim('bootstatus',device,'-b',timeout=180)
  log=ready.stdout+'\n'+ready.stderr
  print(log,file=sys.stderr,flush=True)
  if ready.returncode or re.search(r'failed|failure',log,re.I):
   raise RuntimeError('Simulator did not finish migration successfully')
  print(device)
  break
 except (RuntimeError,subprocess.SubprocessError) as error:
  print('Disposable simulator start failed: '+str(error),file=sys.stderr,flush=True)
  sim('shutdown',device)
  sim('delete',device)
  if attempt==1:raise
PYBOOT
)
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl install "$DEVICE" SimulatorData/Build/Products/Debug-iphonesimulator/Playlo.app
mkdir -p .build
xcrun simctl launch --console "$DEVICE" nl.playlo.app --playlo-offline-smoke > .build/Playlo-launch.log 2>&1 &
LAUNCH_PID=$!
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" nl.playlo.app data)
mkdir -p .build
diagnostics() {
 xcrun simctl io "$DEVICE" screenshot .build/Playlo-simulator.png || true
 cp "$CONTAINER/Documents/Playlo-native-progress.json" .build/Playlo-native-progress.json 2>/dev/null || true
 if [ -f .build/Playlo-native-progress.json ]; then cat .build/Playlo-native-progress.json; else echo 'Native lifecycle progress missing'; fi
 xcrun simctl spawn "$DEVICE" log show --last 5m --style compact --predicate 'process == "Playlo"' > .build/Playlo-simulator.log 2>&1 || true
 cat .build/Playlo-launch.log || true
 mkdir -p .build/Playlo-crashes
 find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'Playlo*' -type f -exec cp {} .build/Playlo-crashes/ \; 2>/dev/null || true
 kill "$LAUNCH_PID" 2>/dev/null || true
}
trap 'diagnostics; xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
for _ in $(seq 1 150); do
 if [ -f "$CONTAINER/Documents/Playlo-native-smoke.json" ]; then break; fi
 if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then echo 'Native simulator process ended before reporting'; break; fi
 sleep 2
done
cp "$CONTAINER/Documents/Playlo-native-smoke.json" .build/Playlo-native-smoke.json
cat .build/Playlo-native-smoke.json
python3 -c 'import json;d=json.load(open(".build/Playlo-native-smoke.json"));assert d["status"]=="PASS" and d["isSecureContext"] and d["games"]==34 and len(d["graphics"])==29 and all(g["webgl2"] and g["ticks"]>0 for g in d["graphics"]) and d["hitQuiz"]["questions"]==8 and d["hitQuiz"]["minimumControlSize"] and d["hitQuiz"]["pauseResume"] and d["hitQuiz"]["skipScore"]==0,d'
xcrun simctl io "$DEVICE" screenshot .build/Playlo-simulator.png

# Verify the actual isolated YouTube controller and app identity in WKWebView.
xcrun simctl terminate "$DEVICE" nl.playlo.app
xcrun simctl launch --console "$DEVICE" nl.playlo.app --playlo-youtube-smoke > .build/Playlo-youtube-launch.log 2>&1 &
LAUNCH_PID=$!
for _ in $(seq 1 45); do
 if [ -f "$CONTAINER/Documents/Playlo-native-youtube.json" ]; then break; fi
 if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then break; fi
 sleep 1
done
cp "$CONTAINER/Documents/Playlo-native-youtube.json" .build/Playlo-native-youtube.json
cat .build/Playlo-native-youtube.json
python3 -c 'import json;d=json.load(open(".build/Playlo-native-youtube.json"));assert d["status"]=="PASS" and not d["hasAccountBridge"] and not d["playbackTested"],d'
xcrun simctl io "$DEVICE" screenshot .build/Playlo-native-youtube.png
