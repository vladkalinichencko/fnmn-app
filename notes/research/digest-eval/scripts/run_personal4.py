import json, sys
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
import numpy as np
data=json.load(open('/tmp/digest-eval/evalset.json'))
model=SentenceTransformer("intfloat/multilingual-e5-base")
BASE=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects","other"]
PERSONAL={
 "personal blog":"personal blog",
 "personal stories":"personal stories",
 "life posts":"posts about personal life, everyday events and personal experiences",
 "blog diary":"blog and diary posts about the author's own life",
 "рус дневник":"личный дневник: записи о жизни, событиях и повседневности",
}
texts=["query: "+p['text'][:1500] for p in data]
PE=model.encode(texts,normalize_embeddings=True)
for name,pt in PERSONAL.items():
    topics=BASE[:8]+[pt,"other"]
    TE=model.encode(["passage: "+t for t in topics],normalize_embeddings=True)
    preds=(PE@TE.T).argmax(1)
    p_idx=topics.index(pt)
    gold_personal=[i for i,p in enumerate(data) if p['gold']=='personal']
    caught=sum(1 for i in gold_personal if preds[i]==p_idx)
    fp=[data[i]['id'] for i,p in enumerate(data) if preds[i]==p_idx and p['gold']!='personal']
    print(f"{name:14} personal-preds={int((preds==p_idx).sum())} caught={caught}/{len(gold_personal)} fp={fp}")
