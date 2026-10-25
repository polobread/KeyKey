#!/usr/bin/env python3
"""Rebuild the Threads carousel from real, unmodified KeyKey source screenshots.

Requires Python 3, Pillow, numpy and reportlab. No generative-image service.
All geometry and original screenshots stay editable in the companion SVGs.
"""
from __future__ import annotations
import base64, hashlib, html, io, json, os, shutil
from pathlib import Path
from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms
from reportlab.graphics.barcode.qr import QrCodeWidget

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
CFG = json.loads((OUT/'design.json').read_text())
W,H = CFG['canvas']
S = 2
C = CFG['colors']; COPY = CFG['copy']
ASSETS = OUT/'assets'; ASSETS.mkdir(exist_ok=True)
ICC = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
FONT = os.environ.get('KEYKEY_FONT')
if not FONT:
    mac = list(Path('/System/Library/AssetsV2').glob('com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc'))
    linux = [Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')]
    FONT = str(next((p for p in mac+linux if p.exists()), ''))
if not FONT:
    raise SystemExit('Set KEYKEY_FONT to a Traditional Chinese font, e.g. PingFang.ttc.')
IS_PINGFANG = 'PingFang' in FONT

@lru_cache(None)
def font(size, weight='regular', scale=S):
    index = ({'regular':2,'medium':6,'bold':10}[weight] if IS_PINGFANG else 3)
    return ImageFont.truetype(FONT,round(size*scale),index=index)

def rgb(h): return tuple(int(h.lstrip('#')[i:i+2],16) for i in (0,2,4))
def e(s): return html.escape(str(s),quote=True)

def srgb(im):
    profile=im.info.get('icc_profile')
    if profile:
        try: return ImageCms.profileToProfile(im,ImageCms.ImageCmsProfile(io.BytesIO(profile)),ImageCms.createProfile('sRGB'),outputMode='RGB')
        except (ValueError,OSError,ImageCms.PyCMSError): pass
    return im.convert('RGB')

def source_image(key):
    return srgb(Image.open(ASSETS/(key+'.png')))

manifest=[]
for key,item in CFG['sources'].items():
    src=ROOT/item['path']; dest=ASSETS/(key+'.png')
    if src.exists(): shutil.copyfile(src,dest)
    elif not dest.exists(): raise FileNotFoundError(src)
    im=Image.open(dest)
    manifest.append({'key':key,'original_path':item['path'],'local_copy':str(dest.relative_to(OUT)),
      'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'size':list(im.size),'credit':item['credit'],
      'crop':item.get('crop'),'processing':'僅裁切與等比例縮放；依來源色彩描述轉成 sRGB；不改寫介面內容'})
(OUT/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

class Canvas:
    def __init__(self,name):
        self.name=name;self.svg=[];self.texts=[];self.images=[]
        y,x=np.mgrid[0:H,0:W]
        t=np.clip(.65*y/H+.35*x/W,0,1)[...,None]
        a=np.array(rgb('#FCFDFF'));b=np.array(rgb('#EAF2FF'))
        arr=(a*(1-t)+b*t).astype('uint8')
        self.im=Image.fromarray(arr,'RGB').resize((W*S,H*S),Image.Resampling.BICUBIC)
        self.draw=ImageDraw.Draw(self.im)
        self.svg.append('<rect width="1080" height="1350" fill="url(#bg)"/>')
    def rr(self,x,y,w,h,r,fill,stroke=None,sw=1):
        self.draw.rounded_rectangle((round(x*S),round(y*S),round((x+w)*S),round((y+h)*S)),radius=r*S,fill=fill,outline=stroke,width=round(sw*S))
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"'if stroke else '')+'/>')
    def gradient(self,x,y,w,h,r,start,end):
        yy,xx=np.mgrid[0:round(h*S),0:round(w*S)]
        t=(.4*yy/max(1,h*S-1)+.6*xx/max(1,w*S-1))[...,None]
        a=np.array(rgb(start));b=np.array(rgb(end))
        pic=Image.fromarray((a*(1-t)+b*t).astype('uint8'),'RGB')
        mask=Image.new('L',pic.size,0)
        ImageDraw.Draw(mask).rounded_rectangle((0,0,pic.width-1,pic.height-1),radius=r*S,fill=255)
        self.im.paste(pic,(round(x*S),round(y*S)),mask);self.draw=ImageDraw.Draw(self.im)
        gid=f'grad{len(self.svg)}'
        self.svg.append(f'<defs><linearGradient id="{gid}" x2="1" y2="1"><stop stop-color="{start}"/><stop offset="1" stop-color="{end}"/></linearGradient></defs><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#{gid})"/>')
    def ellipse(self,x,y,w,h,fill,stroke=None,sw=1):
        self.draw.ellipse((round(x*S),round(y*S),round((x+w)*S),round((y+h)*S)),fill=fill,outline=stroke,width=round(sw*S))
        self.svg.append(f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w/2}" ry="{h/2}" fill="{fill or "none"}"'+(f' stroke="{stroke}" stroke-width="{sw}"'if stroke else '')+'/>')
    def line(self,points,fill,width=3):
        self.draw.line([(round(x*S),round(y*S))for x,y in points],fill=fill,width=round(width*S),joint='curve')
        self.svg.append(f'<polyline points="'+ ' '.join(f'{x},{y}'for x,y in points)+f'" fill="none" stroke="{fill}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')
    def text(self,value,x,y,size=28,color=None,weight='regular',align='left',max_width=None):
        color=color or C['ink'];f=font(size,weight)
        width=self.draw.textlength(value,font=f)/S
        if max_width is not None and width>max_width+.2:
            raise ValueError(f'{self.name}: text too wide: {value}: {width:.1f} > {max_width}')
        if align=='center': x-=width/2
        elif align=='right': x-=width
        box=self.draw.textbbox((round(x*S),round(y*S)),value,font=f,anchor='lt')
        if min(box[:2])<0 or box[2]>W*S or box[3]>H*S:
            raise ValueError(f'Text out of bounds: {value}: {box}')
        self.draw.text((round(x*S),round(y*S)),value,font=f,fill=color,anchor='lt')
        self.texts.append({'text':value,'x':x,'y':y,'size':size,'bbox':[round(v/S,2)for v in box]})
        self.svg.append(f'<text x="{x:.3f}" y="{y}" font-size="{size}" font-weight="'+{'regular':'400','medium':'500','bold':'600'}[weight]+f'" fill="{color}" dominant-baseline="text-before-edge">{e(value)}</text>')
    def shadow(self,x,y,w,h,r):
        lay=Image.new('RGBA',self.im.size,(0,0,0,0));d=ImageDraw.Draw(lay)
        d.rounded_rectangle((x*S,(y+7)*S,(x+w)*S,(y+h+7)*S),radius=r*S,fill=(24,61,116,17))
        lay=lay.filter(ImageFilter.GaussianBlur(13*S))
        self.im=Image.alpha_composite(self.im.convert('RGBA'),lay).convert('RGB');self.draw=ImageDraw.Draw(self.im)
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#183D74" opacity=".08" filter="url(#shadow)"/>')
    def image(self,key,x,y,w,h=None,r=0,crop=None):
        im=source_image(key)
        crop=crop or CFG['sources'][key].get('crop') or [0,0,*im.size]
        assert 0<=crop[0]<crop[2]<=im.width and 0<=crop[1]<crop[3]<=im.height
        cw,ch=crop[2]-crop[0],crop[3]-crop[1]
        target_h=round(w*ch/cw)
        if h is not None and abs(target_h-h)>1:raise ValueError('Images must keep aspect ratio')
        h=target_h
        self.images.append({'key':key,'x':round(x),'y':round(y),'w':round(w),'h':h,'r':r,'crop':crop})
        cl=f'clip{len(self.images)}'
        self.svg.append(f'<defs><clipPath id="{cl}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath></defs>')
        encoded=base64.b64encode((ASSETS/(key+'.png')).read_bytes()).decode()
        self.svg.append(f'<g clip-path="url(#{cl})"><svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="{crop[0]} {crop[1]} {cw} {ch}" preserveAspectRatio="xMidYMid meet" overflow="hidden"><image width="{im.width}" height="{im.height}" href="data:image/png;base64,{encoded}"/></svg></g>')
    def brand(self,page):
        self.rr(64,54,46,46,12,'#FFFFFF',C['line'])
        self.image('icon',68,58,38,r=8,crop=[0,0,512,512])
        self.text(f'琦琦輸入法 {CFG["version"]}',124,65,25,weight='medium')
        self.text(f'{page:02d} / 03',1016,67,22,C['muted'],align='right')
    def save(self):
        out=self.im.resize((W,H),Image.Resampling.LANCZOS)
        for p in self.images:
            pic=source_image(p['key']).crop(p['crop']).resize((p['w'],p['h']),Image.Resampling.LANCZOS)
            if p['r']:
                mask=Image.new('L',(p['w']*S,p['h']*S),0)
                ImageDraw.Draw(mask).rounded_rectangle((0,0,p['w']*S-1,p['h']*S-1),radius=p['r']*S,fill=255)
                mask=mask.resize(pic.size,Image.Resampling.LANCZOS);out.paste(pic,(p['x'],p['y']),mask)
            else:out.paste(pic,(p['x'],p['y']))
        out.save(OUT/(self.name+'.png'),icc_profile=ICC,optimize=True)
        defs='<defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#FCFDFF"/><stop offset="1" stop-color="#EAF2FF"/></linearGradient><filter id="shadow" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="13"/></filter></defs>'
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="PingFang TC,Noto Sans CJK TC,Noto Sans TC,sans-serif">'+defs+''.join(self.svg)+'</svg>'
        (OUT/(self.name+'.svg')).write_text(svg)
        return out,{'page':self.name,'texts':self.texts,'images':self.images}

# Page 01 — lively six-platform collage, made entirely from documented screenshots.
# Linux and FreeBSD share one row; neither platform borrows the other's screen.
c=Canvas('01-six-platforms')
c.ellipse(770,-170,480,480,'#E0ECFF');c.ellipse(-110,1000,290,290,'#E4F2FF')
c.rr(64,35,252,36,18,'#E5EEFF');c.text('正式版・六平台支援',83,42,21,C['blue'],weight='medium')
c.shadow(64,100,88,88,22);c.rr(64,100,88,88,22,'#FFFFFF',C['line'])
c.image('icon',69,105,78,r=18,crop=[0,0,512,512])
c.text(COPY['cover_title'],174,112,61,weight='bold')
c.text(CFG['version'],1016,96,83,C['blue'],weight='bold',align='right')
c.text('熟悉的中文輸入，走到六大平台',64,226,49,weight='bold',max_width=952)
c.text('好打注音・傳統注音・倉頡・簡易',64,300,26,C['muted'])
c.rr(889,293,127,38,19,'#FFF0DF');c.text('正式 1.3.7',952,301,18,'#9D5420',weight='medium',align='center')
collage=[
 ('macOS','mac_smart','#276BF4','#243FAD'),
 ('Windows','windows_emoji','#177BC3','#15529F'),
 ('Linux','linux_smart','#C76E40','#AC4455'),
 ('FreeBSD','freebsd_smart','#8E54BF','#584397'),
 ('iPhone / iPad','ios_smart','#A752AC','#6D4DAB'),
 ('Android','android_smart','#198D80','#1A636C')
]
for i,(title,key,start,end) in enumerate(collage):
    title=CFG['platforms'][i]['name']
    x=64+(i%2)*488;y=363+(i//2)*280
    c.shadow(x,y,464,264,26);c.gradient(x,y,464,264,26,start,end)
    c.text(title,x+22,y+17,30,'#FFFFFF',weight='bold',max_width=420)
    if i<4:
        c.image(key,x+16,y+65,432,r=8)
    else:
        c.image(key,x+20,y+59,180,r=10)
        c.text('整句順著打',x+221,y+89,29,'#FFFFFF',weight='bold')
        c.text('點字就能改',x+221,y+137,26,'#FFFFFF')
        c.text('官方模擬器',x+221,y+213,18,'#FFFFFF')
c.text('真實軟體畫面局部；手機為官方模擬器，Linux 為 VM',64,1202,19,C['muted'])
c.rr(64,1243,8,54,4,C['warm'])
c.text(COPY['cover_footer'],92,1253,29,weight='medium',max_width=924)
c.text('01 / 03',1016,1310,20,C['muted'],align='right')
cover,report1=c.save()

# Page 02 — single contiguous crops; the candidate glyphs are original pixels.
c=Canvas('02-smart-phonetic-cangjie');c.brand(2)
c.text(COPY['feature_title'],64,150,61,weight='bold',max_width=952)
c.gradient(64,255,952,518,28,'#DFEDFF','#EAF4FF')
c.gradient(88,278,455,48,14,'#266CF5','#3154B8');c.text(COPY['smart_title'],106,285,29,'#FFFFFF',weight='bold')
c.text(COPY['smart_description'],88,338,29,C['muted'])
c.image('mac_smart',88,395,904)
c.text(CFG['sources']['mac_smart']['credit'],88,792,22,C['muted'])
c.line([(64,839),(1016,839)],C['line'],1)
c.gradient(64,864,286,51,14,'#198D80','#1A636C');c.text(COPY['cangjie_title'],83,874,30,'#FFFFFF',weight='bold')
c.rr(730,853,286,71,20,'#FFF0DF');c.text(COPY['cangjie_example'],995,864,45,'#A45B26',weight='bold',align='right')
c.text(COPY['cangjie_description'],64,933,29,C['muted'])
c.gradient(64,990,952,277,24,'#E0F3EF','#EFF8F3')
c.image('android_cangjie',80,1030,920)
c.text(COPY['cangjie_note'],64,1293,21,C['muted'])
c.text('Android 官方模擬器・1.3.7・局部',1016,1293,20,C['muted'],align='right')
features,report2=c.save()

# Page 03 — large keyboard crops with no invented phone shell or UI.
c=Canvas('03-mobile-downloads');c.brand(3)
c.text(COPY['mobile_title'][0],64,148,60,weight='bold')
c.text(COPY['mobile_title'][1],64,229,60,C['blue'],weight='bold')
for key,x,title in [('ios_smart',64,'iPhone / iPad'),('android_smart',552,'Android')]:
    c.shadow(x,352,464,577,26);c.rr(x,352,464,577,26,'#FFFFFF',C['line'])
    colors=('#9255BA','#6447AD') if key=='ios_smart' else ('#1B9487','#176776')
    c.gradient(x+12,364,440,53,16,*colors)
    c.text(title,x+28,375,30,'#FFFFFF',weight='bold')
    c.image(key,x+16,424,432,r=8)
    c.text(CFG['sources'][key]['credit'],x+24,898,20,C['muted'],max_width=416)
c.text('正式 1.3.7 來源・畫面局部・保留原始鍵盤與候選',64,954,23,C['muted'])
qr_report=[]
for i,d in enumerate(CFG['downloads']):
    x=64+i*325
    c.rr(x,1010,302,273,24,'#FFFFFF',C['line'])
    c.rr(x+20,1024,262,5,2,['#8C56B7','#198D80',C['blue']][i])
    sz=19 if i==2 else 26
    c.text(d['name'],x+151,1041,sz,weight='bold',align='center',max_width=280)
    for j,line in enumerate(d['lines']):c.text(line,x+151,1083+j*28,22,C['muted'],align='center',max_width=280)
    q=QrCodeWidget(d['url'],barLevel='M');q.qr.make();matrix=q.qr.modules;n=len(matrix);module=3;border=4
    qr=Image.new('RGB',((n+border*2)*module,)*2,'#FFFFFF');draw=ImageDraw.Draw(qr)
    for yy,row in enumerate(matrix):
        for xx,v in enumerate(row):
            if v:draw.rectangle(((xx+border)*module,(yy+border)*module,(xx+border+1)*module-1,(yy+border+1)*module-1),fill='#132B50')
    qr_key=f'qr-{i+1}';qr_path=ASSETS/(qr_key+'.png');qr.save(qr_path,icc_profile=ICC)
    # QR is positioned without resampling so every module remains an integer square.
    CFG['sources'][qr_key]={'path':'','credit':'正式下載網址 QR Code'}
    qx=round(x+151-qr.width/2);qy=round(1207-qr.height/2)
    c.image(qr_key,qx,qy,qr.width,crop=[0,0,*qr.size])
    qr_report.append({'asset':str(qr_path.relative_to(OUT)),'url':d['url'],'modules':n,'module_pixels':module,'bbox':[qx,qy,qx+qr.width,qy+qr.height]})
c.text(COPY['freebsd_note'],64,1294,23,C['muted'])
c.text('03 / 03',1016,1294,22,C['muted'],align='right')
mobile,report3=c.save()

# A phone-sized overview: each thumbnail is exactly 360 × 450.
preview=Image.new('RGB',(1168,530),'#EAF0F8');dr=ImageDraw.Draw(preview)
for i,im in enumerate([cover,features,mobile]):
    preview.paste(im.resize((360,450),Image.Resampling.LANCZOS),(24+i*380,16))
    dr.text((24+i*380,484),['01 六平台總覽','02 好打注音與倉頡','03 手機與下載'][i],font=font(18,'medium',1),fill=C['ink'])
preview.save(OUT/'preview-all.png',icc_profile=ICC,optimize=True)
(OUT/'layout-report.json').write_text(json.dumps({'size':[W,H],'font':font(30).getname(),'pages':[report1,report2,report3],'qr_codes':qr_report},ensure_ascii=False,indent=2)+'\n')
for path in [OUT/(n+'.png')for n in ['01-six-platforms','02-smart-phonetic-cangjie','03-mobile-downloads']]:
    im=Image.open(path);assert im.size==(1080,1350) and im.mode=='RGB' and im.info.get('icc_profile')
    print(path.name,im.size,im.mode,'sRGB',path.stat().st_size)
print('preview-all.png and editable SVGs generated. Original source files were only read.')
