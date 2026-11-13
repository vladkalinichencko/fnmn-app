import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
from collections import Counter

model=SentenceTransformer("intfloat/multilingual-e5-large")
T=0.02

def score(text, topics):
    TE=model.encode(["passage: "+t for t in topics],normalize_embeddings=True)
    v=model.encode("query: "+text,normalize_embeddings=True)
    s=TE@v; w=np.exp((s-s.max())/T); p=w/w.sum()
    return {t:float(pi) for t,pi in zip(topics,p)}

# --- 1) argmax-only: what happens with no threshold (evalset)
data=json.load(open('/tmp/digest-eval/evalset.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects","other"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
texts=["query: "+p['text'][:1500] for p in data]
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
S=PE@TE.T
E=np.exp(S/T); P=E/E.sum(1,keepdims=True)
preds=S.argmax(1); golds=np.array([canon.index(p['gold']) for p in data])
print(f"ARGMAX-ONLY: all {len(data)} posts get a folder, acc={float((preds==golds).mean()):.2f}")
print("  gold dist of ALL posts:",dict(Counter(p['gold'] for p in data)))
for th in [0.3,0.4,0.5]:
    keep=P.max(1)>=th
    ok=(preds==golds)&keep
    print(f"  th={th}: kept {int(keep.sum())}/{len(data)} ({keep.mean():.0%}), of kept correct {int(ok.sum())} ({ok.sum()/max(keep.sum(),1):.0%})")
    # what gold classes survive / die
    surv=Counter(data[i]['gold'] for i in range(len(data)) if keep[i])
    dead=Counter(data[i]['gold'] for i in range(len(data)) if not keep[i])
    print(f"    survives: {dict(surv)}")
    print(f"    dropped : {dict(dead)}")

# --- 2) personal formulations on diary-ish texts
diary={
 "Errand RU":"Вчера сходила в магазин, купила хлеб и молоко, потом была на тренировке. Устала, но день был хороший, вечером позвонила маме.",
 "Friends RU":"Девочки, привет! На выходных едем на дачу, кто с нами? Берите купальники и что-нибудь почитать, будет жарко. Привозите фрукты!",
 "Errand EN":"Went grocery shopping yesterday, got bread and milk, then hit the gym. Tired but it was a good day, called mom in the evening.",
}
others=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects","research","other"]
PERSONAL=["personal blog","personal stories","everyday life","личный блог","дневник","personal diary and everyday moments","my life","blog posts"]
print("\n--- personal formulations (top-2 shown)")
for pt in PERSONAL:
    topics=[pt]+others
    res=[]
    for name,t in diary.items():
        s=score(t,topics); top=sorted(s.items(),key=lambda x:-x[1])[:2]
        res.append(f"{name}:{top[0][0]}={top[0][1]:.2f}")
    # fp check on evalset: how many non-personal get this topic on top
    TE2=model.encode(["passage: "+x for x in topics],normalize_embeddings=True)
    S2=PE@TE2.T; p2=S2.argmax(1); pi=topics.index(pt)
    preds_personal=int((p2==pi).sum()); caught=sum(1 for i,p in enumerate(data) if p['gold']=='personal' and p2[i]==pi)
    fp=preds_personal-caught
    print(f"{pt:35} evalset preds={preds_personal} caught={caught}/2 fp={fp} | "+" ".join(res))

# --- 3) SpaceX formulations
spacex="SpaceX успешно запустила ракету Falcon 9 с новой партией спутников Starlink. Посадка первой ступени прошла штатно — уже сороковой раз подряд. Инженеры компании работают над увеличением частоты запусков."
print("\n--- spacex topic variants")
for tp in ["startups","startups and business","space and rockets","aerospace and spaceflight","technology companies","business news","space exploration"]:
    topics=[tp,"ai news","design thoughts","personal blog","research"]
    s=score(spacex,topics); top=sorted(s.items(),key=lambda x:-x[1])[:3]
    print(f"{tp:25} -> "+" ".join(f"{k}={v:.2f}" for k,v in top))
