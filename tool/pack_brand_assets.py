"""Pack the original Flutter-rendered brand art for existing native icon slots."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
master = Image.open(root / 'assets/app-icon.png').convert('RGB')
assert master.size == (1024, 1024)
master.save(root / 'assets/app-icon.png')  # iOS marketing icons have no alpha channel.
catalog = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for slot in json.loads((catalog / 'Contents.json').read_text())['images']:
    pixels = round(float(slot['size'].split('x')[0]) * float(slot['scale'].rstrip('x')))
    master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(catalog / slot['filename'])
for density, pixels in {'mdpi':48, 'hdpi':72, 'xhdpi':96, 'xxhdpi':144, 'xxxhdpi':192}.items():
    target = root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target)
widget = root / 'ios/MealCaptureWidget/Assets.xcassets'
widget.mkdir(parents=True, exist_ok=True)
(widget / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
for name, source in [('RiceFriends', 'rice-friends.png'), ('MealCamera', 'camera.png')]:
    target = widget / f'{name}.imageset'
    target.mkdir(exist_ok=True)
    image = Image.open(root / 'assets/brand' / source)
    image.save(target / source)
    (target / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': source, 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2) + '\n')
print('Packed iOS, Android and widget assets from shared brand artwork.')
