#!/bin/bash
# CPU/session gate matching iOS defaults; deliberately not a UIKit/display test.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
swift build -c release --product VieLotusCLI
BIN_DIR="$(swift build -c release --show-bin-path)"
python3 - "$BIN_DIR/VieLotusCLI" "${MOBILE_BENCHMARK_RUNS:-3}" <<'PY'
import datetime,json,pathlib,subprocess,sys
binary=sys.argv[1]
count=int(sys.argv[2])
if count < 1: raise SystemExit('MOBILE_BENCHMARK_RUNS must be positive')
root=pathlib.Path('.build/mobile-benchmark')/datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
root.mkdir(parents=True,exist_ok=False)
rows=[]
for index in range(1,count+1):
    result=subprocess.run([binary,'--stress','--mobile-path','--json'],capture_output=True,text=True)
    (root/f'run-{index}.log').write_text(result.stdout+result.stderr)
    if result.returncode: raise SystemExit(f'Mobile CPU gate failed on run {index}; see {root}')
    payloads=[json.loads(line[len('LATENCY_JSON '):]) for line in result.stdout.splitlines() if line.startswith('LATENCY_JSON ')]
    if len(payloads)!=1: raise SystemExit('Missing/duplicate mobile latency payload')
    row=payloads[0]
    if not (row['profile']=='senFlex' and row['inline_bilingual'] is True and row['provider']=='local-mobile' and row['host_ui_measured'] is False and row['output_verified'] is True):
        raise SystemExit('Wrong configuration or reconstructed output mismatch')
    rows.append(row)
    print(f"Run {index}: Telex p99={row['telex_p99']:.3f}us; mixed p99={row['mixed_p99']:.3f}us; kps={row['avg_kps']:.0f}",flush=True)
worst={key:max(row[key] for row in rows) for key in ['telex_p99','vni_p99','mixed_p99']}
worst['avg_kps']=min(row['avg_kps'] for row in rows)
for key,ceiling in [('telex_p99',500),('vni_p99',300),('mixed_p99',700)]:
    if worst[key]>ceiling: raise SystemExit(f'{key} exceeds {ceiling}us')
if worst['avg_kps']<25000: raise SystemExit('Mobile core throughput below 25000 KPS')
(root/'summary.json').write_text(json.dumps({'configuration':'mobile-equivalent core only','runs':rows,'worst':worst},indent=2))
print('MOBILE_CORE_GATE_PASS '+json.dumps(worst,sort_keys=True))
print(f'Host/UI/display NOT MEASURED. Evidence: {root}')
PY
