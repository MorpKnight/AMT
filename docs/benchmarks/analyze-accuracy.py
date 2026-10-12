#!/usr/bin/env python3
"""Summarize pending synthetic accuracy reports without approving their labels."""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path


def read(directory, name):
    return json.loads((directory / name).read_text())


def corrections(records, fixtures, categories):
    tp = fp = fn = 0
    misses = []
    for record in records:
        fixture = fixtures[record['fixtureID']]
        if fixture['category'] not in categories:
            continue
        expected = [item for item in fixture['expected']['findings']
                    if item['category'] in categories and not item['readOnly']]
        remaining = [item for item in record['output']['findings']
                     if item['category'] in categories and not item['readOnly']]
        for wanted in expected:
            index = next((i for i, actual in enumerate(remaining)
                          if actual['anchorValid'] and all(
                              actual.get(key) == wanted.get(key)
                              for key in ('category', 'status', 'original', 'replacement', 'occurrence'))), None)
            if index is None:
                fn += 1
                misses.append({'fixtureID': fixture['id'], 'expected': wanted})
            else:
                tp += 1
                remaining.pop(index)
        fp += len(remaining)
    return {'tp': tp, 'fp': fp, 'fn': fn,
            'precision': tp / (tp + fp) if tp + fp else None,
            'recall': tp / (tp + fn) if tp + fn else None,
            'f1': 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else None,
            'misses': misses}


def incomplete_coverage(record):
    observation = record.get('observation') or {}
    return any(value in ('failed', 'tooLong', 'cancelled')
               for segment in observation.get('segments', [])
               for value in segment.get('stageCoverage', {}).values()) or any(
                   value.get('omittedRanges') for value in observation.get('inputCoverage', {}).values())


def main(directory):
    fixture_list = read(directory, 'fixtures.json')
    fixtures = {item['id']: item for item in fixture_list}
    records = read(directory, 'records.json')
    modes = ('deterministic', 'hybrid', 'modelOnly')
    expected_keys = {(mode, fixture) for mode in modes for fixture in fixtures}
    actual_keys = [(record['mode'], record['fixtureID']) for record in records]
    if set(actual_keys) != expected_keys or len(actual_keys) != len(expected_keys):
        raise ValueError('Incomplete or duplicated matrix; do not summarize partial runs as complete.')
    summary = {'fixtureCount': len(fixtures), 'runCount': len(records),
               'reviewStatus': dict(Counter(item['reviewStatus'] for item in fixture_list)),
               'scope': 'Pending synthetic experiment; no human approvals added.',
               'fixtureFileSHA256': hashlib.sha256((directory / 'fixtures.json').read_bytes()).hexdigest(),
               'gateStatus': read(directory, 'reviewed-quality-gate.json')['overallStatus'], 'modes': {}}
    for mode in modes:
        subset = [record for record in records if record['mode'] == mode]
        no_change = [record for record in subset if fixtures[record['fixtureID']]['expected']['noChange']]
        summary['modes'][mode] = {
            'spelling': corrections(subset, fixtures, {'spelling'}),
            'grammar': corrections(subset, fixtures, {'grammar'}),
            'localCorrections': corrections(subset, fixtures, {'spelling', 'grammar'}),
            'novelSpelling': corrections([record for record in subset
                                         if record['fixtureID'].startswith('backend46-spelling-')],
                                        fixtures, {'spelling'}),
            'noChangeCases': len(no_change),
            'noChangeWithActionable': sum(any(not item['readOnly'] for item in record['output']['findings'])
                                         for record in no_change),
            'noChangeWithRawObservedFinding': sum(bool(record['output']['findings']) for record in no_change),
            'invalidMappedAnchors': sum(record['invalidMappedAnchors'] for record in subset),
            'invalidActionableSources': sum(record['invalidActionableSources'] for record in subset),
            'coverageIncompleteRuns': sum(incomplete_coverage(record) for record in subset),
            'totalPipelineSeconds': sum(record['output']['totalDuration'] for record in subset)}
    controls = {item['id']: item for item in read(directory, 'definition-controls.json')}
    control_records = read(directory, 'definition-control-records.json')
    if len(controls) != 18 or len(control_records) != 36 or len({(r['mode'], r['id']) for r in control_records}) != 36:
        raise ValueError('Incomplete or duplicated definition controls.')
    summary['definitionControls'] = {}
    for mode in ('deterministic', 'hybrid'):
        summary['definitionControls'][mode] = {}
        for kind in ('exact', 'negated', 'mention'):
            subset = [record for record in control_records
                      if record['mode'] == mode and controls[record['id']]['kind'] == kind]
            summary['definitionControls'][mode][kind] = {
                'cases': len(subset),
                'matchCases': sum(any(item['alignment'] == 'MATCH' for item in record['assessments'])
                                  for record in subset),
                'needsReviewCases': sum(any(item['alignment'] == 'NEEDS_REVIEW' for item in record['assessments'])
                                        for record in subset),
                'noAssessmentCases': sum(not record['assessments'] for record in subset),
                'reasonCounts': dict(Counter(item['reason'] for record in subset for item in record['assessments']))}
    repeats = read(directory, 'spelling-repeat-records.json')
    if len(repeats) != 18 or len({(r['fixtureID'], r['iteration']) for r in repeats}) != 18:
        raise ValueError('Incomplete or duplicated spelling repeats.')
    summary['spellingRepeats'] = {'runs': len(repeats),
        'withActionable': sum(any(not item['readOnly'] for item in record['output']['findings']) for record in repeats)}
    summary['validatorDiagnostic'] = read(directory, 'validator-diagnostic.json')
    summary['spellingDiagnostics'] = read(directory, 'spelling-diagnostics.json')
    (directory / 'accuracy-summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({mode: value['localCorrections'] for mode, value in summary['modes'].items()}, indent=2))


if __name__ == '__main__':
    main(Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/amt-accuracy-task'))
