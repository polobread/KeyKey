#!/usr/bin/env python3
"""Import the supplied illustration and crop only the supplied poster's header."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image, ImageCms

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--character', type=Path, required=True)
parser.add_argument('--poster', type=Path, required=True)
parser.add_argument('--header-bottom', type=int, default=454,
                    help='Exclusive bottom pixel of the poster header (default: 454).')
args = parser.parse_args()
out = Path(__file__).resolve().parent
character = out/'user-character-illustration.png'
header = out/'user-title-six-platforms.png'
if args.character.resolve() != character.resolve():
    shutil.copyfile(args.character, character)
poster = Image.open(args.poster)
assert 0 < args.header_bottom <= poster.height
box = (0, 0, poster.width, args.header_bottom)
profile = Image.open(out/'01-six-platforms.png').info.get('icc_profile')
profile = profile or ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
poster.crop(box).save(header, icc_profile=profile, optimize=True)
records = []
for src,dest,crop in [(args.character,character,None),(args.poster,header,list(box))]:
    records.append({
        'file':dest.name, 'kind':'維護者提供的宣傳設計素材，非產品操作截圖',
        'source_name':src.name, 'source_size':list(Image.open(src).size),
        'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
        'crop':crop, 'size':list(Image.open(dest).size), 'mode':Image.open(dest).mode,
        'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),
        'processing':'原圖保留透明背景與內容' if crop is None else '僅保留上方標題、人物與六平台圖示；原比例裁切，不改寫內容'
    })
(out/'user-art-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
for item in records:
    print(item['file'],item['size'],item['mode'])
