import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer

model=SentenceTransformer("intfloat/multilingual-e5-large")
T=0.02
def score(text,topics):
    TE=model.encode(["passage: "+t for t in topics],normalize_embeddings=True)
    v=model.encode("query: "+text,normalize_embeddings=True)
    s=TE@v; w=np.exp((s-s.max())/T); p=w/w.sum()
    return {t:round(float(pi),3) for t,pi in zip(topics,p)}

# --- 1) the attention text on research-ish topics
att="""Pretraining might not be teaching attention where to look. It may just be refining a decision made by luck in the first 10% of the run.

Top: one model's attention at step 1k and step 10k, barely changed.
Bottom: two models, same training recipe, data, and data ordering, different initialization seed. By step 10k, they're looking at different things."""
topics=["machine learning research","ai news","research","deep learning","startups","personal blog","other"]
print("=== attention text ===")
for t,s in score(att,topics).items(): print(f"  {t:25} {s}")

# --- 2) comments enrichment on short low-scoring posts
posts={}
for l in open('/Users/vladislavkalinichenko/Library/Application Support/FNMN/digest-out/posts.jsonl'):
    p=json.loads(l); posts[p['id']]=p
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)

def probs_for(texts):
    PE=model.encode(["query: "+t for t in texts],normalize_embeddings=True,batch_size=32)
    S=PE@TE.T; E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
    return P.max(1), S.argmax(1)

# posts with comments
cands=[]
for p in data:
    post=posts.get(p['id']) or {}
    comments=post.get('comments') or []
    ctxt=' '.join((c.get('text') or '') for c in comments if c.get('text'))
    if comments and p['gold']!='other':
        cands.append((p,post,ctxt))
print(f"\n=== {len(cands)} on-topic eval posts have comments ===")
rows=[]
for p,post,ctxt in cands:
    raw=p['text'][:1200]
    comb=raw+("\n\n"+ctxt[:600] if ctxt else "")
    rows.append((p['id'],p['gold'],raw,comb))
pr_raw,pr_=probs_for([r[2] for r in rows]); pr_cb,_=probs_for([r[3] for r in rows])
for (pid,gold,raw,comb),a,b in zip(rows,pr_raw,pr_cb):
    d=b-a
    flag=' <<<' if abs(d)>0.05 else ''
    print(f"{pid[:36]:36} gold={gold:14} raw={a:.3f} +comments={b:.3f} (d={d:+.3f}){flag}")
    print(f"     text: {raw[:90]}")
    if abs(d)>0.05: print(f"     comments: {comb[len(raw):][:120]}")
