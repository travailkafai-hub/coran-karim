"""Compare des statuts Kotlin en flux, sans reinterpretation des transcriptions."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "benchmark/replay_chaine_jvm_20260915"
rows = json.loads((OUT / "resultats.json").read_text(encoding="utf-8"))
# La garde compte 4 configurations par cas REELLEMENT rejoue, au lieu d'un 20
# fige : le banc portait cinq cas a l'ecriture, il en porte huit de plus depuis
# l'extension aux paliers, et une garde figee refusait des resultats corrects.
assert rows, "Replay vide"
_cas = {r["cas"] for r in rows}
assert len(rows) == 4 * len(_cas), (
    f"Replay incomplet : {len(rows)} lignes pour {len(_cas)} cas "
    f"({4 * len(_cas)} attendues, 4 configurations par cas)")


def signale(s):
    return s not in ("inconnu", "definitif:VERT", "provisoire:VERT")


def observations(case, config):
    result = []
    for line in (OUT / f"{case}_{config}.log").read_text(encoding="utf-8").splitlines():
        if "[vote-observation] " in line:
            o = json.loads(line.split("[vote-observation] ", 1)[1])
            result.append({k: v for k, v in o.items() if not k.startswith("t3")})
    return result


result = []
for case_id in dict.fromkeys(r["cas"] for r in rows):
    configs = {r["configuration"]: r for r in rows if r["cas"] == case_id}
    one = next(iter(configs.values()))
    m = json.loads((ROOT / "benchmark" / one["dossier"] / "manifest.json").read_text(encoding="utf-8"))
    case = next(c for c in m["cases"] if c["case_id"] == case_id)
    assert hashlib.sha256(Path(case["wav"]).read_bytes()).hexdigest() == case["sha256"]
    erreurs, insertions = set(), set()
    for op in case["operations"]:
        (insertions if "insertion" in op["family"] else erreurs).update(op["affected_word_indices"])
    corrects = set(range(len(case["expected_words"]))) - erreurs - insertions
    communs = set.intersection(*[{int(k) for k,s in c["statuts"].items() if s != "inconnu"} for c in configs.values()])
    detail = {"cas": case_id, "total": len(case["expected_words"]), "indices_communs": sorted(communs),
              "mutations": sorted(erreurs), "insertions_exclues": sorted(insertions), "configurations": {}}
    for config, row in configs.items():
        statuts = {int(k):s for k,s in row["statuts"].items()}
        metriques = {}
        for nature, population in [("mutations",erreurs),("corrects",corrects)]:
            juges = population & communs
            signales = sorted(i for i in juges if signale(statuts[i]))
            rouges = sorted(i for i in juges if statuts[i] == "definitif:ROUGE")
            metriques[nature] = {"denominateur_commun":len(juges),"signales":signales,"rouges_definitifs":rouges,
                "taux_signales":len(signales)/len(juges) if juges else None,
                "taux_rouges_definitifs":len(rouges)/len(juges) if juges else None,
                "total_manifest":len(population),"juges":sum(statuts[i]!="inconnu" for i in population),
                "signales_population_entiere":sorted(i for i in population if signale(statuts[i])),
                "rouges_population_entiere":sorted(i for i in population if statuts[i]=="definitif:ROUGE")}
        detail["configurations"][config] = metriques
        print(case_id,config,"stop",row["arret_decrochage"],
              "; ".join(f"{k}: signales {len(v['signales'])}/{v['denominateur_commun']}, rouges {len(v['rouges_definitifs'])}/{v['denominateur_commun']}" for k,v in metriques.items()))
    avant, apres = configs["vote_t3_legacy"]["statuts"], configs["vote_t3_bpe"]["statuts"]
    detail["changements_bpe"] = [{"mot":i,"attendu":case["expected_words"][i],"mutation":i in erreurs,
        "avant":avant[str(i)],"apres":apres[str(i)]} for i in range(len(case["expected_words"])) if avant[str(i)] != apres[str(i)]]
    detail["observations_hors_t3_identiques"] = observations(case_id,"vote_t3_legacy") == observations(case_id,"vote_t3_bpe")
    # Ne pas masquer un temoin entier derriere la couverture plus courte de
    # l'historique : apparier aussi LES DEUX entrees de tete, mot pour mot.
    # CES TROIS CONTROLES ETAIENT DES `assert` (arret au premier cas). Sur les
    # cinq cas d'origine ils tenaient ; en etendant aux huit paliers, T803 les
    # met en defaut -- la tete BPE y signale 14 mutations contre 15 pour la
    # tete a anciennes entrees. S'arreter la cacherait les sept autres cas,
    # alors que c'est justement un resultat a regarder : une detection perdue
    # par la correction peut n'etre qu'un faux positif qui tombait par hasard
    # sur une mutation. On COLLECTE donc au lieu d'interrompre.
    detail["anomalies"] = []
    if {k for k,s in avant.items() if s != "inconnu"} != {k for k,s in apres.items() if s != "inconnu"}:
        detail["anomalies"].append("couverture des deux tetes differente")
    perdues = sorted({i for i in erreurs if signale(avant[str(i)])} - {i for i in erreurs if signale(apres[str(i)])})
    if perdues:
        detail["anomalies"].append(f"mutations signalees par legacy et PAS par bpe : {perdues}")
    ajoutes = len([i for i in corrects if signale(apres[str(i)])]) - len([i for i in corrects if signale(avant[str(i)])])
    if ajoutes > 0:
        detail["anomalies"].append(f"bpe ajoute {ajoutes} faux signalements vs legacy")
    if detail["anomalies"]:
        print("   ANOMALIES", case_id, detail["anomalies"])
    print("Observations hors T3 identiques:",detail["observations_hors_t3_identiques"],"changements",detail["changements_bpe"])
    result.append(detail)
(OUT / "analyse.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
