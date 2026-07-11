"""Re-decoupe les sourates assajda par ALIGNEMENT FORCE (repare le decoupage uniforme).

Cause reparee : download_assajda.py decoupait chaque sourate en tranches de duree
EGALE (split_by_verse_uniform) -> derive cumulative, l'audio du "verset 107" contient
en realite le verset ~98. Les MP3 sourates complets ont ete conserves (data/train/).

Methode :
  1. MP3 sourate -> WAV 16k mono (ffmpeg, temporaire)
  2. Emissions CTC par chunks de 20s (wav2vec2-large-xlsr-53-arabic, GPU fp16)
  3. torchaudio.functional.forced_align du texte COMPLET de la sourate (mots separes
     par le token "|" du vocab) -> frame de debut/fin de chaque mot -> frontieres verset
  4. Decoupe au midpoint entre fin du verset v et debut du v+1 (+marge), reecrit
     train_wav/{reciter}/{s}_{v}.wav (ecrase les anciens desalignes)
  5. Reecrit data/train_{reciter}.jsonl avec duration + align_score (log-prob moyen)

La basmala/isti3adha en debut de sourate est absorbee par les frames blank (CTC).
Reciteurs Warsh : texte Hafs utilise -> score plus bas attendu, les versets a score
faible seront filtres au rebuild du manifest.

Usage :
  python realign_assajda.py --reciter SaberAbdulHakam_assajda --surahs 26
  python realign_assajda.py --reciter all
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import sys, json, re, argparse, subprocess, tempfile, time
from pathlib import Path
import numpy as np
import torch, torchaudio, soundfile as sf

sys.stdout.reconfigure(encoding="utf-8")

BASE = Path(__file__).parent
DATA = BASE / "data"
MP3_ROOT = DATA / "train"
WAV_ROOT = DATA / "train_wav"
ALIGNER = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
CHUNK_S = 20.0          # duree des chunks encodeur
FRAME_S = 0.02          # stride wav2vec2 (~20ms/frame)
PAD_S = 0.15            # marge autour des frontieres de coupe
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
# Le groupage par budget de TOKENS (MAX_TOK, independant de la duree totale) borne deja
# chaque appel forced_align -> pas de risque memoire/segfault quelle que soit la duree de
# la sourate. Sur les tres longues sourates (Al-Baqarah ~2.2h) la qualite mesuree est plus
# faible (similarite ~0.4-0.5 au lieu de ~0.8) a cause de la derive de l'estimation
# proportionnelle -> filtre via align_score en aval plutot qu'exclusion a priori.
MAX_SURAH_DUR_S = float("inf")
BASMALA = "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ"

# harakat + annotations a retirer (regex eprouvee du projet) ; wasla -> alef ;
# on GARDE hamzas/variantes (presentes dans le vocab de l'aligneur) ; tout caractere
# restant hors-vocab est de toute facon filtre par norm_word.
_STRIP = re.compile(r'[ً-ٰٟؐ-ؚۖ-ۭـ۟-۪ۤۧۨ]')

def load_quran() -> dict:
    q = {}
    for src in [DATA/"manifest_full_wav.jsonl", DATA/"train_combined.jsonl"]:
        if src.exists():
            for line in open(src, encoding="utf-8"):
                try:
                    e = json.loads(line)
                    if e.get("text"): q.setdefault(e["key"], e["text"])
                except Exception: pass
            if q: break
    return q

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reciter", required=True, help="nom dossier (ex: SaberAbdulHakam_assajda) ou 'all'")
    ap.add_argument("--surahs", default=None, help="ex: 26 ou 1-114")
    args = ap.parse_args()

    from transformers import AutoProcessor, AutoModelForCTC
    print(f"Chargement aligneur {ALIGNER} sur {DEVICE}...", flush=True)
    proc = AutoProcessor.from_pretrained(ALIGNER)
    model = AutoModelForCTC.from_pretrained(ALIGNER, dtype=torch.float16 if DEVICE=="cuda" else torch.float32).to(DEVICE).eval()
    vocab = proc.tokenizer.get_vocab()
    WORD_SEP = vocab.get("|", None)
    assert WORD_SEP is not None, "token | absent du vocab"

    def norm_word(w: str) -> list[int]:
        w = w.replace("ٱ", "ا")
        w = _STRIP.sub("", w)
        return [vocab[c] for c in w if c in vocab]

    quran = load_quran()
    print(f"{len(quran)} versets de reference charges", flush=True)

    if args.reciter == "all":
        reciters = sorted(p.name for p in MP3_ROOT.iterdir()
                          if p.is_dir() and p.name.endswith("_assajda"))
    else:
        reciters = [args.reciter]

    surah_filter = None
    if args.surahs:
        surah_filter = set()
        for seg in args.surahs.split(","):
            if "-" in seg:
                a, b = seg.split("-"); surah_filter.update(range(int(a), int(b)+1))
            else:
                surah_filter.add(int(seg))

    state_path = BASE / "logs" / "realign_state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}

    for reciter in reciters:
        mp3_dir = MP3_ROOT / reciter
        wav_dir = WAV_ROOT / reciter
        wav_dir.mkdir(parents=True, exist_ok=True)
        mp3s = sorted(mp3_dir.glob("*.mp3"))
        if surah_filter:
            mp3s = [m for m in mp3s if int(m.stem) in surah_filter]
        print(f"\n===== {reciter} : {len(mp3s)} sourates =====", flush=True)
        entries = []
        # recharge les entrees deja realignees (reprise)
        out_jsonl = DATA / f"train_{reciter}.jsonl"
        done_key = lambda s: f"{reciter}/{s}"

        for mp3 in mp3s:
            surah = int(mp3.stem)
            if state.get(done_key(surah)) == "ok" and not surah_filter:
                continue
            t0 = time.time()
            # 1. texte de la sourate
            verses = []
            v = 1
            while f"{surah}:{v}" in quran:
                verses.append((v, quran[f"{surah}:{v}"]))
                v += 1
            if not verses:
                print(f"  s{surah:03d}: pas de texte, skip", flush=True); continue

            # tokens cibles : mots separes par WORD_SEP ; spans (verset -> [i0,i1) tokens)
            # Basmala "fantome" en tete (sourates != 1,9) : elle est recitee a l'oral
            # avant le verset 1 mais absente du texte cible -> sans cet ancrage, l'aligneur
            # l'absorbe dans le verset 1 (cause du sim<0.5 observe sur les versets 1/2).
            tokens, verse_tok_spans = [], []
            skipped_words = 0
            if surah not in (1, 9):
                for w in BASMALA.split():
                    ids = norm_word(w)
                    if not ids: continue
                    if tokens: tokens.append(WORD_SEP)
                    tokens.extend(ids)
            for vi, (vnum, text) in enumerate(verses):
                start = len(tokens)
                for w in text.split():
                    ids = norm_word(w)
                    if not ids:
                        skipped_words += 1; continue
                    if tokens: tokens.append(WORD_SEP)
                    tokens.extend(ids)
                verse_tok_spans.append((vnum, start, len(tokens)))
            if len(tokens) < 10:
                print(f"  s{surah:03d}: tokens insuffisants, skip", flush=True); continue

            # 2. decode mp3 -> wav 16k
            with tempfile.TemporaryDirectory() as td:
                tmp_wav = Path(td) / "s.wav"
                r = subprocess.run(["ffmpeg","-y","-i",str(mp3),"-ar","16000","-ac","1",str(tmp_wav)],
                                   capture_output=True)
                if r.returncode != 0 or not tmp_wav.exists():
                    print(f"  s{surah:03d}: ffmpeg ECHEC", flush=True); continue
                audio, sr = sf.read(str(tmp_wav), dtype="float32")
            dur = len(audio)/sr
            if dur > MAX_SURAH_DUR_S:
                print(f"  s{surah:03d}: {dur/60:.0f}min > {MAX_SURAH_DUR_S/60:.0f}min "
                      f"(sourate longue, ancrage sequentiel pas encore fiable ici) -> SKIP", flush=True)
                continue

            # 3. emissions par chunks CHEVAUCHANTS (30s, recouvrement 2s, bords rognés)
            # -> evite les artefacts de coupure en plein mot a chaque frontiere
            win = int(30.0 * sr)
            hop = int(28.0 * sr)
            trim_frames = None  # frames a rogner de chaque cote (calcule au 1er chunk)
            ems = []
            with torch.no_grad():
                i = 0
                first = True
                while i < len(audio):
                    seg = audio[i:i+win]
                    if len(seg) < int(0.2*sr): break
                    inp = proc(seg, sampling_rate=sr, return_tensors="pt")
                    x = inp.input_values.to(DEVICE, dtype=model.dtype)
                    logits = model(x).logits.float()          # (1,T,V)
                    lp = torch.log_softmax(logits, dim=-1)[0].cpu()
                    if trim_frames is None:
                        # ~50 frames/s -> 1s de recouvrement rogne de chaque cote
                        trim_frames = int(round(lp.shape[0] / (len(seg)/sr)))  # frames/s
                    last = i + win >= len(audio)
                    a0 = 0 if first else trim_frames
                    a1 = lp.shape[0] if last else lp.shape[0] - trim_frames
                    ems.append(lp[a0:a1])
                    first = False
                    if last: break
                    i += hop
            if not ems:
                print(f"  s{surah:03d}: pas d'emissions", flush=True); continue
            emissions = torch.cat(ems, dim=0).unsqueeze(0)     # (1,T,V)
            T = emissions.shape[1]
            frame_dur = dur / T
            print(f"  s{surah:03d} DEBUG: dur={dur:.1f}s T={T} frame_dur={frame_dur*1000:.2f}ms "
                  f"tokens={len(tokens)} n_chunks={len(ems)}", flush=True)

            # 4. alignement force PAR GROUPES DE VERSETS (estimation PROPORTIONNELLE simple).
            # forced_align est O(T*U) en memoire (grille trellis) : pour une longue sourate
            # (Al-Baqarah, ~2.2h/286 versets), T*U peut depasser plusieurs milliards de
            # cellules -> segfault/OOM, d'ou le decoupage en groupes <= MAX_TOK tokens.
            # Version VALIDEE (similarite caractere mediane 0.82 sur sourates 12/26, test
            # manuel + QA) : fenetre estimee par simple PROPORTION de tokens x duree totale,
            # marge 30%. Un ancrage sequentiel (curseur = fin reelle du groupe precedent) a
            # ete tente pour les sourates tres longues mais s'est avere moins fiable (voir
            # BENCHMARK_RESULTS.md) -> abandonne, on garde le proportionnel simple partout et
            # on exclut juste les sourates > MAX_SURAH_DUR_S en amont.
            MAX_TOK = 400
            frame_of_tok = [None]*len(tokens)
            score_of_tok = [0.0]*len(tokens)

            group_bounds = []
            g_start = 0
            for vnum, i0, i1 in verse_tok_spans:
                if i1 - g_start > MAX_TOK and i0 > g_start:
                    group_bounds.append((g_start, i0))
                    g_start = i0
            if g_start < len(tokens):
                group_bounds.append((g_start, len(tokens)))

            for tok_start, tok_end in group_bounds:
                if tok_end <= tok_start: continue
                grp_tokens = tokens[tok_start:tok_end]
                t_lo_est = (tok_start/len(tokens)) * dur
                t_hi_est = (tok_end/len(tokens)) * dur
                pad = max(30.0, 0.3*(t_hi_est - t_lo_est))
                f_lo = max(0, int((t_lo_est - pad)/frame_dur))
                f_hi = min(T, int((t_hi_est + pad)/frame_dur))
                if f_hi - f_lo < len(grp_tokens):
                    f_lo, f_hi = 0, T
                sub_em = emissions[:, f_lo:f_hi, :]
                tg = torch.tensor([grp_tokens], dtype=torch.int64)
                try:
                    aligned, scores = torchaudio.functional.forced_align(
                        sub_em, tg, torch.tensor([sub_em.shape[1]]), torch.tensor([len(grp_tokens)]), blank=0)
                except Exception as ex:
                    print(f"  s{surah:03d} [tok {tok_start}:{tok_end}]: forced_align ECHEC ({ex})", flush=True)
                    continue
                aligned_l = aligned[0].tolist(); fscores_l = scores[0].tolist()
                ptr = 0
                for f, tok in enumerate(aligned_l):
                    gi = tok_start + ptr
                    if ptr < len(grp_tokens) and tok == grp_tokens[ptr]:
                        if frame_of_tok[gi] is None:
                            frame_of_tok[gi] = f_lo + f
                            score_of_tok[gi] = fscores_l[f]
                        if f+1 >= len(aligned_l) or aligned_l[f+1] != tok:
                            ptr += 1

            # 5. frontieres versets -> decoupe
            n_ok = 0
            vinfos = []
            for vi, (vnum, i0, i1) in enumerate(verse_tok_spans):
                fs = [frame_of_tok[i] for i in range(i0, i1) if frame_of_tok[i] is not None]
                sc = [score_of_tok[i] for i in range(i0, i1) if frame_of_tok[i] is not None]
                if not fs:
                    vinfos.append(None); continue
                vinfos.append({"vnum": vnum, "f0": min(fs), "f1": max(fs),
                               "score": float(np.mean(sc))})
            for vi, info in enumerate(vinfos):
                if info is None: continue
                t_start = info["f0"]*frame_dur
                t_end   = (info["f1"]+1)*frame_dur
                # coupe au midpoint entre versets voisins (frontiere naturelle)
                prev = next((vinfos[j] for j in range(vi-1, -1, -1) if vinfos[j]), None)
                nxt  = next((vinfos[j] for j in range(vi+1, len(vinfos)) if vinfos[j]), None)
                lo = max(0.0, t_start - 0.3) if prev is None else ((prev["f1"]+1)*frame_dur + t_start) / 2
                hi = min(dur, t_end + 0.5)   if nxt  is None else (t_end + nxt["f0"]*frame_dur) / 2
                seg = audio[int(lo*sr):int(hi*sr)]
                if len(seg) < int(0.4*sr): continue
                key = f"{surah}:{info['vnum']}"
                out_wav = wav_dir / f"{surah}_{info['vnum']}.wav"
                tmp_out = out_wav.with_suffix(".tmp.wav")
                sf.write(str(tmp_out), seg, sr, subtype="PCM_16")
                os.replace(tmp_out, out_wav)
                entries.append({
                    "key": key, "reciter": reciter, "text": quran[key],
                    "wav": str(out_wav.absolute()).replace("\\", "/"),
                    "duration": round(len(seg)/sr, 3),
                    "align_score": round(info["score"], 3),
                })
                n_ok += 1
            state[done_key(surah)] = "ok"
            state_path.parent.mkdir(exist_ok=True)
            state_path.write_text(json.dumps(state))
            mean_sc = float(np.mean([e["align_score"] for e in entries[-n_ok:]])) if n_ok else 0.0
            print(f"  s{surah:03d}: {n_ok}/{len(verses)} versets realignes "
                  f"(score moy {mean_sc:.2f}, {dur/60:.1f}min, {time.time()-t0:.0f}s)", flush=True)

        # reecrit le jsonl du reciteur (fusion avec l'existant realigne si reprise partielle)
        if entries:
            old = {}
            if out_jsonl.exists():
                for line in open(out_jsonl, encoding="utf-8"):
                    try:
                        e = json.loads(line)
                        # ne garder l'ancien QUE s'il a un align_score (deja realigne)
                        if "align_score" in e: old[e["key"]] = e
                    except Exception: pass
            for e in entries: old[e["key"]] = e
            merged = sorted(old.values(), key=lambda x: (int(x["key"].split(":")[0]), int(x["key"].split(":")[1])))
            with open(out_jsonl, "w", encoding="utf-8") as f:
                for e in merged: f.write(json.dumps(e, ensure_ascii=False) + "\n")
            print(f"  -> {out_jsonl.name}: {len(merged)} versets (realignes)", flush=True)

    print("REALIGN DONE", flush=True)

if __name__ == "__main__":
    main()
