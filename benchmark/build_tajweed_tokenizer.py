"""
Entraine un nouveau tokenizer SentencePiece BPE sur le corpus tajweed-preserve
(nemo_manifests_tajweed/corpus_text.txt). Le tokenizer pcd d'origine a ete
construit sur du texte SANS marques de tajweed -> il ne peut pas les representer
(elles tombaient en <unk>). Ce nouveau tokenizer les couvre toutes.

character_coverage=1.0 est CRITIQUE : garantit que chaque caractere du corpus
(y compris les marques rares a 40-50 occurrences) a son propre token de repli,
donc aucun caractere inapprenable. NeMo cree tokenizer.model + vocab.txt +
tokenizer.vocab dans OUT_DIR, directement utilisables par change_vocabulary().
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
from pathlib import Path
from nemo.collections.common.tokenizers.sentencepiece_tokenizer import create_spt_model

BASE = Path(__file__).parent
CORPUS = BASE / "nemo_manifests_tajweed" / "corpus_text.txt"
OUT = BASE / "tokenizers" / "tajweed_bpe_v1"
OUT.mkdir(parents=True, exist_ok=True)

VOCAB_SIZE = 1024

def main():
    print(f"Entrainement tokenizer BPE {VOCAB_SIZE} sur {CORPUS.name}...", flush=True)
    create_spt_model(
        data_file=str(CORPUS),
        vocab_size=VOCAB_SIZE,
        sample_size=-1,             # tout le corpus
        do_lower_case=False,
        output_dir=str(OUT),
        tokenizer_type="bpe",
        character_coverage=1.0,     # couvre TOUS les caracteres (marques rares incluses)
        bos=False, eos=False, pad=False,
    )
    print(f"Tokenizer ecrit -> {OUT}", flush=True)
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name} ({f.stat().st_size} o)", flush=True)

if __name__ == "__main__":
    main()
