#!/usr/bin/env python3
"""Run an isolated synthetic investigation. No credentials or provider requests."""
import json,subprocess,time,uuid,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'.preview/demo');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
name='ipintel-demo-'+uuid.uuid4().hex[:8]
def sql(value):
 r=subprocess.run(['sudo','-n','docker','exec','-i',name,'psql','-U','postgres','-At','-v','ON_ERROR_STOP=1'],input=value,text=True,capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
def literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"
try:
 subprocess.run(['sudo','-n','docker','run','-d','--name',name,'--network','none','-e','POSTGRES_HOST_AUTH_METHOD=trust','postgres:17-alpine'],check=True,capture_output=True)
 for _ in range(40):
  if subprocess.run(['sudo','-n','docker','exec',name,'pg_isready','-U','postgres'],capture_output=True).returncode==0:break
  time.sleep(.25)
 sql('create role anon;create role authenticated;create role service_role;')
 for path in sorted((ROOT/'supabase/migrations').glob('*.sql')):sql(path.read_text())
 payload=json.loads((ROOT/'demo/repeated_failures.json').read_text());payload.update(demo=True,actor={'id':'synthetic-reviewer','name':'Synthetic reviewer','source':'n8n_authenticated_user'})
 imported=json.loads(sql("select public.ipintel_api('events_ingest',"+literal(payload)+');'));cid=imported['case_ids'][0]
 replay=json.loads(sql("select public.ipintel_api('events_ingest',"+literal(payload)+');'));assert replay['inserted']==0 and replay['duplicates']==3
 assert sql('select count(*) from ipintel.jobs;')=='0'
 report=json.loads(sql("select public.ipintel_api('report',"+literal({'case_id':cid})+');'));assert report['event_context']['priority']=='medium'
 review={'case_id':cid,'assessment_id':report['assessment_id'],'status':'closed','disposition':'insufficient_evidence','note':'Synthetic exercise: failed logins alone do not establish compromise. No live reputation evidence was requested.','actor':payload['actor']}
 sql("select public.ipintel_api('case_update',"+literal(review)+');')
 report=json.loads(sql("select public.ipintel_api('report',"+literal({'case_id':cid})+');'));assert len(report['analyst_reviews'])==1
 (a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 w=json.loads((ROOT/'workflows/ip-intelligence-unified.sanitized.json').read_text());code=next(n['parameters']['jsCode'] for n in w['nodes'] if n['name']=='report - Render result')
 js="const fs=require('node:fs');const x=JSON.parse(fs.readFileSync(0,'utf8'));const fn=new Function('$input',x.code);const result=fn({first:()=>({json:x.report})});process.stdout.write(result[0].json.html);"
 rendered=subprocess.run(['sudo','-n','docker','exec','-i','n8n-n8n-1','node','-e',js],input=json.dumps({'code':code,'report':report}),text=True,capture_output=True,check=True)
 (a.output/'report.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Synthetic investigation demo</title>'+rendered.stdout+'</html>')
 print('PASS: fresh schema → 3 events → 1 case → 3 suppressed replay events → medium priority → saved assessment → attributed explained closure')
 print('Provider requests: 0. Demo actor is a fixture, not a browser-authentication test.')
 print('Report:',a.output/'report.html')
finally:subprocess.run(['sudo','-n','docker','rm','-f',name],capture_output=True)
