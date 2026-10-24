"""Deterministic CPU reference for GFRefraction.metal math.

Not a replacement for compiling Metal on iPad. Used to verify transparency,
coord transforms, and whether shader-style displacement changes image pixels.
"""
from __future__ import annotations
import math
import numpy as np
from PIL import Image, ImageDraw


def make_backdrop(width=520, height=370):
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    color = np.stack([
        95 + 42*np.sin(xx/29) + 30*np.cos(yy/35),
        95 + 43*np.sin((xx+yy)/47) + 37*np.cos(xx/21),
        125 + 48*np.cos((yy-xx)/41) + 30*np.sin(yy/17)
    ], axis=-1)
    color += np.where((xx//13+yy//13)%2==0,10,-10)[...,None]
    image=Image.fromarray(np.uint8(np.clip(color,0,255)), 'RGB')
    draw=ImageDraw.Draw(image)
    for i in range(8):
        x=25+55*i
        draw.ellipse((x,30+11*i,x+30,58+11*i),fill=(220,90+14*i,70+18*i))
        draw.rectangle((20+50*i,260-8*i,45+50*i,290-8*i),fill=(60+20*i,150,210-15*i))
    return np.asarray(image).astype(np.float32)/255.0


def _rounded_sdf(x,y,width,height,radius):
    hx,hy=width*0.5,height*0.5
    radius=np.clip(radius,0,min(hx,hy))
    qx=np.abs(x-hx)-(hx-radius)
    qy=np.abs(y-hy)-(hy-radius)
    return np.hypot(np.maximum(qx,0),np.maximum(qy,0))+np.minimum(np.maximum(qx,qy),0)-radius


def _smoothstep(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)


def _sample_rgb(backdrop,x,y):
    h,w=backdrop.shape[:2]
    x=np.clip(x,0,w-1); y=np.clip(y,0,h-1)
    x0=np.floor(x).astype(np.int32); y0=np.floor(y).astype(np.int32)
    x1=np.minimum(x0+1,w-1); y1=np.minimum(y0+1,h-1)
    dx=(x-x0)[...,None];dy=(y-y0)[...,None]
    return (backdrop[y0,x0]*(1-dx)*(1-dy)+backdrop[y0,x1]*dx*(1-dy)
            +backdrop[y1,x0]*(1-dx)*dy+backdrop[y1,x1]*dx*dy)


def render_ring(backdrop, rect=(105,75,268,190), radius=29, bevel=17,
                displacement=7, dispersion=.35, sheen=.10, opacity=.78,
                axes=(1,0,0,1), translation=(0,0)):
    """Return premultiplied RGBA float array sized to the card."""
    x0,y0,w,h=rect
    yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    xx+=.5; yy+=.5
    sd=_rounded_sdf(xx,yy,w,h,radius)
    inside=np.maximum(-sd,0)
    coverage=_smoothstep(0,1.5,-sd)
    rim=1-_smoothstep(1,bevel,inside)
    alpha=(coverage*rim*np.clip(opacity,0,.94)).astype(np.float32)
    gx=_rounded_sdf(xx+1,yy,w,h,radius)-_rounded_sdf(xx-1,yy,w,h,radius)
    gy=_rounded_sdf(xx,yy+1,w,h,radius)-_rounded_sdf(xx,yy-1,w,h,radius)
    length=np.hypot(gx,gy)
    nx=np.divide(gx,length,out=np.zeros_like(gx),where=length>1e-4)
    ny=np.divide(gy,length,out=np.zeros_like(gy),where=length>1e-4)
    bend=np.clip(displacement,0,24)*rim*rim
    sx=x0+xx-bend*nx
    sy=y0+yy-bend*ny
    ax,ay,bx,by=axes;tx,ty=translation
    px=sx*ax+sy*bx+tx-.5
    py=sx*ay+sy*by+ty-.5
    rgb=_sample_rgb(backdrop,px,py)
    spread=np.clip(dispersion,0,2)*rim
    if dispersion>0:
        snx=nx*ax+ny*bx;sny=nx*ay+ny*by
        plus=_sample_rgb(backdrop,px+spread*snx,py+spread*sny)
        minus=_sample_rgb(backdrop,px-spread*snx,py-spread*sny)
        rgb[...,0]=plus[...,0]
        rgb[...,2]=minus[...,2]
    gloss=np.clip(sheen,0,.22)*rim**3
    rgb=np.clip(rgb+(1-rgb)*gloss[...,None],0,1)
    premult=rgb*alpha[...,None]
    return np.concatenate([premult,alpha[...,None]],axis=2)


def composite(backdrop,ring,rect):
    x,y,w,h=rect
    out=backdrop.copy()
    a=ring[...,3:]
    out[y:y+h,x:x+w]=ring[...,:3]+out[y:y+h,x:x+w]*(1-a)
    return np.uint8(np.clip(out*255+0.5,0,255))


def create_demo(outdir):
    from pathlib import Path
    import json
    outdir=Path(outdir);outdir.mkdir(parents=True,exist_ok=True)
    scene=make_backdrop()
    rect=(105,75,268,190)
    ring=render_ring(scene,rect)
    after=composite(scene,ring,rect)
    before=np.uint8(scene*255+0.5)
    diff=np.abs(after.astype(np.int16)-before.astype(np.int16))
    alpha=ring[...,3]
    # Deliberate regression checks: no rectangular overlay, just curved rim.
    assert alpha[95,134] == 0, 'card center must be fully transparent'
    assert alpha[1,134] > .05, 'near-edge must have visible effect'
    assert alpha[0,0] == 0, 'outside rounded corner must be transparent'
    changed=int(np.count_nonzero(diff.max(axis=2)>4))
    assert changed>1000, 'optical displacement should be noticeable on textured scene'
    assert int(np.count_nonzero(alpha>.10))>1000
    assert np.all(ring[...,:3] <= alpha[...,None]+1e-6), 'RGBA must be premultiplied'
    Image.fromarray(before,'RGB').save(outdir/'before.png')
    Image.fromarray(after,'RGB').save(outdir/'after.png')
    Image.fromarray(np.uint8(np.clip(diff*3,0,255)),'RGB').save(outdir/'difference_x3.png')
    report={'changed_rgb_pixels_gt4':changed,
            'alpha_center':float(alpha[95,134]),
            'alpha_edge':float(alpha[1,134]),
            'alpha_outside_corner':float(alpha[0,0]),
            'alpha_max':float(alpha.max()),
            'premultiplied_alpha':True,
            'source':'synthetic scene only; NOT a live iPad/Metal render'}
    (outdir/'metrics.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    return report

if __name__=='__main__':
    import sys
    print(create_demo(sys.argv[1] if len(sys.argv)>1 else 'tests/output'))
