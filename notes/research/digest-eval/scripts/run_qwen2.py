import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
golds=[p['gold'] for p in data]
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
PE=model.encode([QP+p['text'][:1500] for p in data],normalize_embeddings=True,batch_size=32)
S=PE@TE.T
print("sim range:",S.min().round(3),S.max().round(3),"mean gap top1-top2:",np.sort(S,axis=1)[:,-1].mean().round(3)-np.sort(S,axis=1)[:,-2].mean().round(3))
preds=S.argmax(1)
def auc(score,ok):
    order=np.argsort(score); r=np.empty(len(score)); r[order]=np.arange(len(score))
    n1=ok.sum(); n0=len(ok)-n1
    return (r[ok==1].sum()-n1*(n1-1)/2)/(n1*n0)
ok_arr=np.array([canon[preds[i]]==golds[i] if golds[i]!='other' else probs_dummy for i in range(len(golds))]) if False else None
for T in [0.02,0.05,0.08,0.1,0.15]:
    E=np.exp(S/T); P=E/E.sum(1,keepdims=True); probs=P.max(1)
    off=[i for i,g in enumerate(golds) if g=='other']; on=[i for i,g in enumerate(golds) if g!='other']
    line=f"T={T}: prob pct {np.percentile(probs,[25,50,75]).round(2)} | "
    for th in [0.3,0.4,0.5]:
        off_f=sum(1 for i in off if probs[i]>=th)/len(off)
        on_c=sum(1 for i in on if probs[i]>=th and canon[preds[i]]==golds[i])/len(on)
        line+=f"th{th}: off {off_f:.0%} corr {on_c:.0%} | "
    print(line)
