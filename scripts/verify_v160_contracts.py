#!/usr/bin/env python3
"""Check cross-component purchase IDs and the recovered migration manifest."""
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
swift = (root / 'ATHLTH/Subscriptions/SubscriptionStore.swift').read_text()
products = set(re.findall(r'static let (?:monthly|yearly)ProductID = "([^"]+)"', swift))
if len(products) != 2:
    raise SystemExit('Expected monthly and yearly StoreKit products')
for function in ('verify-app-store-transaction', 'app-store-notifications'):
    source = (root / f'supabase/functions/{function}/index.ts').read_text()
    block = re.search(r'const PRODUCT_IDS = new Set\(\[([\s\S]*?)\]\)', source)
    if not block or set(re.findall(r'"([^"]+)"', block[1])) != products:
        raise SystemExit(f'{function} disagrees with StoreKit product IDs')

migrations = root / 'supabase/migrations'
versions = [p.name.split('_', 1)[0] for p in migrations.glob('*.sql')]
if len(versions) != len(set(versions)):
    raise SystemExit('Duplicate migration versions')
manifest = json.loads((root / 'supabase/migration-history.json').read_text())
for item in manifest['migrations']:
    path = migrations / item['file']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit(f'Recovered migration changed or missing: {path.name}')
print(f'Purchase IDs match; {len(versions)} unique migrations; {len(manifest["migrations"])} recovered files verified.')
