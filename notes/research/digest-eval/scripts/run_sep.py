import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer

data=json.load(open('/tmp/digest-eval/evalset.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects","other"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
texts=["query: "+p['text'][:1500] for p in data]
golds=[canon.index(p['gold']) for p in data]

def evaluate(model_name):
    model=SentenceTransformer(model_name)
    TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
    PE=model.encode(texts,normalize_embeddings=True,batch_size=32)
    S=PE@TE.T
    preds=S.argmax(1)
    ok=(preds==np.array(golds)).astype(float)
    acc=ok.mean()
    # features
    part=np.partition(S,-2,axis=1)
    top1=S.max(1); top2=part[:,-2]
    margin=top1-top2
    # softmax prob at T=0.02
    E=np.exp(S/0.02); softmax=(E/E.sum(1,keepdims=True)).max(1)
    # AUC for each feature vs correctness
    def auc(score):
        order=np.argsort(score); ranks=np.empty(len(score)); ranks[order]=np.arange(len(score))
        n1=ok.sum(); n0=len(ok)-n1
        return (ranks[ok==1].sum()-n1*(n1-1)/2)/(n1*n0)
    print(f"{model_name}: acc={acc:.2f} auc_top1={auc(top1):.3f} auc_margin={auc(margin):.3f} auc_softmax={auc(softmax):.3f}")
    # best-F1 threshold on margin: keep if margin>=t -> among kept acc & coverage
    for t in np.percentile(margin,[25,50,75]):
        keep=margin>=t; print(f"   margin>={t:.3f}: keep {keep.mean():.0%} acc {ok[keep].mean():.2f}")
    return S

evaluate("intfloat/multilingual-e5-base")
evaluate("intfloat/multilingual-e5-large")
