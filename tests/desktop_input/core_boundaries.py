from pathlib import Path
import json, math, sys, hashlib, traceback
import argparse, os
parser = argparse.ArgumentParser(description='Shared core boundary contracts; desktop frontend execution is separate')
parser.add_argument('--library', required=True)
parser.add_argument('--model', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
os.environ['GUANYINMA_TEST_LIBRARY'] = str(Path(args.library).resolve())
os.environ['GUANYINMA_TEST_MODEL'] = str(Path(args.model).resolve())
from core_cabi import Session, LIB, MODEL
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
fixture = json.loads(Path(__file__).with_name('cases.json').read_text())
assert hashlib.sha256(MODEL.read_bytes()).hexdigest() == fixture['model_sha256'], 'Model differs from shared case fixture'
contracts = {case['id']: case for case in fixture['cases']}
(out / 'manifest.json').write_text(json.dumps({'model_sha256': fixture['model_sha256'], 'library_sha256': hashlib.sha256(LIB.read_bytes()).hexdigest(), 'cases_sha256': hashlib.sha256(Path(__file__).with_name('cases.json').read_bytes()).hexdigest()}, indent=2) + '\n')
results = []

def run(name, cfg, fn):
    assert name in contracts, name
    s = Session(cfg)
    evidence = []
    try:
        fn(s, evidence)
        r = {'case': name, 'status': 'passed', 'configuration': cfg, 'snapshots': evidence}
    except Exception as e:
        r = {'case': name, 'status': 'failed', 'error': traceback.format_exc(), 'configuration': cfg, 'snapshots': evidence}
    finally:
        s.close()
    (out / (name + '.json')).write_text(json.dumps(r, ensure_ascii=False, indent=2) + '\n')
    results.append({k: v for k, v in r.items() if k != 'snapshots'})
for limit in [10, 20]:

    def check(s, e, limit=limit):
        v = s.type('su3' * limit)
        e.append(v)
        assert len(v['readings']) == limit and s.committed == '' and (v['composition'] == '你' * limit)
        v = s.type('su3')
        e.append(v)
        assert s.committed and len(v['readings']) <= limit and (s.committed + v['composition'] == '你' * (limit + 1))
        v = s.key('return')
        e.append(v)
        assert s.committed == '你' * (limit + 1) and (not v['composition'])
    run(f'B01-COMPOSITION-{limit}-{limit + 1}', {'method': 'smart', 'smart': {'max_completed_syllables': limit}}, check)
for method in ['traditional', 'smart']:
    for keys in ['12345678', '123456789', 'asdfzxcv']:

        def check(s, e, keys=keys, method=method):
            v = s.type('su3')
            v = s.key('down') if method == 'smart' else v
            e.append(v)
            all_candidates = v['candidates']
            size = len(keys)
            pages = math.ceil(len(all_candidates) / size)
            assert v['page_size'] == size and len(v['displayed_candidates']) == size
            v = s.key('page_down')
            e.append(v)
            assert v['page'] == 1 and v['displayed_candidates'] == all_candidates[size:2 * size]
            for _ in range(pages - 2):
                v = s.key('page_down')
            e.append(v)
            assert v['page'] == pages - 1 and v['displayed_candidates'] == all_candidates[(pages - 1) * size:] and (1 <= len(v['displayed_candidates']) <= size)
            v = s.key('page_down')
            e.append(v)
            assert v['page'] == 0
            v = s.key('page_up')
            e.append(v)
            assert v['page'] == pages - 1
            v = s.key('home')
            e.append(v)
            assert v['page'] == 0 and v['highlight'] == 0
            v = s.key('end')
            e.append(v)
            assert v['page'] == pages - 1 and v['highlight'] == len(v['displayed_candidates']) - 1
            v = s.key('home')
            e.append(v)
            assert v['page'] == 0 and v['highlight'] == 0
        cfg = {'method': method, 'smart': {'candidate_selection_keys': keys}} if method == 'smart' else {'method': method, 'traditional_selection_keys': keys}
        run(f'B02-PAGING-{method.upper()}-{keys}', cfg, check)
for enabled in [False, True]:

    def check(s, e, enabled=enabled):
        v = s.type('ab')
        e.append(v)
        assert bool(v['candidates']) == enabled and (not s.committed) and (v['code'] == 'ab')
        if not enabled:
            v = s.key('space')
            e.append(v)
        assert v['candidates'][:2] == ['明', '冐']
        v = s.type('1')
        e.append(v)
        assert s.committed == '明' and (not v['code'])
    run(f'B03-CANGJIE-MAXIMUM-{int(enabled)}', {'method': 'cangjie', 'cangjie': {'maximum_radical_length': 2, 'query_at_maximum': enabled}}, check)

    def realtime(s, e, enabled=enabled):
        v = s.type('a')
        e.append(v)
        assert bool(v['candidates']) == enabled and v['code'] == 'a' and (not s.committed)
    run(f'B05-CANGJIE-REALTIME-{int(enabled)}', {'method': 'cangjie', 'cangjie': {'realtime': enabled, 'clear_on_error': not enabled}}, realtime)
(out / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(results, ensure_ascii=False, indent=2))
sys.exit(any((r['status'] != 'passed' for r in results)))
