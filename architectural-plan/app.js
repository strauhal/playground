'use strict';
const $=id=>document.getElementById(id),canvas=$('model'),ctx=canvas.getContext('2d');
let view='model',angle=.67,tilt=.28,zoom=1,level=10,drag=null,scheduled=false,modelDirty=true;
const triangles=[];
function face(points,color,alpha=1,line=null){triangles.push({points,color,alpha,line});}
function profile(y){const t=((y%150)+150)%150/150,u=Math.abs((t-.38)/(t<.38?.38:.62));return 25+75*u**1.7;}
function ring(y,r=profile(y)){return Array.from({length:192},(_,i)=>{const t=i*Math.PI/96;return [r*Math.cos(t),y,r*Math.sin(t)]});}
function box(x,y,z,w,h,d,color){const p=[[x,y,z],[x+w,y,z],[x+w,y,z+d],[x,y,z+d],[x,y+h,z],[x+w,y+h,z],[x+w,y+h,z+d],[x,y+h,z+d]];for(const ids of [[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]])face(ids.map(i=>p[i]),color);}
function beam(a,b,width,color){
 const d=b.map((v,i)=>v-a[i]),len=Math.hypot(...d);if(len<.001)return;
 const n=d.map(v=>v/len),ref=Math.abs(n[1])<.9?[0,1,0]:[1,0,0];
 const cross=(u,v)=>[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
 let u=cross(n,ref),ul=Math.hypot(...u);u=u.map(v=>v/ul*width/2);let v=cross(n,u);
 const corners=p=>[[1,1],[-1,1],[-1,-1],[1,-1]].map(([i,j])=>p.map((x,k)=>x+i*u[k]+j*v[k]));
 const aa=corners(a),bb=corners(b);for(let i=0;i<4;i++){const k=(i+1)%4;face([aa[i],aa[k],bb[k],bb[i]],i%2?color:'#829287');}
}
function build(){triangles.length=0;const detail=view!=='city'&&$('detail').checked;const low=detail?Math.max(0,level-5):0;const high=detail?Math.min(100,level+4):(view!=='city'&&$('cut').checked?level:100);const opacity=+$('glass').value/100;
 if(!detail)box(-120,-1,-120,240,.5,240,'#d3d8d2');
 for(let l=low;l<high;l++){
  const d=DESIGN.levels[l],y=d.z,ir=d.atriumDiameter/2,outer=ring(y),inside=ring(y,ir),rooms=ring(y,d.roomRadius),back=ring(y+6),rail=ring(y+1.2,ir);const selected=l===level-1;
  for(let i=0;i<192;i++){const k=(i+1)%192;
   // Actual annular floor faces: no polygon ever spans the atrium.
   face([outer[i],outer[k],rooms[k],rooms[i]],selected?'#c99c7c':'#b9c3bc');
   face([rooms[i],rooms[k],inside[k],inside[i]],selected?'#d29a70':'#ded4bf');
   face([inside[i],inside[k],[inside[k][0],y-.28,inside[k][2]],[inside[i][0],y-.28,inside[i][2]]],'#547079',1,'#294854');
   face([outer[i],outer[k],[outer[k][0],y-.28,outer[k][2]],[outer[i][0],y-.28,outer[i][2]]],'#718b8c',1,'#294854');
   if(opacity>0)face([outer[i],outer[k],back[k],back[i]],'#acd4dd',opacity);
   face([inside[i],inside[k],rail[k],rail[i]],'#91bfca',.24);
  }
  // Interior room front: glass behind the shared terrace.
  const front=ring(y+5.5,d.roomRadius);
  for(let i=0;i<192;i+=4){const k=(i+4)%192;face([rooms[i],rooms[k],front[k],front[i]],'#a4c7ce',.13);}
 }
 // The roof is also an annulus. The centre remains open to sky.
 if(high===100&&!detail){const ro=ring(600),ri=ring(600,55);for(let i=0;i<192;i++){const k=(i+1)%192;face([ro[i],ro[k],ri[k],ri[i]],'#9ea99f');}}
 if(view==='city'||$('outerFrame').checked){
  for(const seg of DESIGN.frameSegments){const a=seg.a,b=seg.b;if(a[1]<low*6||b[1]>high*6)continue;
   const dx=b[0]-a[0],dz=b[2]-a[2],len=Math.hypot(dx,dz);if(len<.001)continue;
   const ux=-dz/len*seg.width/2,uz=dx/len*seg.width/2,y=b[1];
   const q=[[a[0]+ux,y,a[2]+uz],[a[0]-ux,y,a[2]-uz],[b[0]-ux,y,b[2]-uz],[b[0]+ux,y,b[2]+uz]];
   face(q,seg.kind==='landing'?'#a3afa2':'#788f7f');
   for(let i=0;i<4;i++){const k=(i+1)%4;face([q[i],q[k],[q[k][0],y-.5,q[k][2]],[q[i][0],y-.5,q[i][2]]],'#526c5d');}
   // Transparent guards follow both exposed edges of each stair ribbon.
   for(const [i,k] of [[0,3],[1,2]])face([q[i],q[k],[q[k][0],y+1.2,q[k][2]],[q[i][0],y+1.2,q[i][2]]],'#a9d0d7',.3);
  }
  for(const y of DESIGN.frameBands){if(y<low*6||y>high*6)continue;const ro=ring(y,100),ri=ring(y,97);for(let i=0;i<192;i++){const k=(i+1)%192;face([ro[i],ro[k],ri[k],ri[i]],'#647b6c');face([ro[i],ro[k],[ro[k][0],y-2,ro[k][2]],[ro[i][0],y-2,ro[i][2]]],'#526c5d');}}
 }
 if(view!=='city'&&$('sectionModel').checked){let keep=0;for(const f of triangles){if(f.points.reduce((sum,p)=>sum+p[2],0)/f.points.length<=0)triangles[keep++]=f;}triangles.length=keep;}
}
function cityScene(){
 const begin=triangles.length;
 box(-650,-3,-650,1300,1,1300,'#abb7b4');
 // A fictional street grid, surrounding the central civic plaza.
 for(let gx=-4;gx<=4;gx++)for(let gz=-4;gz<=4;gz++){
  if(Math.abs(gx)<=1&&Math.abs(gz)<=1)continue;
  const x=gx*130,z=gz*130,seed=Math.abs(gx*37+gz*59+gx*gz*13);
  box(x-52,-1,z-52,104,1,104,'#d7d8cf');
  const h=22+seed%95,w=42+seed%19,dep=40+(seed*7)%22;
  box(x-w/2,0,z-dep/2,w,h,dep,['#c4c7bd','#9db2b6','#b2b7b1','#d0c9bb'][seed%4]);
  box(x-w*.3,h,z-dep*.3,w*.6,5+seed%12,dep*.6,'#889b9b');
  for(let y=5;y<h-2;y+=5){
   face([[x-w/2-.1,y,z-dep/2],[x-w/2-.1,y+1.6,z-dep/2],[x-w/2-.1,y+1.6,z+dep/2],[x-w/2-.1,y,z+dep/2]],'#66848c',.6);
   face([[x-w/2,y,z+dep/2+.1],[x+w/2,y,z+dep/2+.1],[x+w/2,y+1.6,z+dep/2+.1],[x-w/2,y+1.6,z+dep/2+.1]],'#66848c',.6);
  }
  if(seed%3===0)box(x+37,0,z-25,4,2,9,'#bd7451');
 }
 // Plaza, garden beds and four approach paths.
 box(-170,-.7,-170,340,.5,340,'#e4ded0');
 for(let n=0;n<4;n++){
  const t=n*Math.PI/2;
  for(let j=-3;j<=3;j++){
   const x=150*Math.cos(t)-j*20*Math.sin(t),z=150*Math.sin(t)+j*20*Math.cos(t);
   box(x-5,0,z-5,10,.7,10,'#8d9e79');box(x-.7,.7,z-.7,1.4,5,1.4,'#82705c');
   const r=5.5,y=7;
   face([[x-r,y,z],[x,y+5,z],[x+r,y,z],[x,y-2,z+r]],'#698779');
   face([[x-r,y,z],[x,y+5,z],[x,y-2,z-r]],'#809982');
  }
 }
 // Move urban context into the same depth-sorted scene as the tower.
 return triangles.length-begin;
}
function project(p,w,h){let [x,y,z]=p;let a=x*Math.cos(angle)+z*Math.sin(angle),b=-x*Math.sin(angle)+z*Math.cos(angle);let v=(y-(view==='source'?38:(view==='city'?245:($('detail').checked?(level-1)*6:DESIGN.height/2))))*Math.cos(tilt)-b*Math.sin(tilt),depth=(y-(view==='source'?38:(view==='city'?245:($('detail').checked?(level-1)*6:DESIGN.height/2))))*Math.sin(tilt)+b*Math.cos(tilt);const s=Math.min(w/(view==='source'?70:(view==='city'?1550:DESIGN.diameter*1.65)),h/(view==='source'?91:(view==='city'?1050:($('detail').checked?70:DESIGN.height)+DESIGN.diameter*Math.abs(Math.sin(tilt))+90)))*zoom;return [w/2+a*s,h*.51-v*s,depth];}
function render(){scheduled=false;const w=canvas.clientWidth,h=canvas.clientHeight,dpr=Math.min(Math.max(devicePixelRatio||1,2),3);canvas.width=w*dpr;canvas.height=h*dpr;ctx.scale(dpr,dpr);ctx.fillStyle='#e8eeeb';ctx.fillRect(0,0,w,h);
 ctx.strokeStyle='#d1dcd6';ctx.lineWidth=.6;for(let a=-50;a<=50;a+=5){for(const ends of [[[a,-1,-50],[a,-1,50]],[[-50,-1,a],[50,-1,a]]]){let p=ends.map(x=>project(x,w,h));ctx.beginPath();ctx.moveTo(...p[0].slice(0,2));ctx.lineTo(...p[1].slice(0,2));ctx.stroke();}}
 let faces;if(view==='source'){faces=[];for(let i=0;i<SOURCE_VERTICES.length;i+=3){faces.push({points:SOURCE_VERTICES.slice(i,i+3),color:'#526e73',alpha:.85});}}else{if(modelDirty){build();if(view==='city')cityScene();modelDirty=false;}faces=triangles;}
 const ff=faces.map(f=>({...f,p:f.points.map(p=>project(p,w,h))}));ff.forEach(f=>f.depth=(view==='city'&&f.points.every(p=>p[1]<=0)?-1e9+Math.max(...f.points.map(p=>p[1])):f.p.reduce((s,p)=>s+p[2],0)/f.p.length));ff.sort((a,b)=>a.depth-b.depth);
 for(const f of ff){ctx.beginPath();ctx.moveTo(f.p[0][0],f.p[0][1]);for(let i=1;i<f.p.length;i++)ctx.lineTo(f.p[i][0],f.p[i][1]);ctx.closePath();ctx.globalAlpha=f.alpha;ctx.fillStyle=f.color;ctx.fill();if(f.line){ctx.globalAlpha=.95;ctx.lineWidth=.85;ctx.strokeStyle=f.line;ctx.stroke();}}ctx.globalAlpha=1;
}
function queue(){if(!scheduled){scheduled=true;requestAnimationFrame(render);}}
function update(){modelDirty=true;level=+$('level').value;const d=DESIGN.levels[level-1];$('levelValue').textContent=`${level} / 100`;$('datum').textContent=`+${d.z.toFixed(2)} m`;$('envelope').textContent=`${d.width.toFixed(3)} × ${d.depth.toFixed(3)} m`;const spatial=view==='model'||view==='source'||view==='city';canvas.style.display=spatial?'block':'none';$('drawing').style.display=spatial?'none':'block';$('stageLabel').hidden=!spatial;$('hint').hidden=!spatial;for(const id of ['glassField','cutField','interiorField'])$(id).hidden=view!=='model';$('levelField').hidden=view==='city'||view==='source'||view==='elevation'||view==='section';$('orbitButtons').hidden=!spatial;$('elevationField').hidden=view!=='elevation';$('saveDrawing').hidden=spatial;$('panelTitle').textContent=spatial?'MODEL CONTROLS':'DRAWING INFORMATION';$('stageLabel').textContent=view==='city'?'CITY MOCKUP / FICTIONAL URBAN CONTEXT':view==='source'?'ORIGINAL MESH / NEUTRAL GEOMETRY VIEW':'AXONOMETRIC / PROPOSED INTERPRETATION';$('viewDescription').textContent=view==='city'?'Your 100-story tower in an imagined city, with surrounding buildings, streets, planted plaza and approach paths. The tower geometry is unchanged. Drag to orbit or scroll to zoom.':view==='source'?'Actual uploaded geometry, uniformly scaled for comparison. Brush textures are omitted.':view==='model'?'Four pronounced hourglass bays follow your sketch. Maximum width is two imagined 100 m blocks. Four 4 m-wide exterior stairways, with steps, landings and a bridge to every floor, replace the vertical ribs.':'Artistic drawing with imagined dimensions. Download the vector SVG for crisp printing at any size.';
 if(!spatial){const path=view==='plan'?`drawings/plan-${String(level).padStart(2,'0')}.svg`:view==='section'?'drawings/section.svg':`drawings/${$('elevation').value}-elevation.svg`;$('drawing').src=path;$('drawing').alt=view==='plan'?`Level ${level} architectural plan`:view+' architectural drawing';$('saveDrawing').href=path;}else queue();}
document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{view=b.dataset.view;if(view==='city'){angle=.67;tilt=.48;zoom=1;}document.querySelectorAll('[data-view]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',x===b)});update();});
for(const id of ['level','glass','cut','elevation','sectionModel','detail','outerFrame'])$(id).addEventListener('input',update);
canvas.onpointerdown=e=>{drag=[e.clientX,e.clientY];canvas.setPointerCapture(e.pointerId)};canvas.onpointermove=e=>{if(!drag)return;angle+=(e.clientX-drag[0])*.008;tilt=Math.max(-.1,Math.min(1.1,tilt+(e.clientY-drag[1])*.005));drag=[e.clientX,e.clientY];queue()};canvas.onpointerup=canvas.onpointercancel=()=>drag=null;canvas.addEventListener('wheel',e=>{e.preventDefault();zoom=Math.max(.5,Math.min(2.5,zoom*Math.exp(-e.deltaY*.001)));queue()},{passive:false});$('rotateLeft').onclick=()=>{angle-=.3;queue()};$('rotateRight').onclick=()=>{angle+=.3;queue()};$('reset').onclick=()=>{angle=.67;tilt=view==='city'?.48:.28;zoom=1;queue()};window.addEventListener('resize',queue);update();
