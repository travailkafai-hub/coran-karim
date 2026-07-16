#!/usr/bin/env python3
"""Go/No-Go OFFLINE pour le rescoring tête-à-tête (Étape 5.1 du plan
REVUE_ARCHITECTURE_KARAOKE.md, proposition Fable §4.2 P1.2 -- développée ici
par l'agent exécutant, Sonnet).

LE PROBLEME QUE CE SCRIPT TESTE :
    Le gop actuel (forced - free) est un score RELATIF. Mesuré sur device
    aujourd'hui : attendu "صِرَٰطَ", prononcé "سَرَٰطَ" (sin au lieu de sad),
    gop=-0.35 -> jugé CORRECT. Le décodage libre avait pourtant bien entendu le
    sin (free quasi nul) -- mais le modèle hésitait sur TOUT à cet endroit,
    donc "forcer le sad" n'était "pas beaucoup pire" que le meilleur chemin
    libre -> écart faible -> vert. Ce n'est pas un problème de seuil : c'est le
    signal lui-même qui est mal posé.

L'IDEE TESTEE ICI :
    Au lieu de comparer "chemin forcé" à "chemin libre" (gop), comparer DEUX
    chemins forcés ENTRE EUX, tête-à-tête, sur le MEME audio :
        NLL(canonique) vs NLL(ce qui a été réellement prononcé)
    via la loss CTC standard (= -log P(séquence | audio) sous le modèle).
    Plus bas = meilleure explication de l'audio. Si "prononcé" bat toujours
    "canonique" quand c'est effectivement fautif, ce signal est absolu et
    exploitable en production (comparer le mot attendu à ses variantes
    confusables générées, sans connaître à l'avance ce qui sera dit).

    Si au contraire "canonique" gagne souvent MEME quand la personne a dit
    autre chose, le biais est acoustique (pas juste un artefact du décodage
    libre) et aucun rescoring ne le corrigera -- il faudrait alors plus de
    données d'entraînement sur cette confusion précise, pas un meilleur score.

SIMPLIFICATION délibérée vs la formulation initiale du plan : le plan
envisageait de forcer-aligner `correct_text` sur un énoncé PLUS LONG puis de
localiser les frames du mot muté. Inutile ici : chaque clip du holdout TTS
est un mot ISOLE (toute l'enregistrement = ce seul mot), donc on compare
directement le score CTC forcé du clip ENTIER pour chaque candidat. Cette
localisation redeviendra nécessaire le jour où le holdout contiendra des
énoncés multi-mots (ex. via build_confusable_splice_augmentation.py).

Go/No-Go : >75% de bonnes décisions sur `letter` (seuil de départ, cf. §6.4 de
REVUE_ARCHITECTURE_KARAOKE.md -- point de repère, pas une cible validée).

Usage :
    python3 variant_rescoring_eval.py <modele.nemo> [--limit N] [--cpu]
"""
import argparse
import json
import statistics
from pathlib import Path

import soundfile as sf
import torch
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL_ERRORS = BASE / "nemo_manifests_mixed" / "val_errors_annotated.jsonl"


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def load_model(nemo_path, use_cpu):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(nemo_path), map_location="cpu")
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0
    m.eval()
    # --cpu : mesurer pendant qu'un entraînement occupe le GPU (cf.
    # eval_error_detection.py, même motivation -- ne jamais risquer le run
    # en cours pour une mesure).
    if torch.cuda.is_available() and not use_cpu:
        m = m.cuda()
    return m


@torch.no_grad()
def logprobs_for_clip(model, path, device):
    """Reproduit EXACTEMENT le chemin de production (EncCTCWrapper des scripts
    d'export : encoder(audio_signal=mel, length) -> ctc_decoder -> log_softmax)
    -- même calcul que ce que le téléphone verrait, pas une approximation.

    Rééchantillonne à 16kHz si besoin : les clips TTS (XTTS-v2) sont en 24kHz
    natif. Bug réel de la version précédente de ce script -- un refus strict
    (`raise ValueError` si sr != 16000) a fait sauter les 1808/1808 lignes
    SILENCIEUSEMENT (aucune exception fatale, juste des `[skip]` un par un) et
    produit un "NO-GO 0.0%" qui ne mesurait rien du tout. eval_error_detection.py
    ne rencontrait pas ce problème car `model.transcribe()` rééchantillonne en
    interne (torchaudio/NeMo AudioSegment) -- ici, en lisant l'audio nous-mêmes
    via soundfile pour rester au plus près du pipeline mel->onnx de production,
    il faut le faire explicitement."""
    audio, sr = sf.read(path, dtype="float32")
    if sr != 16000:
        import librosa
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    audio_t = torch.tensor(audio, device=device).unsqueeze(0)
    len_t = torch.tensor([audio.shape[0]], dtype=torch.int64, device=device)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
    encoded, encoded_len = model.encoder(audio_signal=feats, length=feats_len)
    logits = model.ctc_decoder(encoder_output=encoded)
    logprobs = F.log_softmax(logits, dim=-1)  # (1, T, V+1)
    return logprobs, encoded_len


def ctc_forced_nll(logprobs, enc_len, token_ids, blank_id, device):
    """-log P(token_ids | audio) sous le CTC -- plus BAS = meilleure
    explication de l'audio par cette séquence de tokens. None si la longueur
    cible dépasse ce que les frames peuvent physiquement porter (T < 2S+1) --
    JAMAIS zero_infinity (qui ramènerait un cas infaisable à 0, soit
    artificiellement "excellent" : faux positif silencieux)."""
    if not token_ids:
        return None
    t = logprobs.transpose(0, 1)  # (T, N=1, C), format attendu par ctc_loss
    targets = torch.tensor([token_ids], dtype=torch.int64, device=device)
    target_len = torch.tensor([len(token_ids)], dtype=torch.int64, device=device)
    loss = F.ctc_loss(t, targets, enc_len, target_len, blank=blank_id,
                       reduction="sum", zero_infinity=False)
    val = loss.item()
    if val != val or val == float("inf"):  # NaN ou inf : cible infaisable
        return None
    return val


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=2000)
    ap.add_argument("--cpu", action="store_true")
    args = ap.parse_args()

    print(f"Chargement : {args.model}")
    model = load_model(args.model, args.cpu)
    device = next(model.parameters()).device
    blank_id = model.tokenizer.vocab_size  # même convention que ForcedAligner.kt

    rows = [json.loads(l) for l in open(VAL_ERRORS, encoding="utf-8")]
    rows = [r for r in rows if r.get("correct_text") and r["text"] != r["correct_text"]]
    rows = rows[:args.limit]
    print(f"Clips FAUTIFS à évaluer : {len(rows)} (device={device})\n")

    by_kind = {}
    infeasible = 0
    for i, r in enumerate(rows):
        try:
            logprobs, enc_len = logprobs_for_clip(model, r["audio_filepath"], device)
        except Exception as e:
            print(f"  [skip] {r.get('clip', '?')} : {e}")
            continue
        said_ids = model.tokenizer.text_to_ids(r["text"])
        canon_ids = model.tokenizer.text_to_ids(r["correct_text"])
        nll_said = ctc_forced_nll(logprobs, enc_len, said_ids, blank_id, device)
        nll_canon = ctc_forced_nll(logprobs, enc_len, canon_ids, blank_id, device)
        if nll_said is None or nll_canon is None:
            infeasible += 1
            continue
        margin = nll_canon - nll_said  # >0 => "prononcé" bat "canonique" (bon signal)
        k = r.get("err_kind", "?")
        s = by_kind.setdefault(k, {"n": 0, "win": 0, "margins": []})
        s["n"] += 1
        s["margins"].append(margin)
        if margin > 0:
            s["win"] += 1
        if (i + 1) % 200 == 0:
            print(f"  {i + 1}/{len(rows)}...")

    print(f"\n{'=' * 62}\nRESCORING TÊTE-À-TÊTE : 'prononcé' vs 'canonique'\n{'=' * 62}")
    print(f"{'type':<10}{'n':>6}{'gagne':>8}{'%':>8}{'marge médiane':>16}")
    total_n = total_win = 0
    for k, s in sorted(by_kind.items()):
        med = statistics.median(s["margins"]) if s["margins"] else float("nan")
        pct = 100 * s["win"] / s["n"] if s["n"] else 0.0
        print(f"{k:<10}{s['n']:>6}{s['win']:>8}{pct:>7.1f}%{med:>16.2f}")
        total_n += s["n"]
        total_win += s["win"]
    print("-" * 62)
    if total_n:
        print(f"{'TOTAL':<10}{total_n:>6}{total_win:>8}{100 * total_win / total_n:>7.1f}%")
    print(f"cibles infaisables (T trop court pour la séquence) : {infeasible}")

    letter = by_kind.get("letter", {"n": 0, "win": 0})
    letter_pct = 100 * letter["win"] / letter["n"] if letter["n"] else 0.0
    print(f"\nGo/No-Go (letter > 75%) : "
          f"{'GO' if letter_pct > 75 else 'NO-GO -- investiguer par confusion'}"
          f"  ({letter_pct:.1f}%)")


if __name__ == "__main__":
    main()
