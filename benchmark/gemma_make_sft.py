"""Build Gemma SFT examples from train.jsonl: ASR + direct-judgment (correct & corrupted)."""
import json, os, random
random.seed(0)
ROOT=os.path.dirname(os.path.abspath(__file__))

TRANSCRIBE=("Transcris fidèlement cet audio de récitation coranique en arabe. "
            "Donne UNIQUEMENT le texte arabe transcrit, sans explication.")

def judge_instr(ref):
    return (f"Un élève récite le Coran. Le texte EXACT attendu est :\n«{ref}»\n\n"
            "Écoute l'audio et compare-le mot à mot au texte attendu. Réponds STRICTEMENT sur une seule ligne :\n"
            "- «VERDICT: CORRECT» si la récitation correspond exactement,\n"
            "- «VERDICT: ERREUR - <détail>» s'il y a la moindre différence.")

def corrupt(text):
    w=text.split()
    if len(w)<2: return None
    mode=random.choice(["delete","substitute","swap"]); i=random.randrange(len(w))
    if mode=="delete": rm=w.pop(i); d=f"mot manquant: {rm}"
    elif mode=="substitute":
        o=w[i]; w[i]="ٱللَّهِ" if o!="ٱللَّهِ" else "رَبِّ"; d=f"mot changé: {o}->{w[i]}"
    else:
        j=(i+1)%len(w); w[i],w[j]=w[j],w[i]; d="mots inversés"
    return " ".join(w), d

rows=[json.loads(l) for l in open(os.path.join(ROOT,"data","train.jsonl"),encoding="utf-8")]
out=[]
for r in rows:
    a=r["wav"]
    # ASR task
    out.append({"audio":a,"user":TRANSCRIBE,"target":r["text"]})
    # Judgment task: 50% correct, 50% corrupted
    if random.random()<0.5:
        out.append({"audio":a,"user":judge_instr(r["text"]),"target":"VERDICT: CORRECT"})
    else:
        c=corrupt(r["text"])
        if c: out.append({"audio":a,"user":judge_instr(c[0]),"target":f"VERDICT: ERREUR - {c[1]}"})
        else: out.append({"audio":a,"user":judge_instr(r["text"]),"target":"VERDICT: CORRECT"})
random.shuffle(out)
with open(os.path.join(ROOT,"data","gemma_sft.jsonl"),"w",encoding="utf-8") as f:
    for e in out: f.write(json.dumps(e,ensure_ascii=False)+"\n")
print(f"SFT examples: {len(out)} (ASR + judgment)")
