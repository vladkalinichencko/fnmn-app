import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
golds=[p['gold'] for p in data]
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "
texts=[p['text'][:1500] for p in data]
for dname,docs in [("plain",TOPICS),("passage",["passage: "+t for t in TOPICS])]:
    TE=model.encode(docs,normalize_embeddings=True)
    PE=model.encode([QP+t for t in texts],normalize_embeddings=True,batch_size=32)
    S=PE@TE.T
    for T in [0.05,0.08]:
        E=np.exp(S/T); P=E/E.sum(1,keepdims=True); probs=P.max(1); preds=S.argmax(1)
        off=[i for i,g in enumerate(golds) if g=='other']; on=[i for i,g in enumerate(golds) if g!='other']
        res=[]
        for th in [0.3,0.4]:
            off_f=sum(1 for i in off if probs[i]>=th)/len(off)
            on_f=sum(1 for i in on if probs[i]>=th)/len(on)
            on_c=sum(1 for i in on if probs[i]>=th and canon[preds[i]]==golds[i])/len(on)
            res.append(f"th{th}: off {off_f:.0%} filed {on_f:.0%} corr {on_c:.0%}")
        acc=(preds==np.array([canon.index(g) if g in canon else 99 for g in golds])).mean()
        print(f"{dname} T={T}: argmax-acc {acc:.2f} | "+" | ".join(res))
    # attention text
    att="""Pretraining might not be teaching attention where to look. It may just be refining a decision made by luck in the first 10% of the run.\n\nTop: one model's attention at step 1k and step 10k, barely changed.\nBottom: two models, same training recipe, data, and data ordering, different initialization seed. By step 10k, they're looking at different things."""
    v=model.encode(QP+att,normalize_embeddings=True); s=TE@v; w=np.exp((s-s.max())/0.08); p=w/w.sum()
    print(f"  {dname} attention top3:",[(TOPICS[i],round(float(p[i]),3)) for i in np.argsort(-p)[:3]])
