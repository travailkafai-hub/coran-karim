#!/usr/bin/env python3
"""Evalue SEPAREMENT un checkpoint sur le canonique et sur les erreurs deliberees.

POURQUOI CE SCRIPT (2026-07-16) :
    Le val d'entrainement (val_mixed) agrege canonique + erreurs : une baisse du
    WER global ne dit PAS ou est le gain. Le modele pourrait progresser sur le
    Coran et continuer d'ignorer totalement les erreurs -- c'est meme son biais
    naturel. Ici on mesure les deux moities separement, et surtout on repond a
    LA question : quand le clip contient une erreur deliberee, le modele
    transcrit-il ce qui est REELLEMENT dit, ou "corrige"-t-il vers le canonique ?

    Rappel du probleme observe sur device (2026-07-16, avant ce chantier) :
    l'utilisateur prononce "rabba" (fatha), le modele ecrit "rabbi" (kasra,
    forme canonique). Le GOP est alors structurellement aveugle : il mesure
    forced-free, or si le modele est convaincu du canonique, forced == free
    => gop=0 => vert. Aucun reglage de seuil ne rattrape ca.

METRIQUE CLE -- "taux de correction canonique" :
    Pour chaque clip d'erreur, on compare la transcription a DEUX references :
      - `text`         : ce qui est reellement prononce (fautif)
      - `correct_text` : la forme canonique
    Si la transcription colle au canonique plutot qu'au prononce, le modele a
    "corrige" => l'erreur est invisible pour l'app. C'est le taux qu'on veut
    voir S'EFFONDRER. Un WER brut ne le montrerait pas : transcrire le canonique
    au lieu du fautif ne coute que quelques caracteres de WER, alors que c'est
    un echec TOTAL du point de vue du produit.

Usage :
    python3 eval_error_detection.py <modele.nemo|checkpoint.ckpt> [--limit N]
"""
import argparse
import json
import unicodedata
from pathlib import Path

import torch
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL_ERRORS = BASE / "nemo_manifests_mixed" / "val_errors_annotated.jsonl"
VAL_CANON = BASE / "nemo_manifests_mixed" / "val_canonical.jsonl"
TOKENIZER_DIR = BASE / "tokenizers" / "tajweed_bpe_v1"
LOCAL_NEMO = BASE / ".hf" / "nemo_models" / "stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo"


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def norm(s):
    """Normalisation MINIMALE : NFC + espaces. On ne touche PAS aux harakat --
    c'est precisement ce qu'on mesure."""
    return " ".join(unicodedata.normalize("NFC", s).split())


def cer(ref, hyp):
    """Distance de Levenshtein normalisee (caracteres). Au niveau caractere et
    non mot : une erreur de harakat ne change qu'UN caractere, un WER la
    compterait comme un mot entier faux et noierait le signal."""
    r, h = norm(ref), norm(hyp)
    if not r:
        return 0.0 if not h else 1.0
    prev = list(range(len(h) + 1))
    for i, rc in enumerate(r, 1):
        cur = [i]
        for j, hc in enumerate(h, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (rc != hc)))
        prev = cur
    return prev[-1] / len(r)


def load_model(path, use_cpu=False):
    p = Path(path)
    if p.suffix == ".nemo":
        m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(p), map_location="cpu")
    else:
        m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(LOCAL_NEMO), map_location="cpu")
        m.change_vocabulary(new_tokenizer_dir=str(TOKENIZER_DIR), new_tokenizer_type="bpe")
        ckpt = torch.load(str(p), map_location="cpu", weights_only=False)
        sd = ckpt.get("state_dict", ckpt)
        missing, unexpected = m.load_state_dict(sd, strict=False)
        real = [k for k in missing if not k.startswith("loss.")]
        if real:
            raise SystemExit(f"ECHEC : {len(real)} poids manquants, ex. {real[:3]}")
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0

    # OBLIGATOIRE : ce modele est HYBRIDE (RNNT + CTC) et `transcribe()` utilise
    # le decodeur RNNT PAR DEFAUT. Or on entraine en CTC-only (ZeroRNNTLoss, cf.
    # finetune_fastconformer.py) : la tete RNNT n'a jamais appris et sort du
    # bruit pur -- observe 2026-07-16 : y_sequence = [956, 956, 956, ...] et un
    # texte de charabia, d'ou un CER de 8647% qui a revele le bug. Sans cette
    # ligne, l'eval mesure une tete non entrainee et ses chiffres ne veulent
    # RIEN dire (ils avaient l'air plausibles cote "erreurs" : 11% fideles).
    m.change_decoding_strategy(decoder_type="ctc")

    m.eval()
    # --cpu : mesurer un modele PENDANT qu'un entrainement occupe le GPU. Une
    # eval concurrente peut le faire tomber en OOM (2026-07-16 : plusieurs
    # heures de training en cours, ~8 Go deja pris au pic) -- une mesure ne
    # vaut jamais de risquer le run. Plus lent, sans danger.
    if torch.cuda.is_available() and not use_cpu:
        m = m.cuda()
    return m


def transcribe(model, paths, bs=4):
    with torch.no_grad():
        out = model.transcribe(paths, batch_size=bs, verbose=False)
    # NeMo hybride peut renvoyer (ctc, rnnt) ou une liste d'objets
    if isinstance(out, tuple):
        out = out[0]
    return [o.text if hasattr(o, "text") else str(o) for o in out]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=400)
    ap.add_argument("--cpu", action="store_true",
                    help="force CPU (eval sans risque pendant un entrainement GPU)")
    args = ap.parse_args()

    print(f"Chargement : {args.model}")
    model = load_model(args.model, use_cpu=args.cpu)

    # ── Erreurs deliberees ──────────────────────────────────────────────────
    rows = [json.loads(l) for l in open(VAL_ERRORS, encoding="utf-8")]
    rows = [r for r in rows if r.get("correct_text")][:args.limit]
    hyps = transcribe(model, [r["audio_filepath"] for r in rows])

    corrected = 0          # modele a "corrige" vers le canonique -> ERREUR INVISIBLE
    faithful = 0           # modele a transcrit ce qui est dit -> erreur detectable
    by_kind = {}
    for r, h in zip(rows, hyps):
        d_said = cer(r["text"], h)             # distance a ce qui est PRONONCE
        d_canon = cer(r["correct_text"], h)    # distance au CANONIQUE
        ok = d_said < d_canon                  # plus proche du prononce = fidele
        faithful += ok
        corrected += (d_canon < d_said)
        k = r.get("err_kind", "?")
        s = by_kind.setdefault(k, {"n": 0, "faithful": 0})
        s["n"] += 1
        s["faithful"] += ok

    n = len(rows)
    print(f"\n{'='*58}\nERREURS DELIBEREES ({n} clips tenus hors entrainement)\n{'='*58}")
    print(f"  transcrit CE QUI EST DIT (erreur detectable) : {faithful:>4} ({100*faithful/n:.1f}%)")
    print(f"  'corrige' vers le canonique (INVISIBLE)      : {corrected:>4} ({100*corrected/n:.1f}%)")
    print(f"\n  {'type':<12}{'n':>6}{'fidele':>10}")
    for k, s in sorted(by_kind.items()):
        print(f"  {k:<12}{s['n']:>6}{100*s['faithful']/s['n']:>9.1f}%")

    # ── Canonique (controle anti-oubli) ─────────────────────────────────────
    crows = [json.loads(l) for l in open(VAL_CANON, encoding="utf-8")][:args.limit]
    chyps = transcribe(model, [r["audio_filepath"] for r in crows])
    ccer = sum(cer(r["text"], h) for r, h in zip(crows, chyps)) / len(crows)
    print(f"\n{'='*58}\nCANONIQUE ({len(crows)} clips) -- controle anti-oubli\n{'='*58}")
    print(f"  CER moyen : {100*ccer:.2f}%")
    print("\n  (si ce chiffre explose, le melange a degrade le Coran :")
    print("   reduire --tts-rep/--asc-rep ou remonter --quran-hours)")


if __name__ == "__main__":
    main()
