import json,math
from pathlib import Path
P=Path(__file__).parent
H=600; floors=100; SPACING=6.; DIAMETER=200.; R=100.
bands=[0,150,300,450,600]
def outer(y):
 t=(y%150)/150
 u=abs((t-.38)/(.38 if t<.38 else .62))
 return 25+75*u**1.7
def inner(y):return outer(y)*.55
levels=[dict(level=i+1,z=i*SPACING,width=round(outer(i*SPACING)*2,3),depth=round(outer(i*SPACING)*2,3),atriumDiameter=inner(i*SPACING)*2,terraceDepth=outer(i*SPACING)*.23,outerRadius=outer(i*SPACING),roomRadius=outer(i*SPACING)*.78,coreRadius=outer(i*SPACING)*.89) for i in range(floors)]
data=dict(diameter=DIAMETER,height=H,spacing=SPACING,segments=192,bands=bands,levels=levels,blockLength=100)
# Four continuous exterior stair ribbons; artistic circulation geometry.
STAIR_R=96.; STAIR_WIDTH=4.; TURN=.16
def frame_radius(y):return STAIR_R
def stair_point(floor,route,j=0):
 t=route*math.pi/2+(floor+j/44)*TURN
 rises=min(j,18)+max(0,min(j-22,18))
 return [STAIR_R*math.cos(t),floor*6+rises/6,STAIR_R*math.sin(t)]
frame=[]
for floor in range(100):
 for route in range(4):
  for j in range(44):
   a,b=stair_point(floor,route,j),stair_point(floor,route,j+1)
   frame.append(dict(a=a,b=b,width=STAIR_WIDTH,kind='stair tread' if b[1]>a[1] else 'landing'))
# Bridges meet a landing on every occupied floor; roof landing also connects.
for floor in range(101):
 y=floor*6
 for route in range(4):
  end=stair_point(floor,route);theta=route*math.pi/2+floor*TURN;start=(outer(y)-.5)
  frame.append(dict(a=[start*math.cos(theta),y,start*math.sin(theta)],b=end,width=STAIR_WIDTH,kind='floor bridge'))
data['frameSegments']=frame
data['frameBands']=bands
data['stairWidth']=STAIR_WIDTH
data['stairRoutes']=4
(P/'design.js').write_text('const DESIGN='+json.dumps(data,separators=(',',':'))+';')
D=P/'drawings';D.mkdir(exist_ok=True)
def head(title,subtitle,code,tall=False):
 h=1700 if tall else 850;foot=h-95
 return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 {h}"><defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><path d="M0 0V6" stroke="#718088" stroke-width="1"/></pattern></defs><style>text{{font-family:Arial,sans-serif;fill:#243e49}}.small{{font-size:12px;letter-spacing:1px}}.line{{fill:none;stroke:#254451;stroke-width:1.2}}.fine{{fill:none;stroke:#82969b;stroke-width:.6}}.dash{{fill:none;stroke:#82969b;stroke-width:.7;stroke-dasharray:7 6}}</style><rect width="1200" height="{h}" fill="#f6f4ee"/><rect x="25" y="25" width="1150" height="{h-50}" class="fine"/><text x="55" y="67" font-size="27">STRUCTURE / 100</text><text x="55" y="92" class="small">{title} · {subtitle}</text><path d="M55 115H1145 M55 {foot}H1145" class="fine"/><text x="55" y="{foot+30}" class="small">THE COMMON VOID / GLASS + CONCRETE / TWO-BLOCK MAXIMUM WIDTH</text><text x="55" y="{foot+52}" font-size="10">ART STUDY / Imagined dimensions in metres. Architectural expression, not construction documentation.</text><text x="1030" y="{foot+35}" font-size="22">{code}</text>'''
def plan(i):
 y=i*SPACING;ir=inner(y);rr=outer(y);s=2.44;cx=425;cy=422
 a=[head(f'LEVEL {i+1:03d} / TERRACE PLAN',f'+{y:.2f} m',f'P-{i+1:03d}')]
 a.append(f'<circle cx="{cx}" cy="{cy}" r="{rr*s}" fill="#dce8e8" stroke="#163843" stroke-width="2"/><circle cx="{cx}" cy="{cy}" r="{rr*.78*s}" fill="#e8dfce" stroke="#5b7b86"/><circle cx="{cx}" cy="{cy}" r="{ir*s}" fill="#f6f4ee" stroke="#244b58" stroke-width="2"/><circle cx="{cx}" cy="{cy}" r="{(ir+1.2)*s}" class="fine"/>')
 for n in range(24):
  t=n*math.pi/12;pr=ir+2;xx=cx+pr*s*math.cos(t);yy=cy+pr*s*math.sin(t)
  a.append(f'<circle cx="{xx}" cy="{yy}" r="1.6" fill="#ad6848"/>')
 # Stair landings and walkways connect this exact floor datum.
 fr=STAIR_R
 for n in range(4):
  t=n*math.pi/2+i*TURN;xx=cx+fr*s*math.cos(t);yy=cy+fr*s*math.sin(t)
  a.append(f'<path d="M{cx+(rr-.5)*s*math.cos(t)} {cy+(rr-.5)*s*math.sin(t)}L{xx} {yy}" stroke="#718578" stroke-width="{4*s}"/><circle cx="{xx}" cy="{yy}" r="{2*s}" fill="#526b60"/><text x="{xx+8}" y="{yy-8}" font-size="9">S{n+1}</text>')
 a.append(f'<text x="{cx}" y="{cy+4}" text-anchor="middle" font-size="10">VOID</text>')
 a.append(f'<path d="M{cx-rr*s} 700H{cx+rr*s}m0 -5v10M{cx-rr*s} 695v10" class="line"/><text x="{cx}" y="726" text-anchor="middle" class="small">{2*rr:.2f} m / THIS LEVEL</text>')
 notes=['01 / Glass outer enclosure','02 / Enclosed perimeter rooms','03 / Shared inward-facing terrace','04 / Transparent atrium balustrade','05 / Four exterior stair landings','06 / Open, unobstructed centre','',f'Terrace depth / {rr*.78-ir:.2f} m',f'Atrium diameter / {ir*2:.2f} m','Floor-to-floor / 6.00 m','Terraces follow the hourglass curve.','Four deeply pinched 25-floor bays.','4 m stairways / bridges every floor.']
 for k,t in enumerate(notes):a.append(f'<text x="760" y="{220+28*k}" font-size="12">{t}</text>')
 a.append('<path d="M760 680h122m-122 -5v10m61 -10v10m61 -10v10" class="line"/><text x="760" y="703" font-size="11">0　　　　　 25　　　　 50 m</text></svg>')
 return ''.join(a)
for i in range(floors):(D/f'plan-{i+1:02d}.svg').write_text(plan(i))
def elevation(section=False,side=False):
 a=[head('ATRIUM SECTION A—A' if section else ('EAST ELEVATION' if side else 'SOUTH ELEVATION'),'100 STORIES / ROOF +600 m','A-301' if section else ('A-202' if side else 'A-201'),True)]
 s=2.12;cx=555;base=1510
 ys=[j*.5 for j in range(1201)]
 if not section:
  pts=[(cx-outer(y)*s,base-y*s) for y in ys]+[(cx+outer(y)*s,base-y*s) for y in ys[::-1]]
  a.append('<polygon points="'+' '.join(f'{x:.3f},{y:.3f}' for x,y in pts)+'" fill="#dfebeb" stroke="#254451" stroke-width="2"/>')
 for i in range(floors):
  y=i*SPACING;zz=base-y*s;r=outer(y)*s;ir=inner(y)*s
  if section:
   for sign in [-1,1]:
    xa=cx-r if sign<0 else cx+ir;xb=cx-ir if sign<0 else cx+r
    a.append(f'<path d="M{xa} {zz}H{xb}" stroke="#294854" stroke-width="1"/>')
    xrail=cx+sign*ir;a.append(f'<path d="M{xrail} {zz}v-2.5" stroke="#6c9ba9" stroke-width=".7"/>')
  else:a.append(f'<path d="M{cx-r} {zz}H{cx+r}" stroke="#294854" stroke-width=".7"/>')
  if i%5==0 or i==99:a.append(f'<text x="825" y="{zz+3}" font-size="10">L{i+1:03d} / +{y:.0f} m</text>')
 for sign in [-1,1]:
  for ratio in ([.55,1] if section else [1]):
   pts=[f'{cx+sign*outer(y)*ratio*s:.3f},{base-y*s:.3f}' for y in ys]
   a.append('<path d="M'+' L'.join(pts)+'" fill="none" stroke="#365c60" stroke-width="1.5"/>')
 # Same frame geometry as the spatial model, projected orthographically.
 for seg in frame:
  if section and seg['a'][2]>0:continue
  pa,pb=seg['a'],seg['b'];axis=2 if side else 0
  a.append(f'<path d="M{cx+pa[axis]*s:.3f} {base-pa[1]*s:.3f}L{cx+pb[axis]*s:.3f} {base-pb[1]*s:.3f}" stroke="#5d7467" stroke-width="{seg["width"]*.8:.2f}" fill="none"/>')
 for y in bands:
  r=outer(y)*s;ir=inner(y)*s
  if section:
   for sign in [-1,1]:a.append(f'<path d="M{cx+sign*ir} {base-y*s}H{cx+sign*r}" stroke="#294854" stroke-width="2"/>')
  else:a.append(f'<path d="M{cx-r} {base-y*s}H{cx+r}" stroke="#294854" stroke-width="2"/>')
 a.append(f'<path d="M270 {base}V{base-H*s}" class="line"/><text x="250" y="940" transform="rotate(-90 250 940)" class="small">600 m / 100 STORIES AT 6 m</text><path d="M{cx-R*s} 1550H{cx+R*s}" class="line"/><text x="{cx}" y="1574" text-anchor="middle" class="small">200 m MAXIMUM / TWO IMAGINED 100 m BLOCKS</text><text x="55" y="164" font-size="12">Four deep hourglass bays follow the red-marked reference; circular floor plates narrow at each waist.</text><text x="55" y="187" font-size="12">Four 4 m-wide stair ribbons connect all 100 floors via landings and bridges; vertical ribs removed.</text></svg>')
 return ''.join(a)
for name,body in [('south-elevation.svg',elevation()),('east-elevation.svg',elevation(side=True)),('section.svg',elevation(True))]:(D/name).write_text(body)
(P/'floor-schedule.csv').write_text('Level,Proposed datum m,Width m,Depth m,Atrium diameter m,Terrace depth m\n'+'\n'.join(','.join(str(v[k]) for k in ['level','z','width','depth','atriumDiameter','terraceDepth']) for v in levels))
print('Generated 100 ring-floor plans, atrium section, two elevations, and schedule.')
