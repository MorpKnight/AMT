from pathlib import Path
import os,sys,subprocess,json,time,hashlib
folder=Path(os.environ.get('AMT_EXPERIMENT_DIR', '/private/tmp/amt-accuracy-fix-task')); version=sys.argv[1]
root=folder/'baseline' if version=='before' else Path(os.environ.get('AMT_REPOSITORY', '/Users/giovan/Programming/apple/AMT'))
dd=folder/'derived-baseline' if version=='before' else folder/'derived-after'
out=folder/version;out.mkdir(exist_ok=True)
base=['xcodebuild','-project','AMT.xcodeproj','-scheme','AMT','-configuration','Debug','-destination','platform=macOS,arch=arm64','-derivedDataPath',str(dd),'-clonedSourcePackagesDirPath',os.environ.get('AMT_SOURCE_PACKAGES', '/tmp/amt-backend-study-tests.qIx3rg/SourcePackages'),'-disableAutomaticPackageResolution','-parallel-testing-enabled','NO']
common=os.environ.copy();common['TEST_RUNNER_HF_HUB_CACHE']=os.environ.get('HF_HUB_CACHE', '/private/tmp/amt-flow-fix-task/hf-hub')
common['TEST_RUNNER_AMT_FLOW_BUILD']=version;common['TEST_RUNNER_AMT_FLOW_RUNNER_SHA']=hashlib.sha256((folder/'AIConnectorAccuracyMatrixTests.swift').read_bytes()).hexdigest()

def run(name,test,extra):
 marker=out/(name+'.done.json')
 if marker.exists():print('Completed previously',name,flush=True);return
 env=common.copy();env.update({'TEST_RUNNER_'+k:v for k,v in extra.items()})
 result=out/(name+'-'+str(int(time.time()))+'.xcresult')
 with (out/(name+'.log')).open('w') as log:
  code=subprocess.call(base+['-only-testing:'+test,'-resultBundlePath',str(result),'test-without-building','CODE_SIGNING_ALLOWED=NO'],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
 print(name,'EXIT',code,flush=True)
 if code:raise SystemExit(code)
 marker.write_text(json.dumps({'exit':code,'xcresult':str(result),'finishedAt':time.time()}))

run('accuracy-matrix','AMTTests/AIConnectorAccuracyMatrixTests/testFrozenAccuracyMatrix',{'AMT_RUN_ACCURACY_MATRIX':'1','AMT_ACCURACY_MATRIX_FIXTURES':str(folder/'frozen-fixtures.json'),'AMT_ACCURACY_MATRIX_OUTPUT':str(out/'matrix')})
records=list((out/'matrix').glob('*-warm-*.json'))+list((out/'matrix').glob('*-cached-*.json'))
assert len(records)==3258,len(records)
for fixture in ['local-12','local-60','local-180','terminology','definitions','mixed','tatakata','long-clauses','long-source','hard-negative']:
 for phase in ['warm','cached']:
  run(f'pipeline-{fixture}-{phase}','AMTTests/AIConnectorFlowBenchmarkTests/testFrozenProductionFlow',{'AMT_RUN_FLOW_BENCHMARK':'1','AMT_FLOW_OUTPUT':str(out/'pipeline'),'AMT_FLOW_PHASE':phase,'AMT_FLOW_FIXTURE':fixture})
for fixture in ['local-12','definitions','long-clauses']:
 run(f'pipeline-{fixture}-incremental','AMTTests/AIConnectorFlowBenchmarkTests/testFrozenProductionFlow',{'AMT_RUN_FLOW_BENCHMARK':'1','AMT_FLOW_OUTPUT':str(out/'pipeline'),'AMT_FLOW_PHASE':'incremental','AMT_FLOW_FIXTURE':fixture})
for phase in ['warm','cached']:
 run('fixed-scoring-'+phase,'AMTTests/AIConnectorResourceScoringBenchmarkTests/testFrozenTataKataScores',{'AMT_RUN_RESOURCE_BENCHMARK':'1','AMT_FLOW_OUTPUT':str(out/'pipeline'),'AMT_FLOW_PHASE':phase})
manifest={str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*.json'))}
(out/'completed-manifest.json').write_text(json.dumps({'measuredAccuracyRecords':len(records),'files':manifest},indent=2))
print('COMPLETE',version,len(records),flush=True)
