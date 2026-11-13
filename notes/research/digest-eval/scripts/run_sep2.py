import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
data=json.load(open('/tmp/digest-eval/evalset.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects","other"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
texts=["query: "+p['text'][:1500] for p in data]
golds=np.array([canon.index(p['gold']) for p in data])
model=SentenceTransformer("intfloat/multilingual-e5-large")
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
S=PE@TE.T
for T in [0.01,0.02,0.03]:
    E=np.exp(S/T); P=(E/E.sum(1,keepdims=True)).max(1)
    preds=S.argmax(1); ok=(preds==golds)
    print(f"T={T}: prob pct",np.percentile(P,[10,25,50,75,90]).round(3))
    for t in [0.2,0.3,0.4,0.5,0.6]:
        keep=P>=t
        if keep.sum(): print(f"   th={t}: keep {keep.mean():.0%} acc {ok[keep].mean():.2f}")
