#!/usr/bin/env python3
"""Execute workflow Code nodes in Node's VM inside the existing n8n container."""
import json,subprocess
from pathlib import Path
r=Path(__file__).resolve().parents[1]
nodes={n['name']:n for n in json.loads((r/'workflows/ip-intelligence-unified.sanitized.json').read_text())['nodes']}
checks={'intake':(r/'workflow-src/event-intake.js').read_text(),'result':(r/'workflow-src/event-result.js').read_text(),'worklist':(r/'workflow-src/worklist.js').read_text()}
js='''const vm=require('node:vm');const assert=require('node:assert/strict');const sources=JSON.parse(require('node:fs').readFileSync(0,'utf8'));async function run(code,input,initial={action:'events',user:{id:'signed-in-user',email:'analyst@example.invalid'}}){return await vm.runInNewContext('(async function(){'+code+'}).call(ctx)',{$input:{first:()=>({json:input})},$:()=>({first:()=>({json:initial})}),ctx:{},console});}
(async()=>{const payload={schema_version:'1.0',events:[{source:'demo',event_id:'one'}]};let r=await run(sources.intake,{events_json:JSON.stringify(payload),mode:'Synthetic demo',actor:{id:'forged'}});assert.equal(r[0].json.actor.id,'signed-in-user');assert.equal(r[0].json.event_payload.demo,true);await assert.rejects(run(sources.intake,{events_json:'bad'}));await assert.rejects(run(sources.intake,{events_json:JSON.stringify(payload)},{action:'events'}));r=await run(sources.result,{rows:[{index:0,status:'rejected',errors:['<script>bad</script>']}],demo:true});assert(!r[0].json.html.includes('<script>'));r=await run(sources.worklist,{cases:[{id:'one',ip:'<script>',status:'open',context:{total:3,demo:true}}]});assert(!r[0].json.html.includes('<script>'));console.log('PASS intake actor provenance, missing authentication, malformed JSON, result and worklist escaping');})().catch(e=>{console.error(e);process.exit(1)});'''
p=subprocess.run(['sudo','-n','docker','exec','-i','n8n-n8n-1','node','-e',js],input=json.dumps(checks),text=True);raise SystemExit(p.returncode)
