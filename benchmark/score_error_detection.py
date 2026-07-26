"""Test de BOUT EN BOUT de la chaine de recitation : l'app detecte-t-elle
reellement une faute, et laisse-t-elle passer une recitation correcte ?

POURQUOI CE BANC EXISTE (demande utilisateur 2026-07-26 : « on veut faire le
test de bout en bout qui soit valide »). Tous les bancs existants mesurent le
WER du TEXTE :
    eval_quran_vs_tts.py        WER sur clips propres
    simulate_sliding_window.py  WER dans le regime segmente
    compare_onnx_on_device_wavs.py  transcriptions cote a cote
Aucun ne mesure ce que l'app EXISTE POUR FAIRE. Un WER de 30 % ne dit ni si un
mot rate est passe au rouge, ni si un mot correct a ete valide. Un modele peut
tres bien avoir le meilleur WER du lot et rater toutes les fautes (il suffit
qu'il « corrige » silencieusement vers le texte canonique -- c'est exactement le
biais que le GOP existe pour contourner, cf. asr.md).
Trou deja identifie dans le projet : REFONTE_IHM.md §12, « la mesure de
detection de fautes deliberees n'existe pas ».

CE QUI REND LE TEST VALIDE
  1. Il tourne sur la VRAIE chaine (device) : micro -> BufferedTranscriber /
     streaming causal -> ForcedAligner -> jugement Dart. Aucune
     reimplementation Python, donc rien qui puisse « marcher au banc et pas
     dans l'app ».
  2. Il a une VERITE TERRAIN : la liste des mots volontairement mal recites,
     fournie par l'operateur du test (--errors).
  3. Il lit le PREMIER verdict de chaque mot, pas le dernier. Meme doctrine que
     `resume_log_recitation.py` (demande utilisateur 2026-07-25 : « sur un mot
     j'ai fait expres une erreur de harakat, c'etait jaune au debut mais
     repasse vert »). La question « le systeme a-t-il vu ma faute ? » se joue
     sur la premiere fois qu'il entend le mot ; le verdict final arrive souvent
     apres une correction reussie et ne dit donc rien sur la detection.

LES DEUX ERREURS N'ONT PAS LE MEME COUT -- ne pas les moyenner en une
« precision » unique :
  FAUX NEGATIF (faute non vue)  : l'app a echoue a sa raison d'etre. Le
      recitant croit avoir bien recite. C'est le plus grave.
  FAUX POSITIF (rouge injuste)  : l'app accuse a tort, declenche une
      correction non meritee et casse la confiance. Deja mesure comme le
      symptome dominant du 2026-07-25 (9 faux rouges contre 4 vraies fautes).

PROTOCOLE
  1. Choisir un passage et noter les index GLOBAUX des mots a mal reciter.
     (Index global = position dans la selection, 0-base -- c'est ce que loggue
     `[GOP] mot=N`.)
  2. Reciter le passage en faisant EXACTEMENT ces fautes, une seule fois,
     sans se corriger (une correction reussie brouille le premier verdict du
     mot suivant).
  3. Recuperer le log, puis :
       python3 benchmark/score_error_detection.py <log> --errors 3,7,12

USAGE
    python3 benchmark/score_error_detection.py <log> --errors 3,7,12
    python3 benchmark/score_error_detection.py <log> --errors-file fautes.txt
                                              [--final] [--csv out.csv]
"""
import argparse
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from resume_log_recitation import NEG, parse  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--errors", help="index globaux des mots mal recites, ex. 3,7,12")
    g.add_argument("--errors-file", help="un index par ligne")
    ap.add_argument("--final", action="store_true",
                    help="scorer le DERNIER verdict au lieu du premier "
                         "(mesure la correction, pas la detection -- cf. en-tete)")
    ap.add_argument("--csv")
    a = ap.parse_args()

    if a.errors_file:
        raw = Path(a.errors_file).read_text(encoding="utf-8").split()
    else:
        raw = a.errors.replace(",", " ").split()
    truth = {int(x) for x in raw if x.strip()}

    words, _ = parse(a.log)
    if not words:
        print("Aucun jugement [GOP] dans ce log -- la chaine n'a rien juge.")
        return 1

    unknown = truth - set(words)
    if unknown:
        # NE PAS ignorer silencieusement : un index attendu mais jamais juge
        # est en soi un resultat (mot jamais atteint, ou ancre bloquee avant).
        print(f"⚠️  {len(unknown)} mot(s) declare(s) faux mais JAMAIS juge(s) "
              f"par la chaine : {sorted(unknown)}")
        print("    -> soit la recitation ne les a pas atteints, soit l'ancre a "
              "bloque avant. A traiter comme des fautes NON VUES.\n")

    rows = []
    for i, w in sorted(words.items()):
        ev = w["ev"][-1 if a.final else 0]
        flagged = ev["v"] in NEG
        expected_bad = i in truth
        rows.append({
            "mot": i, "attendu": w["txt"], "entendu": ev["heard"],
            "verdict": ev["v"], "gop": ev["gop"],
            "faute_voulue": expected_bad, "signale": flagged,
            "cas": ("VRAI_POSITIF" if expected_bad and flagged else
                    "FAUX_NEGATIF" if expected_bad else
                    "FAUX_POSITIF" if flagged else "VRAI_NEGATIF"),
        })

    tp = [r for r in rows if r["cas"] == "VRAI_POSITIF"]
    fn = [r for r in rows if r["cas"] == "FAUX_NEGATIF"]
    fp = [r for r in rows if r["cas"] == "FAUX_POSITIF"]
    tn = [r for r in rows if r["cas"] == "VRAI_NEGATIF"]
    # Les mots jamais juges comptent comme des fautes non vues (cf. plus haut).
    n_fn = len(fn) + len(unknown)

    if a.csv:
        with open(a.csv, "w", newline="", encoding="utf-8") as f:
            wr = csv.DictWriter(f, fieldnames=list(rows[0]))
            wr.writeheader()
            wr.writerows(rows)
        print(f"CSV ecrit : {a.csv}\n")

    verdict_kind = "DERNIER" if a.final else "PREMIER"
    print(f"{'=' * 68}\nDETECTION DE FAUTES -- verdict {verdict_kind}, "
          f"{len(rows)} mots juges, {len(truth)} faute(s) voulue(s)\n{'=' * 68}")
    print(f"  fautes VUES            (vrai positif) : {len(tp):3d}")
    print(f"  fautes NON VUES        (faux negatif) : {n_fn:3d}   <-- le plus grave")
    print(f"  rouges INJUSTES        (faux positif) : {len(fp):3d}")
    print(f"  corrects VALIDES       (vrai negatif) : {len(tn):3d}")

    rappel = len(tp) / len(truth) if truth else float("nan")
    n_signales = len(tp) + len(fp)
    precision = len(tp) / n_signales if n_signales else float("nan")
    n_corrects = len(fp) + len(tn)
    taux_fp = len(fp) / n_corrects if n_corrects else float("nan")
    print(f"\n  rappel    (fautes vues / fautes reelles)      : {rappel:.0%}")
    print(f"  precision (vraies fautes / mots signales)     : {precision:.0%}")
    print(f"  taux de faux rouges (sur les mots corrects)   : {taux_fp:.0%}")

    if fn:
        print(f"\n── FAUTES NON VUES (validees a tort) ──")
        for r in fn:
            print(f"  mot {r['mot']:>3d} {r['attendu']:<18s} entendu=\"{r['entendu']}\" "
                  f"gop={r['gop']:>7s} -> {r['verdict']}")
    if fp:
        print(f"\n── ROUGES INJUSTES (mots corrects accuses) ──")
        for r in fp:
            print(f"  mot {r['mot']:>3d} {r['attendu']:<18s} entendu=\"{r['entendu']}\" "
                  f"gop={r['gop']:>7s} -> {r['verdict']}")

    print("\nLecture : le rappel dit si l'app fait son travail (voir les "
          "fautes) ;\nle taux de faux rouges dit si elle est vivable. Les deux "
          "doivent etre\nlus ensemble -- un rappel de 100 % obtenu en signalant "
          "tout est inutile.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
