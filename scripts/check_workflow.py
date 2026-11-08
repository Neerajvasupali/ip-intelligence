#!/usr/bin/env python3
import json,subprocess
from pathlib import Path
r=Path(__file__).resolve().parents[1];w=json.loads((r/'workflows/ip-intelligence-unified.sanitized.json').read_text());names={n['name'] for n in w['nodes']};assert len(names)==len(w['nodes']);assert not w['active'];assert all('credentials' not in n and 'webhookId' not in n for n in w['nodes'])
for source,types in w['connections'].items():
 assert source in names
 for outputs in types.values():
  for edges in outputs:
   for edge in edges:assert edge['node'] in names
route=w['connections']['Route system action']['main'];assert route[9][0]['node']=='events - Preview import';assert route[10][0]['node']=='worklist - Read investigations';assert route[11][0]['node']=='Reject unsupported command'
js='''const vm=require('node:vm'),assert=require('node:assert/strict');const w=JSON.parse(require('node:fs').readFileSync(0,'utf8'));for(const n of w.nodes){if(n.type==='n8n-nodes-base.code')new Function('return async function(){'+n.parameters.jsCode+'}');}const form=w.nodes.find(n=>n.name==='Collect investigation details');const expression=form.parameters.jsonOutput.slice(3,-2).trim();for(const action of ['events','worklist','submit','report','case']){const result=vm.runInNewContext(expression,{$json:{action}});assert(Array.isArray(JSON.parse(result)));}console.log('PASS all Code-node syntax and five form expressions');'''
p=subprocess.run(['sudo','-n','docker','exec','-i','n8n-n8n-1','node','-e',js],input=json.dumps(w),text=True);assert p.returncode==0;print('PASS topology, routes and sanitized export')
