"""Experimental occurrence metrics; never supplies human approval or a release gate."""
from pathlib import Path
import json, statistics, collections, re, sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/private/tmp/amt-accuracy-fix-task")
FIXTURES = {f["id"]: f for f in json.loads((ROOT / "frozen-fixtures.json").read_text())}
LABELS = json.loads((ROOT / "frozen-expectations.json").read_text())
INTENTS = ["requiredSpelling", "optionalStyle", "readabilityReview", "legalMarkerReview", "reference"]

def stats(values):
    values = [v for v in values if v is not None]
    return {"median": statistics.median(values), "min": min(values), "max": max(values), "n": len(values)} if values else None

def ratio(a, b):
    return a / b if b else None

def expected_occurrence(e, text):
    position = e.get("locationUTF16", e.get("location"))
    if position is None:
        return e.get("occurrence", 0)
    before = text.encode("utf-16-le")[:position * 2].decode("utf-16-le")
    return len(list(re.finditer(re.escape(e["original"]), before)))

def norm(s):
    return " ".join(s.strip('“”"').casefold().split())

def group_metrics(rows):
    counts = {k: collections.Counter() for k in INTENTS}
    local = collections.Counter()
    semantic = collections.Counter()
    coverage = collections.Counter()
    sources = collections.Counter()
    references = collections.Counter()
    model = collections.Counter()
    reasons = collections.Counter()
    stages = collections.defaultdict(list)
    by_fixture = collections.defaultdict(list)
    for row in rows:
        fid = row["fixtureID"]
        text = FIXTURES[fid]["text"]
        label = LABELS[fid]
        expected = [e for e in label["expected"] if e.get("intent") in INTENTS and e.get("original")]
        observed = row["findings"]
        matched_detection = set()
        matched_correction = set()
        for e in expected:
            intent = e["intent"]
            m = counts[intent]
            m["expected"] += 1
            category = "internalReference" if intent == "reference" else None
            occurrence = expected_occurrence(e, text)
            candidates = [(i, f) for i, f in enumerate(observed)
                          if i not in matched_detection and f.get("original") == e["original"]
                          and f.get("occurrence") == occurrence and f.get("anchorValid")
                          and (category is None or f.get("category") == category)]
            if candidates:
                index, finding = candidates[0]
                matched_detection.add(index)
                m["detected"] += 1
            else:
                m["missed"] += 1
            if e.get("replacement") is not None:
                correct = [(i, f) for i, f in candidates if i not in matched_correction
                           and f.get("status") == "SUGGESTION" and not f.get("readOnly", True)
                           and f.get("replacement") == e["replacement"]]
                if correct:
                    matched_correction.add(correct[0][0])
                    m["actionableCorrect"] += 1
                else:
                    m["notCorrected"] += 1
        # Unlabelled semantic findings never become gold negatives.
        if label.get("localGoldComplete"):
            local["completeGoldRuns"] += 1
            local["noChangeRuns"] += not expected
            no_change_has_actionable = False
            for i, finding in enumerate(observed):
                if finding.get("category") not in ["spelling", "grammar"]:
                    continue
                is_actionable = finding.get("status") == "SUGGESTION" and not finding.get("readOnly", True)
                is_spelling = finding.get("category") == "spelling"
                intent_matches = [e for e in expected if
                    finding.get("original") == e["original"]
                    and finding.get("occurrence") == expected_occurrence(e, text)]
                correct_detection = bool(intent_matches) and finding.get("anchorValid", False)
                local["detectionTP" if correct_detection else "detectionFP"] += 1
                if is_spelling:
                    local["spellingDetectionTP" if any(e["intent"] in ["requiredSpelling", "legalMarkerReview"] for e in intent_matches)
                          and finding.get("anchorValid", False) else "spellingDetectionFP"] += 1
                if is_actionable:
                    correct = any(e.get("replacement") == finding.get("replacement") for e in intent_matches) and finding.get("anchorValid", False)
                    local["actionableTP" if correct else "actionableFP"] += 1
                    if is_spelling:
                        local["spellingActionableTP" if correct else "spellingActionableFP"] += 1
                    if not expected:
                        local["noChangeActionableFP"] += 1
                        no_change_has_actionable = True
                elif not correct_detection:
                    local["unexpectedReadOnly"] += 1
            local["noChangeRunsWithActionableFP"] += no_change_has_actionable
        # Reference-specific fixtures have an explicit synthetic reference intent.
        # This does not label their unrelated semantic findings as gold negatives.
        if FIXTURES[fid]["category"] == "internalReference":
            references["runs"] += 1
            reference_gold = [e for e in expected if e["intent"] == "reference"]
            references["expected"] += len(reference_gold)
            references["negativeRuns"] += not reference_gold
            has_false = False
            for finding in observed:
                if finding.get("category") != "internalReference": continue
                correct = finding.get("anchorValid", False) and any(
                    finding.get("original") == e["original"]
                    and finding.get("occurrence") == expected_occurrence(e, text) for e in reference_gold)
                references["tp" if correct else "fp"] += 1
                has_false |= not correct
            references["negativeRunsWithFP"] += not reference_gold and has_false
        expected_semantic = label.get("semantic") if label.get("semanticGoldComplete") else None
        if expected_semantic:
            semantic["expected"] += 1
            defs = row["definitions"]
            classification = expected_semantic["classification"]
            alignment = expected_semantic["alignment"]
            if classification == "NOT_A_DEFINITION":
                semantic["mentionControls"] += 1
                semantic["mentionNoAssessment"] += not defs
                semantic["mentionExplicitNotDefinition"] += bool(defs) and all(d["classification"] == classification and d["alignment"] == alignment for d in defs)
                correct = not defs or all(d["classification"] == classification and d["alignment"] == alignment for d in defs)
                semantic["classificationCorrect"] += correct
                semantic["alignmentCorrect"] += correct
                semantic["jointCorrect"] += correct
                semantic["falseDefinition"] += not correct
            else:
                semantic["definitionControls"] += 1
                semantic["definitionClassificationCorrect"] += any(d["classification"] == classification for d in defs)
                semantic["definitionAlignmentCorrect"] += any(d["alignment"] == alignment and d.get("sourceID") == expected_semantic["sourceID"] for d in defs)
                semantic["classificationCorrect"] += any(d["classification"] == classification for d in defs)
                semantic["alignmentCorrect"] += any(d["alignment"] == alignment and d.get("sourceID") == expected_semantic["sourceID"] for d in defs)
                semantic["jointCorrect"] += any(d["classification"] == classification and d["alignment"] == alignment
                    and d.get("sourceID") == expected_semantic["sourceID"] for d in defs)
                semantic["abstention"] += not defs or any(d["classification"] == "NEEDS_REVIEW" or d["alignment"] == "NEEDS_REVIEW" for d in defs)
        for d in row["definitions"]:
            semantic["allAssessments"] += 1
            semantic["allAbstentions"] += d["classification"] == "NEEDS_REVIEW" or d["alignment"] == "NEEDS_REVIEW"
            if d.get("sourceID") and d.get("term") and d.get("sourceTerm") and (
                    "adalah" in text.lower() or "yang dimaksud dengan" in text.lower() or "didefinisikan" in text.lower()):
                sources["explicitShapedComparisons"] += 1
                sources["differentTerms"] += norm(d["term"]) != norm(d["sourceTerm"])
        coverage["partialRuns"] += row["partialRun"]
        coverage["invalidMappedAnchors"] += row["invalidMappedAnchors"]
        coverage["invalidActionableSources"] += row["invalidActionableSources"]
        coverage["skippedSegments"] += row["skippedSegments"]
        coverage["firstVisibleNull"] += row.get("firstVisible") is None
        coverage["firstActionableNull"] += row.get("firstActionable") is None
        obs = row.get("observation") or {}
        for key in ["modelCallCount", "definitionModelCallCount", "riskModelCallCount", "definitionResolutionModelCallCount"]:
            model[key] += obs.get(key, 0)
        model["cacheHits"] += obs.get("cacheHitCount", 0)
        model["e5Queries"] += obs.get("semanticQueryCount", 0)
        for stage in obs.get("stageMetrics", []):
            stages[stage["stage"]].append(stage["totalDuration"])
            if stage["stage"] == "contextClassification":
                model["contextModelCalls"] += stage["invocationCount"]
            if stage["stage"] == "tataKataScoring":
                model["tataScoringBatches"] += stage["invocationCount"]
        for segment in obs.get("segments", []):
            model["candidateRepairSegments"] += segment.get("repairCount", 0)
            model["definitionRepairs"] += segment.get("definitionRepairCount", 0) or 0
            for status in segment.get("stageCoverage", {}).values():
                coverage["stage." + status] += 1
            reasons.update(segment.get("candidateFilterReasons") or {})
        by_fixture[fid].append(row)
    result = {"records": len(rows), "occurrenceMetrics": {}, "localPrecision": dict(local),
              "definitionControls": dict(semantic), "sourceIdentityDiagnostics": dict(sources),
              "coverage": dict(coverage), "counters": dict(model), "filterReasons": dict(reasons),
              "referencePrecision": dict(references) | {"precision": ratio(references["tp"], references["tp"] + references["fp"]),
                  "negativeRunFPR": ratio(references["negativeRunsWithFP"], references["negativeRuns"])}}
    for intent, m in counts.items():
        result["occurrenceMetrics"][intent] = dict(m) | {
            "detectionRecall": ratio(m["detected"], m["expected"]),
            "actionableRecall": ratio(m["actionableCorrect"], m["expected"]) if intent in ["requiredSpelling", "optionalStyle"] else None}
    for key, tp, fp in [("detection", "detectionTP", "detectionFP"), ("actionable", "actionableTP", "actionableFP"),
                        ("spellingDetection", "spellingDetectionTP", "spellingDetectionFP"),
                        ("spellingActionable", "spellingActionableTP", "spellingActionableFP")]:
        result["localPrecision"][key + "Precision"] = ratio(local[tp], local[tp] + local[fp])
    result["counters"]["qwenCalls"] = sum(model[k] for k in ["modelCallCount", "definitionModelCallCount",
        "riskModelCallCount", "definitionResolutionModelCallCount", "contextModelCalls"])
    result["stages"] = {key: stats(values) for key, values in stages.items()}
    for key in ["total", "firstVisible", "firstActionable", "rssPeak", "mlxActivePeak", "mlxCachePeak"]:
        result[key] = stats([row.get(key) for row in rows])
    result["perFixture"] = {fid: {
        "total": stats([r["total"] for r in values]), "firstVisible": stats([r.get("firstVisible") for r in values]),
        "firstActionable": stats([r.get("firstActionable") for r in values]), "partialRuns": sum(r["partialRun"] for r in values),
        "rssPeak": stats([r.get("rssPeak") for r in values])} for fid, values in by_fixture.items()}
    return result

def evaluate(version):
    rows = [json.loads(p.read_text()) for p in sorted((ROOT / version / "matrix").glob("*.json"))
            if "-warm-" in p.name or "-cached-" in p.name]
    results = {}
    for mode in ["deterministic", "hybrid", "modelOnly"]:
        for phase in ["warm", "cached"]:
            selected = [r for r in rows if r["mode"] == mode and r["phase"] == phase]
            subsets = {"all": selected,
                "retrospective113": [r for r in selected if r["fixtureID"].startswith(("phase8-", "backend46-"))],
                "newRegression": [r for r in selected if r["fixtureID"].startswith("accuracy-v2-") and FIXTURES[r["fixtureID"]]["split"] == "regression"],
                "newHoldout": [r for r in selected if r["fixtureID"].startswith("accuracy-v2-") and FIXTURES[r["fixtureID"]]["split"] == "holdout"],
                "definitionControls": [r for r in selected if LABELS[r["fixtureID"]].get("semanticGoldComplete")],
                "dummy": [r for r in selected if r["fixtureID"].startswith("dummy-")]}
            results[mode + "/" + phase] = {key: group_metrics(values) for key, values in subsets.items()}
            results[mode + "/" + phase]["byIteration"] = {
                str(i): {k: v for k, v in group_metrics([r for r in selected if r["iteration"] == i]).items()
                         if k in ["records", "occurrenceMetrics", "localPrecision", "definitionControls", "coverage"]}
                for i in [1, 2, 3]}
            results[mode + "/" + phase]["newGroups"] = {
                str(i): group_metrics([r for r in selected if r["fixtureID"].startswith("accuracy-v2-g" + str(i) + "-")])
                for i in range(1, 9)}
    report = {"labelPolicy": "pending; assistant expectations are not human approval; insufficientEvidence",
              "expectationVersion": "accuracy-experiment-v2", "results": results}
    (ROOT / version / "accuracy-experiment-summary.json").write_text(json.dumps(report, indent=2))
    return report

if __name__ == "__main__":
    for version in sys.argv[2:] or ["before", "after"]:
        report = evaluate(version)
        print(version, {key: value["all"]["records"] for key, value in report["results"].items()})
