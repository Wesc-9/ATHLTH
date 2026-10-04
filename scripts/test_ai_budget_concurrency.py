#!/usr/bin/env python3
"""Verify atomic AI budgets against a disposable local database only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--psql', help='Native psql binary for a loopback test database')
parser.add_argument('--port', default='54322')
args = parser.parse_args()
command = ([args.psql, '-h', '127.0.0.1', '-p', args.port, '-U', 'postgres', '-d', 'postgres']
           if args.psql else ['docker', 'exec', 'supabase_db_ATHLTH-1.6.0', 'psql', '-U', 'postgres', '-d', 'postgres'])

def query(sql):
    return subprocess.check_output(command + ['-v', 'ON_ERROR_STOP=1', '-Atqc', sql], text=True).strip()

user = '00000000-0000-0000-0000-000000000099'
query(f"insert into auth.users(id) values ('{user}')")
try:
    # Keep the burst away from a fixed minute boundary.
    while datetime.now(timezone.utc).second >= 50:
        time.sleep(1)
    with ThreadPoolExecutor(max_workers=20) as pool:
        results = list(pool.map(lambda _: query(
            f"set role service_role; select allowed from public.consume_ai_request_budget('{user}','recovery-sense')"
        ), range(20)))
    if results.count('t') != 10 or results.count('f') != 10:
        raise SystemExit(f'Concurrent budget limit failed: {results}')
    if query(f"select day_units from private.ai_request_budgets where user_id='{user}'") != '10':
        raise SystemExit('Concurrent requests corrupted the usage count')
    print('20 concurrent requests: exactly 10 allowed, 10 denied, 10 units charged.')
finally:
    query(f"delete from auth.users where id='{user}'")
