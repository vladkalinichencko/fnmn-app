import json, sys, numpy as np, time
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
from collections import Counter

T=0.02
data=json.load(open('/tmp/digest-eval/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev"]
golds=[p['gold'] for p in data]

def evaluate(model, name, query_prefix="query: ", passage_prefix="passage: ", batch=32):
    TE=model.encode([passage_prefix+t for t in TOPICS],normalize_embeddings=True)
    texts=[query_prefix+p['text'][:1500] for p in data]
    t0=time.time()
    PE=model.encode(texts,normalize_embeddings=True,batch_size=batch)
    dt=time.time()-t0
    S=PE@TE.T; E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
    probs=P.max(1); preds=S.argmax(1)
    print(f"--- {name} ({dt:.0f}s encode)")
    for th in [0.3,0.4,0.5]:
        off=[i for i,g in enumerate(golds) if g=='other']; on=[i for i,g in enumerate(golds) if g!='other']
        off_f=sum(1 for i in off if probs[i]>=th)/len(off)
        on_f=sum(1 for i in on if probs[i]>=th)/len(on)
        on_c=sum(1 for i in on if probs[i]>=th and canon[preds[i]]==golds[i])/len(on)
        acc_all=(preds==np.array([canon.index(g) if g in canon else -1 for g in golds])).mean()
        print(f"  th={th}: off {off_f:.0%} ({int(off_f*len(off))}/69) | on filed {on_f:.0%} | correct {on_c:.0%} | argmax-acc {acc_all:.2f}")
    # attention text
    att="""Pretraining might not be teaching attention where to look. It may just be refining a decision made by luck in the first 10% of the run.

Top: one model's attention at step 1k and step 10k, barely changed.
Bottom: two models, same training recipe, data, and data ordering, different initialization seed. By step 10k, they're looking at different things."""
    v=model.encode(query_prefix+att,normalize_embeddings=True)
    s=TE@v; w=np.exp((s-s.max())/T); p=w/w.sum()
    order=np.argsort(-p)
    print("  attention text top3:",[(TOPICS[i],round(float(p[i]),3)) for i in order[:3]])

model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
evaluate(model,"Qwen3-Emb-0.6B","Instruct: Classify the topic of this social media post.\nQuery: ","passage: ")
