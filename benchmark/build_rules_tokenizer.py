"""Tokenizer BPE pour le VRAI tajweed (17 regles + marques + harakat) —
Phase 0.3 du PLAN_ENTRAINEMENT_HYBRIDE.md.

Corpus d'entrainement du tokenizer = versets annotes (symboles PUA des regles)
+ tous les textes du manifest mixed (ASC arabe general + mots TTS fautifs) pour
garantir character_coverage=1.0 sur TOUT ce que le modele devra emettre.

⚠️ sentencepiece casse sur les chemins avec espaces ("Coran Karim") ->
tout se passe dans un dossier temporaire sans espace, puis copie du resultat
vers tokenizers/tajweed_rules_bpe_v1/.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import json
import shutil
import tempfile
from pathlib import Path
from nemo.collections.common.tokenizers.sentencepiece_tokenizer import create_spt_model

BASE = Path(__file__).parent
ANNOTATED = BASE / "data" / "quran_tajweed_rules" / "corpus_rules.txt"
MIXED_TRAIN = BASE / "nemo_manifests_mixed" / "train_mixed.jsonl"
OUT = BASE / "tokenizers" / "tajweed_rules_bpe_v1"

VOCAB_SIZE = 1024


def main():
    tmp = Path(tempfile.mkdtemp(prefix="spm_rules_"))  # /tmp/... sans espace
    corpus = tmp / "corpus.txt"
    n_ann, n_mixed = 0, 0
    seen = set()
    with open(corpus, "w", encoding="utf-8") as out:
        for line in open(ANNOTATED, encoding="utf-8"):
            out.write(line)
            n_ann += 1
        for line in open(MIXED_TRAIN, encoding="utf-8"):
            t = json.loads(line)["text"].strip()
            if t and t not in seen:
                seen.add(t)
                out.write(t + "\n")
                n_mixed += 1
    print(f"corpus tokenizer : {n_ann} versets annotes + {n_mixed} textes mixed uniques")

    out_tmp = tmp / "out"
    out_tmp.mkdir()
    create_spt_model(
        data_file=str(corpus),
        vocab_size=VOCAB_SIZE,
        sample_size=-1,
        do_lower_case=False,
        output_dir=str(out_tmp),
        tokenizer_type="bpe",
        character_coverage=1.0,   # chaque caractere (symboles PUA inclus) a un token
        bos=False, eos=False, pad=False,
    )

    if OUT.exists():
        raise SystemExit(f"{OUT} existe deja — ne pas ecraser (nouveau dossier = nouveau nom)")
    shutil.copytree(out_tmp, OUT)
    print(f"Tokenizer copie -> {OUT}")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name} ({f.stat().st_size} o)")
    shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
