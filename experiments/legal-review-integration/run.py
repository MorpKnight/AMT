"""Run the opt-in application benchmark; all outputs stay outside the repository."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, time

parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['build', 'offline', 'release', 'warm', 'cached', 'history', 'incremental'])
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--packages', type=Path, required=True)
parser.add_argument('--hub', type=Path, required=True)
parser.add_argument('--repeats', type=int)
a = parser.parse_args()
source = Path(__file__).resolve().parent
repo, output = a.repo.resolve(), a.output.resolve()
assert str(output).startswith('/private/tmp/'), 'Use a new /private/tmp/ output directory.'
output.mkdir(parents=True, exist_ok=True)
files = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
         for top in ['AMT', 'AMTTests'] for p in (repo/top).rglob('*') if p.is_file()}
manifest = output/'source-manifest.json'
if manifest.exists():
    assert json.loads(manifest.read_text())['files'] == files, 'Source drift; use a new output root.'
else:
    manifest.write_text(json.dumps({'files': files, 'labels': 'pending', 'createdAt': time.time()}, indent=2)+'\n')
status = output/(a.action+'.status.json')
assert not status.exists(), 'This action already has artifacts; use a new output root to repeat.'
env = {k: v for k,v in os.environ.items() if not k.startswith(('AMT_', 'TEST_RUNNER_AMT_'))}
env['TEST_RUNNER_HF_HUB_CACHE'] = str(a.hub.resolve())
command = ['xcodebuild', '-project', 'AMT.xcodeproj', '-scheme', 'AMT', '-configuration',
           'Release' if a.action == 'release' else 'Debug', '-destination', 'platform=macOS,arch=arm64',
           '-derivedDataPath', str(output/'derived'), '-clonedSourcePackagesDirPath', str(a.packages.resolve()),
           '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO',
           'CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=YES', 'ARCHS=arm64']
if a.action == 'build':
    command += ['build-for-testing']
elif a.action == 'release':
    command += ['build']
else:
    if a.action in ['warm', 'cached', 'history']:
        fixture = source/('fixtures-history.json' if a.action == 'history' else 'fixtures-primary.json')
        # XCTest accepts only external synthetic fixture paths.
        target = output/fixture.name
        if not target.exists(): target.write_bytes(fixture.read_bytes())
        assert target.read_bytes() == fixture.read_bytes()
        settings = {'AMT_RUN_INTEGRATED_REVIEW': '1', 'AMT_INTEGRATED_REVIEW_FIXTURES': str(target),
                    'AMT_INTEGRATED_REVIEW_OUTPUT': str(output/'records'/('history' if a.action == 'history' else 'primary')),
                    'AMT_INTEGRATED_REVIEW_PHASE': 'cached' if a.action == 'cached' else 'warm',
                    'AMT_INTEGRATED_REVIEW_REPEATS': str(a.repeats or (1 if a.action == 'history' else 3))}
        env.update({'TEST_RUNNER_'+k:v for k,v in settings.items()})
        command += ['-only-testing:AMTTests/LegalReviewBackendBenchmarkTests/testIntegratedBackendMatrix']
    elif a.action == 'incremental':
        env.update(TEST_RUNNER_AMT_RUN_INTEGRATED_INCREMENTAL='1',
                   TEST_RUNNER_AMT_INTEGRATED_REVIEW_OUTPUT=str(output/'records/incremental'))
        command += ['-only-testing:AMTTests/LegalReviewBackendBenchmarkTests/testIntegratedIncrementalFreshPairs']
    command += ['test-without-building', '-resultBundlePath', str(output/(a.action+'.xcresult'))]
start = time.time()
with (output/(a.action+'.log')).open('w') as log:
    code = subprocess.call(command, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
status.write_text(json.dumps({'exit': code, 'seconds': time.time()-start, 'action': a.action}, indent=2)+'\n')
print(status, 'exit', code)
raise SystemExit(code)
