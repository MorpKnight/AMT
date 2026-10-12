from pathlib import Path
import json, sys, statistics, hashlib

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/private/tmp/amt-accuracy-fix-task")
def stats(values):
    values = [v for v in values if v is not None]
    return {"median": statistics.median(values), "min": min(values), "max": max(values), "n": len(values)} if values else None
def delta(before, after):
    if before is None or after is None: return None
    return {"absolute": after - before, "percent": (after - before) / before * 100 if before else None}
def counters(row):
    obs = row.get("observation") or {}
    qwen = row.get("contextModelCalls", 0) + sum(obs.get(k, 0) for k in ["modelCallCount", "definitionModelCallCount", "riskModelCallCount", "definitionResolutionModelCallCount"])
    return {"qwen": qwen, "e5": obs.get("semanticQueryCount", 0), "tataBatches": sum(s["invocationCount"] for s in obs.get("stageMetrics", []) if s["stage"] == "tataKataScoring"),
        "cacheHits": obs.get("cacheHitCount", 0),
        "candidateRepairSegments": sum(s.get("repairCount", 0) for s in obs.get("segments", [])),
        "definitionRepairs": sum(s.get("definitionRepairCount") or 0 for s in obs.get("segments", [])),
        "fallbacks": obs.get("fallbackCount", 0)}
def coverage(row):
    statuses = [v for s in (row.get("observation") or {}).get("segments", []) for v in s.get("stageCoverage", {}).values()]
    return {"failed": statuses.count("failed"), "tooLong": statuses.count("tooLong"), "cancelled": statuses.count("cancelled"), "skippedByPolicy": statuses.count("skippedByPolicy")}
def envelope_summary(e):
    rows=e["records"]
    values={k:stats([r.get(k) for r in rows]) for k in ["total","firstVisible","firstLocalActionable","peakResidentBytes","mlxActivePeak","mlxCachePeak","mlxEndActive","mlxEndCache"]}
    values["preparation"]=e.get("preparationDuration",e.get("preparation"))
    values["counters"]={k:sum(counters(r)[k] for r in rows) for k in counters(rows[0])}
    values["coverage"]={k:sum(coverage(r)[k] for r in rows) for k in coverage(rows[0])}
    values["invalidAnchors"]=sum(r.get("invalidAnchors",0) for r in rows)
    values["invalidSources"]=sum(r.get("invalidSources",0) for r in rows)
    values["findingsPerRun"]=[len(r.get("normalizedFindings",[])) for r in rows]
    values["incrementalEquivalentToFresh"]=[r["incrementalEquivalentToFresh"] for r in rows if "incrementalEquivalentToFresh" in r]
    return values

result={"baselineCommit":"b2759f53af56105805fe64fd5009bc3d3128eff5","pipeline":{},"accuracy":{}}
for p in sorted((ROOT/"before/pipeline").glob("*.json")):
    q=ROOT/"after/pipeline"/p.name
    if not q.exists():continue
    a=json.loads(p.read_text());b=json.loads(q.read_text())
    x=envelope_summary(a);y=envelope_summary(b)
    comparison={"before":x,"after":y,"totalDelta":delta(x["total"]["median"],y["total"]["median"])}
    if "fixtureSHA256" in a:
        assert a["fixtureSHA256"]==b["fixtureSHA256"],p.name
        for key in ["modelID", "modelRevision", "corpusVersion", "runnerSHA256"]:
            assert a[key] == b[key], (p.name, key)
        comparison["sameNormalizedResults"]=all(i["normalizedFindings"]==j["normalizedFindings"] for i,j in zip(a["records"],b["records"]))
        comparison["sameCoverage"]=x["coverage"]==y["coverage"]
    else:
        comparison["sameFixedScoring"]=all(i["scored"]==j["scored"] and abs(i["deltaSum"]-j["deltaSum"])<1e-9 for i,j in zip(a["records"],b["records"]))
    result["pipeline"][p.name]=comparison
for version in ["before","after"]:
    p=ROOT/version/"accuracy-experiment-summary.json"
    if p.exists():result["accuracy"][version]=json.loads(p.read_text())
(ROOT/"comparison.json").write_text(json.dumps(result,indent=2))
print("Wrote comparison",len(result["pipeline"]),"pipeline envelopes")
