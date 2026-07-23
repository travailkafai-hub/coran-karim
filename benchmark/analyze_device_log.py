"""Analyse un log de test DEVICE (recitation) et en sort un rapport lisible.

POURQUOI (demande utilisateur 2026-07-23) : jusqu'ici chaque diagnostic device
etait refait a coups de python jetable dans le shell -- donc non reproductible,
non comparable d'un test a l'autre, et perdu avec la session. Ce script fige
les extractions qui ont servi a trancher, pour que deux tests soient
comparables ligne a ligne.

Usage :
    python3 benchmark/analyze_device_log.py <log> [--fenetre HH:MM:SS-HH:MM:SS]

Les sections produites (et ce qu'elles ont permis de trancher le 2026-07-23) :

  BUILD/MODE      quel APK, quel preset -- sans ca on compare des pommes et
                  des poires entre deux sessions.
  TEXTE FIGE      ce que l'app a REELLEMENT valide, dans l'ordre. C'est ici
                  qu'on voit un verset manquant (90:11 absent entre 90:10 et
                  90:12, repere par l'utilisateur).
  ANCRE           progression de l'ancre d'alignement. Une ancre figee alors
                  que l'audio arrive = l'app n'avance plus.
  BILAN AUDIO     blocs PCM entres (80ms/bloc) vs croissance du buffer. L'ecart
                  = audio JETE par le portier RMS (BufferedTranscriber:549,
                  300ms de silence garde par pause). Mesure 2026-07-23 : 42%
                  de l'audio jete sur la session, concentre sur 3 intervalles.
  REGRESSIONS     segments ou l'apercu perd des mots QUAND LE BUFFER GROSSIT.
                  Signature de la derive de normalisation per_feature
                  (MelSpectrogram:234, mean/std recalcules sur tout le buffer).
                  Mesure 2026-07-23 : les 3 segments qui regressent sont
                  EXACTEMENT les 3 intervalles de perte audio massive -> c'est
                  ce 3/3 qui a etabli le lien hesitation -> derive -> ancre
                  bloquee.
  GEL vs APERCU   la re-transcription de gel perd-elle du texte ? Hypothese
                  que j'avais et que cette mesure a TUEE (0/16 le 2026-07-23) :
                  garder la section, c'est garder la trace que c'est verifie.
  VERDICTS        les decisions par mot (GOP) et les marqueurs d'anomalie.
"""
import argparse
import re
import sys
from collections import Counter

BLOC_MS = 80  # 2560 octets = 1280 echantillons @16kHz

RE_TS = re.compile(r"(\d\d):(\d\d):(\d\d)")
RE_BUILD = re.compile(r"BUILD code=(\S+)")
RE_MODE = re.compile(r"\[MODE\] (.+)")
RE_BLOC = re.compile(r"bloc PCM #(\d+)")
RE_PREVIEW = re.compile(r'retranscription (\d+)s -> (\d+)ms : "(.*)"')
RE_FIGE = re.compile(r'segment FIGE (\d+)s -> (\d+)ms : "(.*)"')
RE_FIGE_REUSE = re.compile(r'segment FIGE \(borne .*?\) : "(.*)"')
RE_ALIGN = re.compile(
    r"alignement seq=(\d+) ancre=(-?\d+) frontiere=(-?\d+) final=(\w+) "
    r"mots=(\d+) nouvelle_ancre=(-?\d+)"
)
RE_GOP = re.compile(
    r'\[GOP\] mot=(\d+) "([^"]*)".*?entendu="([^"]*)"(.*?)-> WordStatus\.(\w+)'
)
RE_ANOM = re.compile(r"(DESYNC|DERIVE|GEL DEGRADE)")


def secs(m):
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))


def hms(s):
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"


def parse(path, lo=None, hi=None):
    ev = []
    build = mode = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = RE_TS.search(line)
        if not m:
            continue
        ts = secs(m)
        if build is None:
            b = RE_BUILD.search(line)
            if b:
                build = b.group(1)
        if mode is None:
            mo = RE_MODE.search(line)
            if mo:
                mode = mo.group(1).strip()
        if lo is not None and not (lo <= ts <= hi):
            continue
        for kind, rx in (
            ("bloc", RE_BLOC), ("preview", RE_PREVIEW), ("fige", RE_FIGE),
            ("fige_reuse", RE_FIGE_REUSE), ("align", RE_ALIGN), ("gop", RE_GOP),
        ):
            g = rx.search(line)
            if g:
                ev.append((ts, kind, g))
                break
        else:
            a = RE_ANOM.search(line)
            if a:
                ev.append((ts, "anomalie", line.strip()))
    return ev, build, mode


def section(title):
    print(f"\n{'=' * 72}\n{title}\n{'=' * 72}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--fenetre", help="HH:MM:SS-HH:MM:SS")
    args = ap.parse_args()

    lo = hi = None
    if args.fenetre:
        a, b = args.fenetre.split("-")
        lo, hi = (secs(RE_TS.search(x)) for x in (a, b))

    ev, build, mode = parse(args.log, lo, hi)
    if not ev:
        print("aucun evenement reconnu — mauvais fichier ou mauvaise fenetre ?")
        return 1

    span = (ev[0][0], ev[-1][0])
    section("BUILD / MODE")
    print(f"  fichier   {args.log}")
    print(f"  build     {build or '(absent — APK anterieur a la trace BUILD)'}")
    print(f"  mode      {mode or '(non trace)'}")
    print(f"  fenetre   {hms(span[0])} -> {hms(span[1])}  ({span[1] - span[0]}s)")

    # --- texte fige, dans l'ordre : ce que l'app a reellement valide ---
    section("TEXTE FIGE (ce que l'app a valide, dans l'ordre)")
    for ts, k, g in ev:
        if k == "fige":
            print(f"  {hms(ts)}  [{g.group(1):>2}s]  {g.group(3)}")
        elif k == "fige_reuse":
            print(f"  {hms(ts)}  [apercu reutilise]  {g.group(1)}")

    # --- progression de l'ancre ---
    section("ANCRE (blocages = l'app n'avance plus)")
    prev_anchor, stuck_since, stalls = None, None, []
    for ts, k, g in ev:
        if k != "align":
            continue
        a = int(g.group(6))
        if a == prev_anchor:
            if stuck_since is None:
                stuck_since = ts
        else:
            if stuck_since is not None and ts - stuck_since >= 5:
                stalls.append((stuck_since, ts, prev_anchor))
            stuck_since = None
            prev_anchor = a
    if stuck_since is not None:
        stalls.append((stuck_since, span[1], prev_anchor))
    if stalls:
        for a, b, anc in stalls:
            print(f"  ancre BLOQUEE a {anc} de {hms(a)} a {hms(b)}  ({b - a}s)")
    else:
        print("  aucun blocage >=5s")

    # --- bilan audio : entre vs conserve ---
    section("BILAN AUDIO (blocs PCM entres vs croissance du buffer)")
    print("  ecart = audio JETE par le portier RMS (silence au-dela de 300ms/pause)")
    rows, prev, lastblk = [], None, None
    for ts, k, g in ev:
        if k == "bloc":
            lastblk = int(g.group(1))
        elif k == "preview":
            size = int(g.group(1))
            if prev and lastblk is not None and prev[2] is not None:
                d_in = (lastblk - prev[2]) * BLOC_MS / 1000
                d_buf = size - prev[1]
                if d_in > 0.5:
                    rows.append((prev[0], ts, d_in, d_buf, d_in - d_buf))
            prev = (ts, size, lastblk)
        elif k in ("fige", "fige_reuse"):
            prev = None
    if rows:
        tin = sum(r[2] for r in rows)
        tbuf = sum(r[3] for r in rows)
        pct = 100 * (tin - tbuf) / tin if tin else 0
        print(f"\n  TOTAL {tin:.1f}s entrees, buffer +{tbuf:.0f}s -> "
              f"JETE {tin - tbuf:.1f}s ({pct:.0f}%)")
        print(f"\n  {'intervalle':<21}{'entre':>8}{'buffer':>8}{'jete':>8}")
        for a, b, di, db, lost in sorted(rows, key=lambda r: -r[4])[:8]:
            flag = "  <<<" if lost >= 2 else ""
            print(f"  {hms(a)}->{hms(b)}  {di:>7.1f}s {db:>+7}s {lost:>7.1f}s{flag}")

    # --- regressions d'apercu ---
    section("REGRESSIONS D'APERCU (le buffer grossit, la transcription perd)")
    print("  signature de la derive de normalisation per_feature")
    segs, cur = [], []
    for ts, k, g in ev:
        if k == "preview":
            cur.append((ts, int(g.group(1)), g.group(3)))
        elif k in ("fige", "fige_reuse"):
            if cur:
                segs.append(cur)
            cur = []
    if cur:
        segs.append(cur)
    multi = [s for s in segs if len(s) >= 2]
    bad = 0
    for s in multi:
        nm = [len(x[2].split()) for x in s]
        if max(nm) > 0 and nm[-1] < max(nm):
            bad += 1
            print()
            for ts, sz, txt in s:
                print(f"   {hms(ts)}  buffer {sz}s  {len(txt.split())}m : \"{txt[:44]}\"")
    print(f"\n  => {bad}/{len(multi)} segments multi-apercus regressent")

    # --- gel vs apercu ---
    section("GEL vs DERNIER APERCU (le gel perd-il du texte ?)")
    last, perte, total = None, 0, 0
    for ts, k, g in ev:
        if k == "preview":
            last = g.group(3)
        elif k == "fige":
            total += 1
            frozen = g.group(3)
            np_ = len(last.split()) if last else 0
            nf = len(frozen.split())
            if last is not None and nf < np_:
                perte += 1
                print(f"  {hms(ts)}  apercu {np_}m -> FIGE {nf}m   <<< PERTE")
                print(f"            apercu: {last[:50]}")
                print(f"            fige  : {frozen[:50]}")
            last = None
        elif k == "fige_reuse":
            last = None
    print(f"  => {perte}/{total} gels ont fige MOINS de mots que l'apercu")

    # --- verdicts ---
    section("VERDICTS PAR MOT")
    st = Counter()
    non_verts = []
    for ts, k, g in ev:
        if k != "gop":
            continue
        status = g.group(5)
        st[status] += 1
        if status != "correct":
            non_verts.append((ts, g.group(1), g.group(2), g.group(3), status))
    print("  " + "  ".join(f"{k}={v}" for k, v in st.most_common()) or "  aucun")
    for ts, idx, attendu, entendu, status in non_verts:
        print(f"  {hms(ts)}  mot#{idx:<4} {attendu:<18} entendu=\"{entendu}\"  -> {status}")

    section("MARQUEURS D'ANOMALIE")
    anom = Counter()
    for ts, k, g in ev:
        if k == "anomalie":
            anom[RE_ANOM.search(g).group(1)] += 1
    print("  " + ("  ".join(f"{k}={v}" for k, v in anom.most_common())
                  if anom else "aucun"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
