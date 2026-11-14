import json, sys, time, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer

OUT='/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/notes/research/digest-eval'
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "

def encode_posts(texts):
    t=time.time()
    V=model.encode([QP+t[:1500] for t in texts],normalize_embeddings=True,batch_size=32)
    return V,time.time()-t

results={}

# ============ PART 1: evalset, all scorers, dense sweep ============
data=json.load(open(f'{OUT}/data/offtopic_eval.json'))
golds=np.array([p['gold'] for p in data]); texts=[p['text'][:1500] for p in data]
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
labels=np.array([canon.index(g) if g in canon else -1 for g in golds])
off=labels==-1; on=labels>=0
t0=time.time(); TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True); t_te=time.time()-t0
PE,dt=encode_posts(texts)
S=PE@TE.T
srt=np.sort(S,1)[:,::-1]; gaps=-np.diff(srt,axis=1)
scores={
 'm12':gaps[:,0],
 'maxgap':gaps.max(1),
 'm13':srt[:,0]-srt[:,2],
 'm1mean':srt[:,0]-srt[:,1:].mean(1),
 'top1sim':srt[:,0],
 'energy':np.log(np.exp(S/0.05).sum(1))*0.05,
}
# Mahalanobis + KNN with 2-fold split on on-topic (fit half, test other half + all off)
rng=np.random.RandomState(0); on_idx=np.where(on)[0].copy(); rng.shuffle(on_idx)
half=len(on_idx)//2; fit_idx,on_idx2=on_idx[:half],on_idx[half:]
# repeat swapped for fuller estimate: do both directions
folds=[(fit_idx,on_idx2),(on_idx2,fit_idx)]
valid_c=[c for c in range(9) if (labels==c).sum()>=3]
maha_test=np.full(len(PE),np.nan); knn_test=np.full(len(PE),np.nan)
for fit_i,test_i in folds:
    tr=np.concatenate([fit_i, np.where(off)[0]])  # off posts never in fit means? means only from on
    means=[]; 
    for c in valid_c:
        mem=fit_i[labels[fit_i]==c]
        means.append(PE[mem].mean(0) if len(mem) else np.zeros(PE.shape[1]))
    means=np.array(means); means/= (np.linalg.norm(means,axis=1,keepdims=True)+1e-9)
    cov=np.zeros((PE.shape[1],PE.shape[1])); n=0
    for c,m in zip(valid_c,means):
        mem=fit_i[labels[fit_i]==c]
        if len(mem)>1:
            Z=PE[mem]-m; cov+=Z.T@Z; n+=len(mem)
    cov/=max(n-len(valid_c),1); cov+=np.eye(PE.shape[1])*0.05
    prec=np.linalg.pinv(cov)
    # test = held-out on posts + ALL off posts
    te=np.concatenate([test_i,np.where(off)[0]])
    D=np.stack([np.sqrt(((PE[te]-m)@prec*(PE[te]-m)).sum(1)) for m in means],1)
    maha_test[te]=D.min(1)
    # knn3 distance to fit on-posts
    Z=PE[fit_i]
    Dd=np.sqrt(((PE[te][:,None,:]-Z[None,:,:])**2).sum(-1))
    knn_test[te]=np.sort(Dd,1)[:,2]
scores['maha_dist']=-maha_test  # higher=more ID
scores['knn3_dist']=-knn_test

def sweep(name,sc,ths,mask_off,mask_on):
    rows=[]
    for t in ths:
        acc=sc>=t
        rows.append({'th':round(float(t),4),'off_leak':round(float(np.mean(acc[mask_off])),4),
                     'on_filed':round(float(np.mean(acc[mask_on])),4)})
    return rows
results['evalset']={'n':len(data),'off':int(off.sum()),'on':int(on.sum()),
 'embed_s':round(dt,2),'topic_embed_s':round(t_te,2),
 'scores':{k:sweep(k,v,np.arange(-3.0,3.01,0.05) if k.endswith('dist') else np.arange(0.0,0.201,0.005),off,on) for k,v in scores.items()}}
# fix: maha/knn are distances -> accept = dist<=thr i.e. score>=-thr; sweep on raw dist instead
for k in ('maha_dist','knn3_dist'):
    raw=-scores[k]
    rows=[]
    for t in np.arange(0.5,8.01,0.25):
        acc=raw<=t
        rows.append({'th':round(float(t),3),'off_leak':round(float(np.mean(acc[off])),4),'on_filed':round(float(np.mean(acc[on])),4)})
    results['evalset']['scores'][k]=rows

# speed: scorer overhead (post-embedding)
t=time.time()
for _ in range(100):
    _=gaps.max(1); _=np.log(np.exp(S/0.05).sum(1))
results['scorer_overhead_ms_per_100posts']=round((time.time()-t)*10,3)

# ============ PART 2: live X ============
raw=[json.loads(l) for l in open('/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server/digest/out/posts.jsonl')]
xs=[p for p in raw if p.get('network')=='x' and (p.get('text') or '').strip()]
xs.sort(key=lambda p:p.get('posted_at',''),reverse=True); xs=xs[:400]
XT=["film updates","software development","web design","research","artificial intelligence","deep learning"]
PE_x,dt_x=encode_posts([p['text'] for p in xs])
TE_x=model.encode(["passage: "+t for t in XT],normalize_embeddings=True)
Sx=PE_x@TE_x.T
sx=np.sort(Sx,1)[:,::-1]; gx=-np.diff(sx,axis=1)
xscores={'m12':gx[:,0],'maxgap':gx.max(1),'m13':sx[:,0]-sx[:,2],'m1mean':sx[:,0]-sx[:,1:].mean(1),'top1sim':sx[:,0],'energy':np.log(np.exp(Sx/0.05).sum(1))*0.05}
results['x_live']={'n':len(xs),'words_med':float(np.median([len(p['text'].split()) for p in xs])),
 'embed_s':round(dt_x,2),
 'filed':{k:[{'th':round(float(t),3),'filed':round(float(np.mean(v>=t)),4)} for t in np.arange(0.0,0.151,0.005)] for k,v in xscores.items()}}
# dump top-40 by maxgap and by m12 for eyeballing
for name,sc in [('maxgap',xscores['maxgap']),('m12',xscores['m12'])]:
    order=np.argsort(-sc)[:40]
    with open(f'/tmp/bakeoff/x_top_{name}.txt','w') as f:
        for i in order:
            f.write(f"[{name}={sc[i]:.3f}] {(xs[i]['text'] or '')[:300].replace(chr(10),' ')}\n---\n")
json.dump(results,open(f'{OUT}/data/score_bakeoff.json','w'),indent=1)
print("embed evalset",round(dt,2),"s | x",round(dt_x,2),"s")
print("done")
