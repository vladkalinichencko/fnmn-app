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
texts=["query: "+p['text'][:1500] for p in data]
PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
S=PE@TE.T
E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
probs=P.max(1); preds=S.argmax(1)
golds=[p['gold'] for p in data]

print("threshold | off-topic filed (BAD) | on-topic filed | on-topic correct")
for th in [0.2,0.25,0.3,0.35,0.4,0.45,0.5,0.55,0.6]:
    filed=probs>=th
    off=[i for i,g in enumerate(golds) if g=='other']
    on=[i for i,g in enumerate(golds) if g!='other']
    off_filed=sum(1 for i in off if filed[i])/len(off)
    on_filed=sum(1 for i in on if filed[i])/len(on)
    on_corr=sum(1 for i in on if filed[i] and canon[preds[i]]==golds[i])/len(on)
    print(f"  {th:.2f}   | {off_filed:6.0%} ({int(off_filed*len(off))}/{len(off)}) | {on_filed:6.0%} ({int(on_filed*len(on))}/{len(on)}) | {on_corr:6.0%}")

# where do off-topic posts land at th=0.4?
th=0.4
lands=Counter(canon[preds[i]] for i,g in enumerate(golds) if g=='other' and probs[i]>=th)
print("\noff-topic -> folder at th=0.4:",dict(lands))
low=sorted([(round(float(probs[i]),3),golds[i],canon[preds[i]],data[i]['id']) for i,g in enumerate(golds) if g=='other'],reverse=True)
print("\ntop-10 highest-prob off-topic posts:")
for s,g,p,i in low[:10]: print(f"  {s} gold=other -> {p}  {i}")
json.dump([{'id':p['id'],'gold':p['gold'],'pred':canon[preds[k]],'prob':round(float(probs[k]),3)} for k,p in enumerate(data)],open('/tmp/digest-eval/offtopic_preds.json','w'),ensure_ascii=False)
