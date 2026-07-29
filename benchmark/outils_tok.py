import json,os,unicodedata as u
import numpy as np
C=os.path.expanduser("~/.cache/coran-karim")
V=json.load(open(f"{C}/dev_vocab.json",encoding="utf-8"))
vocab=[k for k,_ in sorted(V.items(),key=lambda kv:kv[1])] if isinstance(V,dict) else V
BLANK=len(vocab)
def mk(pieces):
    p2i={}
    for i,p in enumerate(pieces): p2i.setdefault(p,i)
    mx=max(len(p) for p in pieces)
    def g(w):
        t="▁"+w; ids=[];pos=0
        while pos<len(t):
            for l in range(min(mx,len(t)-pos),0,-1):
                if t[pos:pos+l] in p2i: ids.append(p2i[t[pos:pos+l]]);pos+=l;break
            else: pos+=1
        return ids
    return g
tok_actuel=mk(vocab)
_nfcv=mk([u.normalize('NFC',p) for p in vocab])
tok_nfc=lambda w: _nfcv(u.normalize('NFC',w))
def logsoftmax(x):
    m=x.max(-1,keepdims=True); e=x-m; return e-np.log(np.exp(e).sum(-1,keepdims=True))
def viterbi(lp,toks):
    T=lp.shape[0]; ext=[BLANK]
    for t in toks: ext+=[t,BLANK]
    S=len(ext); NEG=-1e30
    d=np.full((T,S),NEG); bp=np.zeros((T,S),dtype=np.int8)
    d[0,0]=lp[0,ext[0]]
    if S>1: d[0,1]=lp[0,ext[1]]
    ok2=np.zeros(S,bool)
    for s in range(2,S): ok2[s]=(ext[s]!=BLANK) and (ext[s]!=ext[s-2])
    for t in range(1,T):
        prev=d[t-1]
        cand=np.stack([prev,np.concatenate(([NEG],prev[:-1])),np.concatenate(([NEG,NEG],prev[:-2]))])
        cand[2][~ok2]=NEG
        k=cand.argmax(0); d[t]=cand[k,np.arange(S)]+lp[t,ext]; bp[t]=k
    fin=S-1 if d[T-1,S-1]>=d[T-1,S-2] else S-2
    s=int(fin); fr=[0]*len(toks); sc=[0.0]*len(toks)
    for t in range(T-1,-1,-1):
        if s%2==1:
            i=(s-1)//2; fr[i]+=1; sc[i]+=lp[t,ext[s]]
        s=int(s)-int(bp[t,s])
    return d[T-1,fin],fr,sc
