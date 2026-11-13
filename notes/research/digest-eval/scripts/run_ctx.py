import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer

model=SentenceTransformer("intfloat/multilingual-e5-large")
T=0.02
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
posts={}
for l in open('/Users/vladislavkalinichenko/Library/Application Support/FNMN/digest-out/posts.jsonl'):
    p=json.loads(l); posts[p['id']]=p

def ctx_text(pid):
    post=posts.get(pid) or {}
    ctx=(post.get('context') or {}).get('post') or {}
    return (ctx.get('text') or '')[:600]

for vname in ["raw","ctx_append","ctx_prepend","ctx_only"]:
    texts=[]
    for p in data:
        t=p['text'][:1200]; c=ctx_text(p['id'])
        if vname=="raw": q=t
        elif vname=="ctx_append": q=t+("\n\n"+c if c else "")
        elif vname=="ctx_prepend": q=(c+"\n\n"+t) if c else t
        else: q=c or t
        texts.append("query: "+q)
    PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
    S=PE@TE.T; E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
    probs=P.max(1); preds=S.argmax(1); golds=[p['gold'] for p in data]
    off=[i for i,g in enumerate(golds) if g=='other']; on=[i for i,g in enumerate(golds) if g!='other']
    off_f=sum(1 for i in off if probs[i]>=0.4)/len(off)
    on_f=sum(1 for i in on if probs[i]>=0.4)/len(on)
    on_c=sum(1 for i in on if probs[i]>=0.4 and canon[preds[i]]==golds[i])/len(on)
    nctx=sum(1 for p in data if ctx_text(p['id']))
    print(f"{vname:12} posts-with-ctx={nctx} | off {off_f:.0%} | on filed {on_f:.0%} | correct {on_c:.0%}")
