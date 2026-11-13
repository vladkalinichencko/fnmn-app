import json, sys
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
import numpy as np
data=json.load(open('/tmp/digest-eval/evalset.json'))
model=SentenceTransformer("intfloat/multilingual-e5-base")
BASE=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects","other"]
PERSONAL={
 "short":"personal stories",
 "descriptive":"a personal blog or diary post about the author's own life and everyday experiences",
 "diary":"personal diary entries about daily life, feelings and personal events",
 "ru":"личный блог: записи о повседневной жизни, feelings и личном",
}
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
texts=["query: "+p['text'][:1500] for p in data]
PE=model.encode(texts,normalize_embeddings=True)
for name,pt in PERSONAL.items():
    topics=BASE[:8]+[pt,"other"]
    TE=model.encode(["passage: "+t for t in topics],normalize_embeddings=True)
    sims=PE@TE.T
    preds=sims.argmax(1)
    p_idx=topics.index(pt)
    npred=int((preds==p_idx).sum())
    gold_personal=[i for i,p in enumerate(data) if p['gold']=='personal']
    caught=sum(1 for i in gold_personal if preds[i]==p_idx)
    # false positives: predicted personal but gold != personal
    fp=sum(1 for i,p in enumerate(data) if preds[i]==p_idx and p['gold']!='personal')
    acc=sum(1 for i,p in enumerate(data) if canon[topics.index(topics[preds[i]])]==p['gold'])
    print(f"{name:12} acc={acc}/94 personal-preds={npred} caught={caught}/{len(gold_personal)} fp={fp}")
