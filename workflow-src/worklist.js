const d=$input.first().json;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let html='<main style="max-width:1100px;margin:24px auto;font-family:system-ui;line-height:1.7"><h1>Investigation worklist</h1><p>Latest 50 matching investigations. Synthetic cases are labeled DEMO. Copy an investigation ID and choose report to inspect evidence.</p><div style="overflow:auto"><table style="width:100%;text-align:left"><tr><th>ID / IP</th><th>Status / Owner</th><th>Asset / Events</th><th>Priority</th></tr>';
for(const c of d.cases||[]){const x=c.context||{};html+='<tr><td style="padding:12px"><code>'+esc(c.id)+'</code><br>'+esc(c.ip)+(x.demo?' · DEMO':'')+'</td><td>'+esc(c.status)+'<br>'+esc(c.owner_name||'Unassigned')+'</td><td>'+esc(x.asset_id||'IP-only')+'<br>'+esc(x.total||0)+'</td><td>'+esc(x.priority||'unassessed')+'</td></tr>';}
html+='</table></div><p><a href="/form/ip-intelligence">Return to workspace</a></p></main>';
return [{json:{...d,html}}];
