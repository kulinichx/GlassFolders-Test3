#!/usr/bin/env python3
"""Offline proof that Optics Lab 04 changes background pixels, not rim color.

Requires Pillow + a C compiler. Does NOT capture a live screen or call Metal.
Render a synthetic high-contrast grid before/after using GFRefractionMath.c.
"""
import ctypes
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / 'Experiments' / 'lab04-refraction-preview.png'

class Geometry(ctypes.Structure):
    _fields_ = [(k, ctypes.c_float) for k in (
        'captureWidthPx', 'captureHeightPx', 'originXPx', 'originYPx',
        'panelWidthPx', 'panelHeightPx', 'cornerRadiusPx', 'bevelWidthPx',
        'maxOffsetPx', 'dispersionPx')]

class Mapping(ctypes.Structure):
    _fields_ = [('rUV', ctypes.c_float * 2),
                ('gUV', ctypes.c_float * 2),
                ('bUV', ctypes.c_float * 2),
                ('coverage', ctypes.c_float),
                ('displacementPx', ctypes.c_float * 2),
                ('chromaDisplacementPx', ctypes.c_float * 2)]


def bilinear(im, u, v, channel):
    w, h = im.size
    x = max(0., min(w - 1., u * w - 0.5))
    y = max(0., min(h - 1., v * h - 0.5))
    x0, y0 = int(x), int(y)
    x1, y1 = min(x0 + 1, w - 1), min(y0 + 1, h - 1)
    dx, dy = x - x0, y - y0
    p = im.load()
    return ((1-dy)*((1-dx)*p[x0,y0][channel] + dx*p[x1,y0][channel]) +
            dy*((1-dx)*p[x0,y1][channel] + dx*p[x1,y1][channel]))


def main():
    output = Path(sys.argv[1]) if len(sys.argv)>1 else DEFAULT_OUT
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        so = Path(tmp) / 'refraction.so'
        subprocess.run(['cc', '-std=c11', '-O2', '-shared', '-fPIC',
                        str(ROOT/'Experiments'/'GFRefractionMath.c'), '-lm', '-o', str(so)],
                       check=True)
        lib = ctypes.CDLL(str(so))
        fn = lib.GFRefractionMapPixel
        fn.argtypes = (ctypes.POINTER(Geometry), ctypes.c_float, ctypes.c_float,
                       ctypes.POINTER(Mapping))
        fn.restype = ctypes.c_int
        w,h=600,360
        base=Image.new('RGB',(w,h),(22,38,57))
        draw=ImageDraw.Draw(base)
        # Vertical and horizontal thin lines make displacements measurable.
        for x in range(0,w,20):
            draw.line((x,0,x,h),fill=(166,206,228),width=2)
        for y in range(0,h,20):
            draw.line((0,y,w,y),fill=(107,174,199),width=2)
        for x in range(0,w,80):
            draw.line((x,0,x,h),fill=(245,233,147),width=3)
        origin=(160,82)
        panel=(280,204)
        geo=Geometry(w,h,*origin,*panel,33,16,8.0,0.65)
        result=base.copy()
        px=result.load(); src=base.load()
        maximum=0.0
        moved_pixels=0
        for y in range(panel[1]):
            for x in range(panel[0]):
                uv=Mapping()
                assert fn(ctypes.byref(geo),x+0.5,y+0.5,ctypes.byref(uv))
                a=uv.coverage
                if not a: continue
                samples=(bilinear(base,*uv.rUV,0),bilinear(base,*uv.gUV,1),
                         bilinear(base,*uv.bUV,2))
                pxy=(origin[0]+x,origin[1]+y)
                prev=src[pxy]
                px[pxy]=tuple(int(round(a*s+(1-a)*v)) for s,v in zip(samples,prev))
                motion=(uv.displacementPx[0]**2 + uv.displacementPx[1]**2)**0.5
                maximum=max(maximum,motion)
                moved_pixels+=(motion>0.15)
        # A narrow neutral outline shows the panel boundary, but no colorful
        # fake specular texture is introduced by this optical comparison.
        for img in [base,result]:
            d=ImageDraw.Draw(img)
            d.rounded_rectangle((*origin,origin[0]+panel[0]-1,origin[1]+panel[1]-1),
                                radius=33,outline=(200,215,221),width=1)
        combined=Image.new('RGB',(w*2+24,h+50),(12,18,29))
        combined.paste(base,(0,50)); combined.paste(result,(w+24,50))
        text=ImageDraw.Draw(combined)
        text.text((20,18),'Original capture (identity sampling)',fill='white')
        text.text((w+44,18),'Optics Lab 04 (texture coordinate displacement)',fill='white')
        combined.save(output)
        print(f'Preview: {output}')
        print(f'Maximum displacement: {maximum:.2f}px; moved pixels: {moved_pixels}')
        assert maximum>0.5 and moved_pixels>1000

if __name__ == '__main__':
    main()
