"""
Construit un manifest 100% Hafs verifie, en excluant les recitateurs Warsh
(deja tagges riwaya="Warsh" dans download_assajda.py, jamais appliques en
aval) et le lot YouTube (provenance non verifiee, riwaya inconnue par clip).

Contexte : ~85 905 clips Warsh (21% du dataset) etaient melanges au Hafs sans
distinction dans manifest_unified.jsonl -> a contamine tous les trainings CTC
precedents. Necessaire avant tout entrainement voulant etre precis sur le
tajweed Hafs specifiquement.
"""
import json

EXCLUDE_RECITERS = {
    # riwaya="Warsh" dans download_assajda.py
    "AbdelKabirHadidi_assajda", "AbdelhamidHssain_assajda", "AbdelmoujibBenkirane_assajda",
    "AbdurrahimNabulsi_assajda", "FaysalWizar_assajda", "HosseinBousseksso_assajda",
    "LaayounKouchi_assajda", "MohamedChahboun_assajda", "MohamedElIraoui_assajda",
    "MohamedHamdan_assajda", "MohamedKantaoui_assajda", "MustaphaGharbi_assajda",
    "NurdinMaghriby_assajda", "OmarKazabri_assajda", "RachidBelaachya_assajda",
    "RachidBelalia_assajda", "RachidIfrad_assajda", "SamirBelaachya_assajda",
    "YassenJazairi_assajda", "YoussefEdghouch_assajda", "ZakariaHamama_assajda",
    # doublon marocain via download_moroccan.py (meme personne qu'OmarKazabri_assajda)
    "OmarQazabri_128kbps",
    # YouTube : provenance/riwaya non verifiee, volume marginal -> exclu par prudence
    "youtube_clean",
    # ── Mauvais tags Hafs decouverts a la verification manuelle (2026-07-12) ──
    # Les tags riwaya de download_assajda.py sont des SUPPOSITIONS geographiques
    # ("Warsh pour Maghreb, Hafs pour le reste") -> non fiables. Verifies un par un
    # sur assabile.com + test audio sur verset discriminant (3:146 qatala/qutila,
    # 57:24 presence de "howa"). Ces 2-la etaient tagges Hafs a tort :
    "HassanSaleh_assajda",     # apparait dans la liste Warsh officielle d'assabile (page 2)
    "AbdulRashidSufi_assajda", # recite en 8 riwayat, collection par defaut non confirmee Hafs
    # NB verifies OK Hafs et CONSERVES : AbdallahMatroud, AdelKalbani, AlzainMohamedAhmed,
    # MustaphaLahouni, AbdulWadudHaneef, AhmedSaoud, MohamedElBarak, MohamedMohisni,
    # KhalidAlJalil, AntarMuslim, SaberAbdulHakam, AbdallahKamel (pages assabile = Hafs A'n Assem).
    # Muhammad_AbdulKareem_128kbps (EveryAyah) verifie Hafs par test audio -> conserve.
}

IN_PATH = "data/manifest_unified.jsonl"
OUT_PATH = "data/manifest_hafs_only.jsonl"

kept = 0
excluded = 0
excluded_by_reciter = {}
with open(IN_PATH, encoding="utf-8") as f, open(OUT_PATH, "w", encoding="utf-8") as out:
    for l in f:
        o = json.loads(l)
        r = o.get("reciter", "?")
        if r in EXCLUDE_RECITERS:
            excluded += 1
            excluded_by_reciter[r] = excluded_by_reciter.get(r, 0) + 1
            continue
        out.write(l)
        kept += 1

print(f"Conserves (Hafs verifie) : {kept}")
print(f"Exclus (Warsh/non-verifie) : {excluded}")
print(f"Detail exclusions : {excluded_by_reciter}")
missing = EXCLUDE_RECITERS - set(excluded_by_reciter.keys())
if missing:
    print(f"ATTENTION - noms attendus mais absents du manifest (deja pas telecharges) : {missing}")
