#!/usr/bin/env python3
"""Replay migrations and SQL suites in a disposable Docker PostgreSQL container."""
import subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
name='ipintel-acceptance-'+uuid.uuid4().hex[:10]
def run(args,**kw):return subprocess.run(args,check=True,text=True,**kw)
def sql(value):return run(['sudo','-n','docker','exec','-i',name,'psql','-U','postgres','-v','ON_ERROR_STOP=1'],input=value,capture_output=True).stdout
try:
 run(['sudo','-n','docker','run','-d','--name',name,'--network','none','-e','POSTGRES_HOST_AUTH_METHOD=trust','postgres:17-alpine'],capture_output=True)
 import time
 for _ in range(40):
  if subprocess.run(['sudo','-n','docker','exec',name,'pg_isready','-U','postgres'],capture_output=True).returncode==0:break
  time.sleep(.25)
 sql('create role anon;create role authenticated;create role service_role;')
 for path in sorted((ROOT/'supabase/migrations').glob('*.sql')):
  sql(path.read_text());print('PASS migration',path.name)
 for path in sorted((ROOT/'tests').glob('*.sql')):
  print(sql(path.read_text()).strip());print('PASS suite',path.name)
except subprocess.CalledProcessError as error:
 print(error.stderr or str(error));raise SystemExit(1)
finally:
 subprocess.run(['sudo','-n','docker','rm','-f',name],capture_output=True)
