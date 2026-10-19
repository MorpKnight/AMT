from pathlib import Path
import argparse,subprocess,os,hashlib,json,time
parser=argparse.ArgumentParser(description="Run frozen opt-in backend benchmarks after build-for-testing.")
parser.add_argument("--label", choices=["before","after"], required=True)
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--artifacts", type=Path, required=True)
parser.add_argument("--packages", type=Path, required=True)
parser.add_argument("--baseline-revision", required=True)
parser.add_argument("--hf-cache", type=Path, required=True)
args=parser.parse_args()
base=args.artifacts.resolve(); label=args.label; root=args.root.resolve()
base.mkdir(parents=True,exist_ok=True)
assert str(base).startswith("/private/tmp/"), "Artifacts must be outside the repository in /private/tmp/."

reports=base/'reports'/label; reports.mkdir(parents=True,exist_ok=True)
h=hashlib.sha256()
for p in sorted(list((root/'AMT').rglob('*.swift'))+list((root/'AMTTests').rglob('*.swift'))): h.update(str(p.relative_to(root)).encode());h.update(p.read_bytes())
identity=label+':'+args.baseline_revision+':'+h.hexdigest()
manifest={'sourceSHA256':h.hexdigest(),'buildIdentity':identity,'harnessSHA256':hashlib.sha256((root/'AMTTests/AIConnectorFlowBenchmarkTests.swift').read_bytes()).hexdigest(),'fixtureSHA256':hashlib.sha256((root/'AMT/Features/AIConnector/Services/AIConnectorBackendEvaluationFixtures.swift').read_bytes()).hexdigest()}
(base/(label+'-manifest.json')).write_text(json.dumps(manifest,indent=2))
def run(fixture,phase,target='AMTTests/AIConnectorFlowBenchmarkTests/testFrozenProductionFlow',stem=None):
 stem=stem or fixture+'-'+phase; output=reports/(stem+'.json')
 if output.exists():
  assert json.load(open(output))['buildIdentity']==identity
  print('EXISTING',label,stem,flush=True);return
 environment=os.environ.copy()
 for k,v in {'HF_HUB_CACHE':str(args.hf_cache.resolve()),'AMT_RUN_FLOW_BENCHMARK':'1','AMT_RUN_RESOURCE_BENCHMARK':'1','AMT_FLOW_PHASE':phase,'AMT_FLOW_FIXTURE':fixture,'AMT_FLOW_OUTPUT':str(reports),'AMT_FLOW_RUNNER_SHA':manifest['harnessSHA256'],'AMT_FLOW_BUILD':identity}.items(): environment['TEST_RUNNER_'+k]=v
 stamp=str(time.time_ns()); log=base/(label+'-'+stem+'-'+stamp+'.log');result=base/(label+'-'+stem+'-'+stamp+'.xcresult')
 args=['xcodebuild','-project','AMT.xcodeproj','-scheme','AMT','-configuration','Debug','-destination','platform=macOS,arch=arm64','-derivedDataPath',str(base/('derived-'+label)),'-clonedSourcePackagesDirPath',str(args.packages.resolve()),'-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','-only-testing:'+target,'-resultBundlePath',str(result),'test-without-building','CODE_SIGNING_ALLOWED=NO']
 print('START',label,stem,flush=True); start=time.monotonic()
 with log.open('w') as f: code=subprocess.call(args,cwd=root,env=environment,stdout=f,stderr=subprocess.STDOUT)
 print('END',label,stem,code,round(time.monotonic()-start,2),flush=True)
 if code or not output.exists():raise RuntimeError(str(log))
fixtures=['local-12','local-60','local-180','terminology','definitions','mixed','tatakata','long-clauses','long-source','hard-negative']
for phase in ['warm','cached','control']:
 for f in (fixtures[:6] if phase=='control' else fixtures):run(f,phase)
for f in ['local-12','definitions','long-clauses']:run(f,'incremental')
for phase in ['warm','cached']:run('tatakata',phase,'AMTTests/AIConnectorResourceScoringBenchmarkTests/testFrozenTataKataScores','fixed-scoring-'+phase)
run('local-12','quality')
run('local-12','stress')
print('BENCHMARK COMPLETE',label,flush=True)
