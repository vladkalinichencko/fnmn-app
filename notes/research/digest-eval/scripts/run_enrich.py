import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
from collections import Counter

model=SentenceTransformer("intfloat/multilingual-e5-large")
T=0.02
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
# need author info: reload posts
posts={}
for l in open('/Users/vladislavkalinichenko/Library/Application Support/FNMN/digest-out/posts.jsonl'):
    p=json.loads(l); posts[p['id']]=p

def variants(p):
    post=posts[p['id']]
    a=post.get('author') or {}
    name=a.get('name') or ''; handle=a.get('handle') or ''
    text=p['text'][:1500]
    src=p['id'].split('/')[1] if '/' in p['id'] else ''
    return {
      "raw": text,
      "author": f"{name} (@{handle}): {text}" if name or handle else text,
      "handle": f"@{handle}: {text}" if handle else text,
      "source": f"{src}: {text}",
      "name_only": f"{name}: {text}" if name else text,
    }

for vname in ["raw","author","handle","source","name_only"]:
    texts=["query: "+variants(p)[vname] for p in data]
    PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
    S=PE@TE.T; E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
    probs=P.max(1); preds=S.argmax(1)
    golds=[p['gold'] for p in data]
    th=0.4
    off=[i for i,g in enumerate(golds) if g=='other']; on=[i for i,g in enumerate(golds) if g!='other']
    off_f=sum(1 for i in off if probs[i]>=th)/len(off)
    on_f=sum(1 for i in on if probs[i]>=th)/len(on)
    on_c=sum(1 for i in on if probs[i]>=th and canon[preds[i]]==golds[i])/len(on)
    print(f"{vname:10} th=0.4: off-topic filed {off_f:.0%} ({int(off_f*len(off))}/69) | on-topic filed {on_f:.0%} | correct {on_c:.0%}")
