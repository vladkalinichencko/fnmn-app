import json, sys, time, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer

OUT='/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/notes/research/digest-eval'
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "

def encode(texts):
    return model.encode([QP+t[:1500] for t in texts],normalize_embeddings=True,batch_size=32)

# ---------- evalset (has gold labels) ----------
data=json.load(open(f'{OUT}/data/offtopic_eval.json'))
golds=np.array([p['gold'] for p in data]); texts=[p['text'][:1500] for p in data]
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
labels=np.array([canon.index(g) if g in canon else -1 for g in golds])
off=labels==-1; on=labels>=0
words=np.array([len(t.split()) for t in texts])
PE=encode(texts); TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
S=PE@TE.T; srt=np.sort(S,1)[:,::-1]
sc={'m12':srt[:,0]-srt[:,1],'m1mean':srt[:,0]-srt[:,1:].mean(1),'maxgap':(-np.diff(srt,1)).max(1)}

# ---------- live X (no labels; distribution only) ----------
raw=[json.loads(l) for l in open('/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server/digest/out/posts.jsonl')]
xs=[p for p in raw if p.get('network')=='x' and (p.get('text') or '').strip()]
xs.sort(key=lambda p:p.get('posted_at',''),reverse=True); xs=xs[:400]
XT=["film updates","software development","web design","research","artificial intelligence","deep learning"]
PX=encode([p['text'] for p in xs]); TX=model.encode(["passage: "+t for t in XT],normalize_embeddings=True)
SX=PX@TX.T; sx=np.sort(SX,1)[:,::-1]
xsc={'m1mean':sx[:,0]-sx[:,1:].mean(1),'m12':sx[:,0]-sx[:,1],'maxgap':(-np.diff(sx,1)).max(1)}
xwords=np.array([len(p['text'].split()) for p in xs])

# ---------- evalset: length buckets ----------
bins=[0,10,20,40,1e9]; names=['<10w','10-20w','20-40w','40w+']
bi=np.digitize(words,bins)-1
print("=== evalset: per-bucket medians (off / on) ===")
for name in ['m12','m1mean','maxgap']:
    print(f"-- {name}")
    for b in range(4):
        mo=off&(bi==b); mn=on&(bi==b)
        if mo.sum()==0 and mn.sum()==0: continue
        print(f"  {names[b]:7s} n_off={mo.sum():3d} n_on={mn.sum():3d} "
              f"off_med={np.median(sc[name][mo]) if mo.sum() else float('nan'):.3f} "
              f"on_med={np.median(sc[name][mn]) if mn.sum() else float('nan'):.3f}")

# fixed-threshold leak/filed overall and per bucket for m1mean
print("\n=== m1mean: fixed thresholds, overall vs per-bucket ===")
for th in [0.08,0.10,0.12,0.14,0.16]:
    acc=sc['m1mean']>=th
    line=f"th={th:.2f} ALL leak={np.mean(acc[off]):.3f} filed={np.mean(acc[on]):.3f} |"
    for b in range(4):
        mo=off&(bi==b); mn=on&(bi==b)
        line+=f" {names[b]}:{np.mean(acc[mo]) if mo.sum() else 0:.2f}/{np.mean(acc[mn]) if mn.sum() else 0:.2f}"
    print(line)

# length-scaled threshold: th = a + b/words  (shorter -> higher bar)
print("\n=== m1mean: scaled threshold th=a+b/sqrt(words), grid ===")
best=None
for a in [0.04,0.06,0.08,0.10]:
    for b in [0.0,0.1,0.2,0.3,0.4,0.5]:
        th=a+b/np.sqrt(np.maximum(words,1))
        acc=sc['scaled']=sc['m1mean']>=th
        leak=np.mean(acc[off]); filed=np.mean(acc[on])
        # compare at ~same leak as flat 0.14
        if leak<=0.06:
            print(f" a={a} b={b}: leak={leak:.3f} filed={filed:.3f}")
            if best is None or filed>best[2]: best=(a,b,filed)
print("best scaled:",best)

# same for m12 scaled
print("\n=== m12 scaled grid (leak<=6%) ===")
for a in [0.02,0.04,0.06,0.08]:
    for b in [0.0,0.1,0.2,0.3,0.4]:
        th=a+b/np.sqrt(np.maximum(words,1))
        acc=sc['m12']>=th
        leak=np.mean(acc[off]); filed=np.mean(acc[on])
        if leak<=0.06:
            print(f" a={a} b={b}: leak={leak:.3f} filed={filed:.3f}")

# ---------- X live: pass-rate by length bucket at candidate thresholds ----------
print("\n=== X live: filed-rate by length bucket ===")
xb=np.digitize(xwords,[0,10,15,25,1e9])-1
xn=['<10w','10-15w','15-25w','25w+']
for name in ['m1mean','m12','maxgap']:
    for th in ([0.10,0.14,0.16] if name=='m1mean' else [0.05,0.08,0.10] if name=='m12' else [0.07,0.10,0.12]):
        acc=xsc[name]>=th
        cells=" ".join(f"{xn[b]}:{np.mean(acc[xb==b]):.2f}" for b in range(4) if (xb==b).sum())
        print(f"{name:8s} th={th:.2f} n={len(acc)} filed={np.mean(acc):.3f} | {cells}")

# eyeball: short X tweets that pass m1mean>=0.14
print("\n=== X: short (<15w) passing m1mean>=0.14 (first 15) ===")
idx=np.where((xsc['m1mean']>=0.14)&(xwords<15))[0]
for i in idx[:15]:
    print(f"[{xsc['m1mean'][i]:.3f} {xwords[i]}w] {xs[i]['text'][:160].replace(chr(10),' ')}")
print(f"total short passing: {len(idx)} / {(xwords<15).sum()} short")

json.dump({'eval_words':words.tolist(),'x_words':xwords.tolist()},open('/tmp/len_dump.json','w'))
