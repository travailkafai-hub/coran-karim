"""Construit des labels PAR FRAME pour la tete 2 (tajwid), multi-label
(2026-07-24, decision utilisateur suite au diagnostic ٱلنَّاسِ : laam_shamsiyah
et ghunnah tombent sur les MEMES frames -- l'assimilation du lam DANS le noun
double EST la ghunnah, ce n'est pas un artefact d'annotation. La tete
actuelle est CTC+softmax (finetune_dual_head.py::_tajwid_loss) : une seule
classe gagnante par frame, sequence ORDONNEE -- structurellement incapable de
representer deux regles simultanees. Ce script derive, pour chaque regle
attendue, sa FENETRE DE FRAMES (via l'alignement force de la tete 1, deja
fiable, val_wer_ctc=0.124), independamment des autres regles -- le
chevauchement devient possible par construction.

AJOUT (demande utilisateur meme session) : deux classes WAQF supplementaires
-- lazim (arret OBLIGATOIRE) et waqf_awla (arret RECOMMANDE). Positions deja
connues (app/assets/data/quran_waqf.json, cf. FONCTIONNALITES_FUTURES.md §9).
Contrairement aux 17 regles existantes (dans le mot), le waqf se joue APRES
la fin du mot : fenetre = le silence REEL detecte juste apres (les recitateurs
du corpus sont professionnels, on suppose un waqf correctement observe --
meme logique que les 17 autres regles, apprises sur de la recitation correcte
sans etiquetage manuel "correct/incorrect"). Si aucun silence mesurable n'est
trouve (le recitateur a enchaine, cas autorise pour wasl_awla/jaiz mais pas
cense arriver sur lazim/waqf_awla), l'instance est OMISE (pas de faux
negatif force) -- meme philosophie que le masquage de la loss tajwid sur les
clips non annotes.

Sortie : nemo_manifests_dual/tajwid_frame_spans.jsonl
  {"audio_filepath": ..., "spans": [[class_id, start_frame, end_frame], ...]}
Un frame = une sortie encodeur (~80ms, meme grille que la tete 1 ET la tete 2,
partagent le meme encodeur).

Usage :
  SITE="benchmark/.venv_nemo/lib/python3.14/site-packages"
  PYTHONPATH="$PWD/$SITE" /usr/bin/python3.14 build_frame_level_tajwid_labels.py \
      --manifest nemo_manifests_dual/train_manifest.jsonl \
      --out nemo_manifests_dual/tajwid_frame_spans_train.jsonl
"""
import os, sys, json, re, argparse
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import numpy as np
import torch
import torch.nn as nn
import soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE = Path(__file__).parent
# Le run a ete DEPLACE sur le HDD (archivage du 2026-07-20, cf. CLAUDE.md
# "Runs archives sur le HDD") : meme chemin relatif, seule la racine change.
# On garde les deux et on prend celui qui existe -- un dossier absent du SSD
# n'est PAS une preuve que le run a disparu.
_CANDIDATS_NEMO = [
    BASE / "models" / "fastconformer-dual-head-v1" / "stageb-convhead-v1" / "stageb-final.nemo",
    Path("/run/media/kafai/HDD/Coran Karim/benchmark/models/fastconformer-dual-head-v1/"
         "stageb-convhead-v1/stageb-final.nemo"),
]
NEMO_PATH = next((c for c in _CANDIDATS_NEMO if c.exists()), _CANDIDATS_NEMO[0])
TAGGED_JSONL = BASE / "data" / "quran_tajweed_rules" / "uthmani_tajweed.jsonl"
WAQF_JSON = BASE.parent / "app" / "assets" / "data" / "quran_waqf.json"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
    # AJOUT waqf (2026-07-24) -- ids 17, 18. Uniquement les deux types a
    # signal acoustique net (arret reellement attendu) ; jaiz/wasl_awla/
    # mamnu/muanaqah/sakta laisses de cote (cf. discussion : mamnu = detecter
    # une ABSENCE de regle est un signal different, pas encore traite).
    "waqf_lazim", "waqf_awla",
]
RULE_ID = {name: i for i, name in enumerate(RULE_CLASSES)}
N_RULES = len(RULE_CLASSES)

# ── FUSION DE LA FAMILLE MADD (2026-08-04, --madd-binaire) ──────────────────
#
# IDEE DE L'UTILISATEUR, et la mesure lui donne raison deux fois.
#
# 1. CE QU'ON DEMANDAIT ETAIT IMPOSSIBLE. `madda_obligatory` (wajib muttasil,
#    4-5 harakat) et `madda_permissible` (jaiz munfasil, 4-5 harakat) ont LA
#    MEME LONGUEUR : ce qui les separe est la nature de ce qui SUIT la voyelle
#    longue -- une hamza dans le meme mot, ou dans le mot suivant. C'est une
#    categorie GRAMMATICALE, que le TEXTE connait deja (RecitedWord.
#    expectedRules). Une tete acoustique ne peut pas y repondre, et son echec
#    n'est pas un defaut d'entrainement.
#    Constate sur device (recitation PROFESSIONNELLE rejouee, preset tajwid) :
#    le mot 76 `إِلَّآ` est signale « madda_obligatory NON DETECTEE » alors que
#    la tete detecte `madda_permissible` au meme endroit -- le madd EST fait,
#    il est juste range dans la sous-famille voisine. L'app accuse donc a tort.
#
# 2. ET CETTE DEMANDE IMPOSSIBLE ABIME CE QUI ETAIT POSSIBLE. La distinction
#    qui compte -- long (4-6) contre court (2) -- ne se separe qu'a moitie :
#    AUC 0,653 par la duree, mesuree sur 410 detections d'une session reelle
#    APRES correction du decodage (mediane 3 frames contre 2, moyenne 5,95
#    contre 2,73). La tete a dilue sa capacite sur quatre classes dont trois se
#    recouvrent, au lieu de trancher la seule question de son ressort :
#    l'allongement a-t-il ete TENU ?
#
# CE QUE LA FUSION NE FAIT PAS : elle ne relache aucun critere. Fusionner
# seulement au DECODAGE reviendrait a accepter n'importe quel madd pour un
# madd obligatoire -- donc a valider un allongement court la ou il en faut un
# long, exactement le « demi-mot valide » que le projet interdit. Ici la fusion
# est faite dans les LABELS : la tete apprend « long » et « court » comme deux
# sons differents, et c'est le TEXTE qui dit lequel etait requis.
MADD_LONG = ("madda_necessary", "madda_obligatory", "madda_permissible")
MADD_COURT = ("madda_normal",)


def classes_binaires():
    """RULE_CLASSES avec la famille madd reduite a deux classes."""
    out = ["madd_long", "madd_court"]
    out += [c for c in RULE_CLASSES if c not in MADD_LONG + MADD_COURT]
    return out


def id_binaire(cls, table):
    """Id de `cls` dans la nomenclature fusionnee, ou None si hors perimetre."""
    if cls in MADD_LONG:
        return table["madd_long"]
    if cls in MADD_COURT:
        return table["madd_court"]
    return table.get(cls)

FULL_TAG_RE = re.compile(r'<tajweed\s+class=["\']?([a-z_]+)["\']?>(.*?)</tajweed>', re.S)
ANY_TAG_RE = re.compile(r"<[^>]+>")

# Frame ~80ms (grille encodeur FastConformer, meme sous-echantillonnage que
# la tete 1). SILENCE_RMS calibre sur BufferedTranscriber.SILENCE_RMS_THRESHOLD
# (meme notion cote app, -34dBFS) -- coherence delib. entre train et inference.
FRAME_SECONDS = 0.08
SAMPLE_RATE = 16000
SILENCE_RMS = 0.02
WAQF_MAX_LOOKAHEAD_FRAMES = 15   # ~1.2s max apres la fin du mot
WAQF_MIN_PAUSE_FRAMES = 2        # ~160ms min pour compter comme un vrai arret


class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


def load_verse_words(surah_filter=None):
    """Identique a test_forced_align_attribution.py::load_verse_words, mais
    charge TOUTES les sourates d'un coup (cle (surah,ayah)) -- ce script
    traite des clips de sourates variees, pas une seule a la fois."""
    verses = {}
    with open(TAGGED_JSONL, encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            s, a = d["verse_key"].split(":")
            s, a = int(s), int(a)
            if surah_filter is not None and s != surah_filter:
                continue
            tagged = re.sub(r"<span class=end>.*?</span>", "", d["text"])
            flat, spans = [], []
            pos, idx = 0, 0
            for m in FULL_TAG_RE.finditer(tagged):
                before = ANY_TAG_RE.sub("", tagged[idx:m.start()])
                flat.append(before); pos += len(before)
                content = ANY_TAG_RE.sub("", m.group(2))
                spans.append((pos, pos + len(content), m.group(1)))
                flat.append(content); pos += len(content)
                idx = m.end()
            flat.append(ANY_TAG_RE.sub("", tagged[idx:]))
            flat = "".join(flat)
            for ent, ch in [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]:
                flat = flat.replace(ent, ch)
            wb = []
            i, n_ = 0, len(flat)
            while i < n_:
                while i < n_ and flat[i].isspace():
                    i += 1
                if i >= n_:
                    break
                j = i
                while j < n_ and not flat[j].isspace():
                    j += 1
                wb.append((i, j)); i = j
            words = [flat[s0:e0] for s0, e0 in wb]

            def widx(off):
                for k, (s0, e0) in enumerate(wb):
                    if s0 <= off <= e0:
                        return k
                return len(wb) - 1

            junctions = []
            for st, en, cls in spans:
                if cls not in RULE_ID:
                    continue
                junctions.append((cls, widx(st), widx(max(st, en - 1))))
            verses[(s, a)] = (words, junctions)
    return verses


def load_waqf():
    """{(surah, ayah): {word_idx: type}} -- filtre lazim/waqf_awla seulement."""
    raw = json.load(open(WAQF_JSON, encoding="utf-8"))
    out = {}
    for key, marks in raw.items():
        s, a = key.split(":")
        kept = {int(wi): t for wi, t in marks.items() if t in ("lazim", "waqf_awla")}
        if kept:
            out[(int(s), int(a))] = kept
    return out


def ctc_forced_align(scoring_lp, flat, blank_id):
    t = len(scoring_lp)
    n = len(flat)
    s = 2 * n + 1
    NEG = -1e30
    prev = np.full(s, NEG)
    # int32 (pas int8, cf. bug decouvert 2026-07-24) : sous NumPy recent
    # (regles NEP 50), `si -= bp[ti][si]` fait deriver le TYPE de `si` vers
    # celui de bp -- si un verset a plus de ~63 tokens (s > 127), si deborde
    # int8 en cours de backtrace (OverflowError). int8 suffisait a l'usage
    # d'origine (versets courts testes manuellement) mais pas a un passage
    # systematique sur tout le corpus (versets longs inclus).
    bp = np.zeros((t, s), dtype=np.int32)

    def emit(ti, si):
        if si % 2 == 0:
            return scoring_lp[ti][blank_id]
        return scoring_lp[ti][flat[(si - 1) // 2]]

    prev[0] = emit(0, 0)
    if s > 1:
        prev[1] = emit(0, 1)
    cur = np.full(s, NEG)
    for ti in range(1, t):
        cur[:] = NEG
        for si in range(s):
            best = prev[si]; frm = 0
            if si >= 1 and prev[si - 1] > best:
                best = prev[si - 1]; frm = 1
            if (si >= 3 and si % 2 == 1 and
                    flat[(si - 1) // 2] != flat[(si - 3) // 2] and
                    prev[si - 2] > best):
                best = prev[si - 2]; frm = 2
            cur[si] = NEG if best <= NEG / 2 else best + emit(ti, si)
            bp[ti][si] = frm
        prev, cur = cur.copy(), prev
    best_end = int(np.argmax(prev))
    path = np.zeros(t, dtype=np.int32)
    si = best_end
    for ti in range(t - 1, -1, -1):
        path[ti] = si
        if ti > 0:
            si = int(si) - int(bp[ti][si])
    return path


def word_frame_spans(lp, words, tokenizer, blank):
    """Aligne les MOTS (forme nue) sur la tete 1 -> (first_frame, last_frame)
    par mot. Retourne None si desaccord de decoupage (meme garde-fou que
    RuleAnnotationService cote Dart : ne jamais risquer un mauvais mapping)."""
    word_tokens = [tokenizer.text_to_ids(w) for w in words]
    if any(len(t) == 0 for t in word_tokens):
        return None
    flat, owner = [], []
    for wi, toks in enumerate(word_tokens):
        for tk in toks:
            flat.append(tk); owner.append(wi)
    t = len(lp)
    if t < 2 * len(flat) + 1:
        return None
    path = ctc_forced_align(lp, flat, blank)
    first = [-1] * len(words)
    last = [-1] * len(words)
    for ti, si in enumerate(path):
        if si % 2 == 0:
            continue
        wi = owner[(si - 1) // 2]
        if first[wi] < 0:
            first[wi] = ti
        last[wi] = ti
    if any(f < 0 for f in first):
        return None
    return first, last


@torch.no_grad()
def encode(m, wav_path):
    a, sr = sf.read(str(wav_path), dtype="float32")
    if a.ndim > 1:
        a = a.mean(axis=1)
    dev = next(m.parameters()).device
    at = torch.tensor(a, device=dev).unsqueeze(0)
    lt = torch.tensor([a.shape[0]], dtype=torch.int64, device=dev)
    feats, flen = m.preprocessor(input_signal=at, length=lt)
    enc, enc_len = m.encoder(audio_signal=feats, length=flen)
    letters_logits = m.ctc_decoder(encoder_output=enc)
    lp = torch.log_softmax(letters_logits[0], dim=-1).cpu().numpy()
    return lp, a, sr


def waqf_span_after(a, sr, end_frame, resSamples_per_frame):
    """Cherche un VRAI silence juste apres la fin du mot (end_frame), dans
    l'audio brut (RMS, meme seuil que BufferedTranscriber cote app). Retourne
    (start_frame, end_frame_incl) ou None si pas de pause mesurable."""
    start_sample = int((end_frame + 1) * resSamples_per_frame)
    n_silent = 0
    for k in range(WAQF_MAX_LOOKAHEAD_FRAMES):
        s0 = start_sample + int(k * resSamples_per_frame)
        s1 = start_sample + int((k + 1) * resSamples_per_frame)
        if s0 >= len(a):
            break
        block = a[s0:min(s1, len(a))]
        if len(block) == 0:
            break
        rms = float(np.sqrt(np.mean(block.astype(np.float64) ** 2)))
        if rms < SILENCE_RMS:
            n_silent += 1
        else:
            break
    if n_silent >= WAQF_MIN_PAUSE_FRAMES:
        return end_frame + 1, end_frame + n_silent
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--madd-binaire", action="store_true",
                    help="fusionne la famille madd en madd_long / madd_court "
                         "(cf. MADD_LONG plus haut). Sans ce drapeau, la "
                         "nomenclature historique a 19 classes est conservee "
                         "-- aucune piste n'est eliminee.")
    args = ap.parse_args()

    # Nomenclature effective : historique (19 classes) ou fusionnee (17), selon
    # --madd-binaire. Les deux restent productibles -- « aucune piste n'est
    # eliminee tant que le retour en arriere est possible ».
    if args.madd_binaire:
        classes = classes_binaires()
        table = {n: i for i, n in enumerate(classes)}
        TABLE_ID = lambda c: id_binaire(c, table)
    else:
        classes = list(RULE_CLASSES)
        table = dict(RULE_ID)
        TABLE_ID = lambda c: table.get(c)
    globals()["TABLE_ID"] = TABLE_ID
    print(f"nomenclature : {len(classes)} classes"
          f"{' (madd FUSIONNE : madd_long / madd_court)' if args.madd_binaire else ' (historique)'}")
    # Le vocabulaire des regles accompagne les labels : sans lui, impossible de
    # savoir a quoi correspond un id plus tard (piege paye avec rules.json).
    Path(args.out).with_suffix(".classes.json").write_text(
        json.dumps(classes, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"chargement {NEMO_PATH} ...")
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero(); m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
        print("GPU:", torch.cuda.get_device_name(0))
    blank = m.tokenizer.vocab_size
    tokenizer = m.tokenizer

    print("chargement annotation tajweed (toutes sourates) ...")
    verses = load_verse_words()
    waqf = load_waqf()
    print(f"  {len(verses)} versets annotes, {len(waqf)} versets avec waqf lazim/awla")

    fname_re = re.compile(r"(\d+)_(\d+)\.wav$")
    n_ok = n_skip_shape = n_skip_align = n_no_verse = 0
    n_waqf_found = n_waqf_missed = 0

    with open(args.manifest, encoding="utf-8") as fin, open(args.out, "w", encoding="utf-8") as fout:
        for li, line in enumerate(fin):
            if args.limit and li >= args.limit:
                break
            r = json.loads(line)
            if not r.get("text_tajwid"):
                continue
            fp = r["audio_filepath"]
            mobj = fname_re.search(fp)
            if not mobj:
                n_no_verse += 1
                continue
            surah, ayah = int(mobj.group(1)), int(mobj.group(2))
            entry = verses.get((surah, ayah))
            if entry is None:
                n_no_verse += 1
                continue
            words, junctions = entry
            if not junctions and (surah, ayah) not in waqf:
                continue  # rien a etiqueter sur ce verset (ne devrait pas arriver si text_tajwid non vide)

            try:
                lp, audio, sr = encode(m, fp)
            except Exception as e:
                n_skip_align += 1
                continue

            aligned = word_frame_spans(lp, words, tokenizer, blank)
            if aligned is None:
                n_skip_shape += 1
                continue
            first, last = aligned
            t_frames = len(lp)
            samples_per_frame = len(audio) / t_frames if t_frames > 0 else 0

            spans = []
            for cls, wstart, wend in junctions:
                cid = TABLE_ID(cls)
                if cid is None:
                    continue
                f0 = first[wstart]
                f1 = last[wend]
                if f0 >= 0 and f1 >= f0:
                    # Dilatation +-1 frame (2026-07-24, verifie sur 114:2 :
                    # ghunnah/laam_shamsiyah alignes sur UNE SEULE frame,
                    # comportement CTC "peaky" deja documente cette session --
                    # une fenetre a 1 frame est trop fragile pour entrainer
                    # (imprecision de bord connue de l'alignement force). La
                    # tete ConvTajwidHead a de toute facon un noyau temporel
                    # de 5 frames (cf. son commentaire), donc une marge de 1
                    # frame ne change rien a sa capacite, juste a la tolerance
                    # du label.
                    f0d = max(0, int(f0) - 1)
                    f1d = min(t_frames - 1, int(f1) + 1)
                    spans.append([cid, f0d, f1d])

            for widx, wtype in waqf.get((surah, ayah), {}).items():
                if widx < 0 or widx >= len(words):
                    continue
                end_f = last[widx]
                if end_f < 0:
                    continue
                found = waqf_span_after(audio, sr, end_f, samples_per_frame)
                if found:
                    n_waqf_found += 1
                    # wtype = "lazim" -> classe "waqf_lazim" ; wtype deja
                    # "waqf_awla" -> classe "waqf_awla" telle quelle (source
                    # quran_waqf.json n'a pas un prefixe uniforme).
                    cid = TABLE_ID(wtype if wtype.startswith("waqf_")
                                   else f"waqf_{wtype}")
                    if cid is None:
                        continue
                    spans.append([cid, int(found[0]), int(found[1])])
                else:
                    n_waqf_missed += 1

            if not spans:
                continue
            fout.write(json.dumps({"audio_filepath": fp, "n_frames": t_frames, "spans": spans},
                                   ensure_ascii=False) + "\n")
            n_ok += 1
            if n_ok % 500 == 0:
                print(f"  {n_ok} clips traites (li={li}) ...")

    print(f"\nTermine : {n_ok} clips avec spans ecrits -> {args.out}")
    print(f"  ignores: pas de verse_key match={n_no_verse}, echec forme mots={n_skip_shape}, "
          f"echec inference={n_skip_align}")
    print(f"  waqf: {n_waqf_found} pauses trouvees, {n_waqf_missed} manquees (recitateur a enchaine)")


if __name__ == "__main__":
    main()
