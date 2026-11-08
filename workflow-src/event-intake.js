const initial=$('Investigation portal').first().json;
const x={...initial,...$input.first().json,action:initial.action,user:initial.user};
const u=initial.user;
x.actor=u?.id?{id:String(u.id),name:[u.firstName,u.lastName].filter(Boolean).join(' ')||String(u.email||u.id),source:'n8n_authenticated_user'}:null;
if(!['submit','report','case','events','worklist'].includes(x.action))throw new Error('Unsupported portal action');
if(x.action==='submit'&&!x.ip)throw new Error('Enter a public IP');
if(['report','case'].includes(x.action)&&!x.case_id)throw new Error('Enter the investigation ID');
if(['events','worklist','case'].includes(x.action)&&!x.actor)throw new Error('Sign in to the production portal to perform this action.');
if(x.action==='events'){
 let raw=String(x.events_json||'');
 const binary=$input.first().binary||{};
 const key=Object.keys(binary)[0];
 if(key){const buffer=await this.helpers.getBinaryDataBuffer(0,key);if(buffer.length>262144)throw new Error('File exceeds 256 KiB');if(raw.trim())throw new Error('Use either a file or pasted JSON, not both');raw=buffer.toString('utf8');}
 if(!raw.trim())throw new Error('Upload a JSON event file or paste its contents');
 if(raw.length>262144)throw new Error('Import too large');
 let parsed;try{parsed=JSON.parse(raw)}catch{throw new Error('Invalid JSON event file')}
 if(!parsed||Array.isArray(parsed)||parsed.schema_version!=='1.0'||!Array.isArray(parsed.events)||parsed.events.length<1||parsed.events.length>100)throw new Error('Expected schema_version 1.0 and 1–100 events');
 x.event_payload={schema_version:'1.0',events:parsed.events,demo:x.mode==='Synthetic demo',asset_criticality:x.asset_criticality||'unknown',actor:x.actor};
}
if(x.action==='case'){
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(x.assessment_id||'')))throw new Error('Enter the assessment ID shown in the report');
 const labels={'Under review':'under_review','Confirmed malicious activity':'confirmed_malicious','Confirmed benign activity':'confirmed_benign','Insufficient evidence':'insufficient_evidence','Duplicate investigation':'duplicate'};
 x.disposition=labels[x.disposition]||x.disposition;
 if(!Object.values(labels).includes(x.disposition))throw new Error('Choose an analyst disposition');
 if(x.status==='closed'&&x.disposition==='under_review')throw new Error('Choose a final disposition before closing the case');
 if(String(x.note||'').trim().length<3)throw new Error('Explain your analyst decision');
}
return [{json:x}];
