#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Playlo.xcodeproj -scheme Playlo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath SimulatorData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
DEVICE=$(xcrun simctl list devices available --json | python3 -c 'import json,sys,re;d=json.load(sys.stdin);c=[(tuple(map(int,re.findall(r"[0-9]+",key))),x["udid"]) for key,items in d["devices"].items() if "iOS" in key for x in items if x["name"].startswith("iPhone")];assert c,"No available iPhone simulator";print(max(c)[1])')
xcrun simctl boot "$DEVICE"
trap 'xcrun simctl shutdown "$DEVICE" || true' EXIT
xcrun simctl bootstatus "$DEVICE" -b
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
trap 'diagnostics; xcrun simctl shutdown "$DEVICE" || true' EXIT
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
