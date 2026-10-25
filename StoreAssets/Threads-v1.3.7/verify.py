#!/usr/bin/env python3
"""Validate delivered art, original source hashes, bounds, and screenshot pixels."""
import hashlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageCms, ImageChops

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
report = json.loads((HERE/'layout-report.json').read_text())
manifest = json.loads((HERE/'source-manifest.json').read_text())
for item in manifest:
    for p in [ROOT/item['original_path'], HERE/item['local_copy']]:
        assert hashlib.sha256(p.read_bytes()).hexdigest() == item['sha256'], str(p)
for page in report['pages']:
    name = page['page']
    im = Image.open(HERE/(name+'.png'))
    assert im.size == (1080,1350) and im.mode == 'RGB', name
    assert 'sRGB' in ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(im.info['icc_profile']))), name
    svg = ET.parse(HERE/(name+'.svg')).getroot()
    assert svg.attrib['viewBox'] == '0 0 1080 1350', name
    for t in page['texts']:
        left,top,right,bottom = t['bbox']
        assert 0 <= left < right <= 1080 and 0 <= top < bottom <= 1350, t
    for p in page['images']:
        x,y,w,h = [p[k] for k in ['x','y','w','h']]
        assert 0 <= x < x+w <= 1080 and 0 <= y < y+h <= 1350, p
        src = Image.open(HERE/'assets'/(p['key']+'.png'))
        if src.info.get('icc_profile'):
            src = ImageCms.profileToProfile(src,ImageCms.ImageCmsProfile(io.BytesIO(src.info['icc_profile'])),ImageCms.createProfile('sRGB'),outputMode='RGB')
        else:
            src = src.convert('RGB')
        l,t,r,b = p['crop']
        assert abs(w*(b-t)/(r-l)-h) <= 0.5, p
        expected = src.crop((l,t,r,b)).resize((w,h),Image.Resampling.LANCZOS)
        actual = im.crop((x,y,x+w,y+h))
        # Rounded presentation corners blend with the page; compare the interior.
        margin = p['r']+3 if p['r'] else 0
        box = (margin,margin,w-margin,h-margin)
        assert ImageChops.difference(expected.crop(box),actual.crop(box)).getbbox() is None, p
    print(name+': size, sRGB, SVG, bounds and original screenshot pixels verified')
preview = Image.open(HERE/'preview-all.png')
assert preview.size == (1168,530) and preview.info.get('icc_profile')
print('All source hashes match the repository originals. Preview verified.')
