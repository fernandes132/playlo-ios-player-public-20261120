"""Copy the same small native shell assets into both platform builds."""
from pathlib import Path
import shutil
import json

root = Path(__file__).resolve().parent
config = json.loads((root / 'shared/app-shell.json').read_text(encoding='utf-8'))
assert config['origin'] == 'https://playlo-social-games.fernandofrederiksen2.chatgpt.site'
style = root.parent / 'app/game-screen-v126.css'
if style.exists():
    shutil.copy2(style, root / 'shared/game-screen.css')
for platform in [root / 'android/app/src/main/assets/Shared', root / 'ios/Playlo/Shared']:
    platform.mkdir(parents=True, exist_ok=True)
    for name in ['app-shell.json', 'shell.js', 'youtube-player.html']:
        shutil.copy2(root / 'shared' / name, platform / name)
    # Included locally so keyboard/viewport handling is available before web publication.
    shutil.copy2(root / 'shared/game-screen.css', platform / 'game-screen.css')
print('Shared native assets prepared for Android and iPhone')

bundle = root / 'bundle'
assert (bundle / 'bundle-manifest.json').exists(), 'Run node scripts/build-mobile.mjs first; never package an empty web app.'
manifest = json.loads((bundle / 'bundle-manifest.json').read_text(encoding='utf-8'))
assert len(set(manifest['games'])) == 34 and manifest['studio'] and manifest['version'] == config['version']
expected = {entry['path'] for entry in manifest['files']} | {'bundle-manifest.json'}
actual = {file.relative_to(bundle).as_posix() for file in bundle.rglob('*') if file.is_file()}
assert actual == expected, 'Bundle contains missing or stale files; rebuild it first.'
import hashlib
for entry in manifest['files']:
    file = (bundle / entry['path']).resolve()
    assert file.is_relative_to(bundle.resolve()) and file.is_file()
    assert hashlib.sha256(file.read_bytes()).hexdigest() == entry['sha256'], entry['path']
for platform in [root / 'android/app/src/main/assets/Shared/Web', root / 'ios/Playlo/Shared/Web']:
    if platform.exists():
        assert platform.resolve().is_relative_to(root.resolve())
        shutil.rmtree(platform)
    shutil.copytree(bundle, platform)
print('Verified and embedded all 34 games, Studio and local database runtime')
