import json, sys
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
import numpy as np
data=json.load(open('/tmp/digest-eval/evalset.json'))
model=SentenceTransformer("intfloat/multilingual-e5-base")
BASE=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects","other"]
for pt in ["personal blog","personal stories"]:
    topics=BASE[:8]+[pt,"other"]
    TE=model.encode(["passage: "+t for t in topics],normalize_embeddings=True)
    rows=[]
    for p in data:
        v=model.encode("query: "+p['text'][:1500],normalize_embeddings=True)
        sims=TE@v; j=int(sims.argmax())
        if topics[j]==pt:
            rows.append((round(float(sims[j]),3),p['gold'],p['id']))
    rows.sort(reverse=True)
    print(f"--- {pt}: {len(rows)} predicted")
    for s,g,i in rows: print(f"  {s} gold={g:10} {i}")
