'use strict';
const $ = (selector) => document.querySelector(selector);
const all = (selector) => [...document.querySelectorAll(selector)];
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
let paused = reduced.matches;
function setMotion(value) { paused = value; document.documentElement.classList.toggle('paused', paused); $('#motion').textContent = paused ? 'Resume motion' : 'Pause motion'; $('#motion').setAttribute('aria-pressed', String(paused)); }
setMotion(paused);
$('#motion').addEventListener('click', () => setMotion(!paused));
reduced.addEventListener('change', event => setMotion(event.matches));
try { const saved = localStorage.getItem('ipintel-docs-theme'); if (saved === 'light' || saved === 'dark') document.documentElement.dataset.theme = saved; } catch (_) { /* Local storage may be unavailable in file mode. */ }
$('#theme').addEventListener('click', () => { const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; document.documentElement.dataset.theme = next; try { localStorage.setItem('ipintel-docs-theme', next); } catch (_) {} });
$('#menu').addEventListener('click', () => { const open = document.body.classList.toggle('menu-open'); $('#menu').setAttribute('aria-expanded', String(open)); });
all('nav a').forEach(link => link.addEventListener('click', () => { document.body.classList.remove('menu-open'); $('#menu').setAttribute('aria-expanded', 'false'); }));
const stages = [
  ['Accept once. Investigate asynchronously.', 'Validate a public IP, create a case and enqueue provider jobs. A request key supports idempotent submission. Return a case ID without waiting for every external API.'],
  ['Claim carefully. Reuse recent evidence.', 'The scheduled worker claims one eligible job. Database locks, provider budgets, leases and claim-token fencing bound concurrent work. Recent cached evidence avoids another external request.'],
  ['Save the evidence behind the conclusion.', 'Normalize provider outcomes, expose observation dates and classify using ordered rules. Save an assessment snapshot; reuse it when evidence and rule version have not changed.'],
  ['Require an attributed explanation.', 'The original authenticated n8n user supplies reviewer identity. A saved assessment, final disposition and explanation are required for closure. No automated blocking follows a reputation signal.']
];
const tabs = all('[data-stage]');
function stage(index, focus = false) { tabs.forEach((tab, i) => { tab.setAttribute('aria-selected', String(i === index)); tab.tabIndex = i === index ? 0 : -1; }); $('#stage-title').textContent = stages[index][0]; $('#stage-copy').textContent = stages[index][1]; $('#stage-detail').setAttribute('aria-labelledby', `step-${index}`); if (focus) tabs[index].focus(); }
tabs.forEach((tab, i) => { tab.addEventListener('click', () => stage(i)); tab.addEventListener('keydown', event => { let next; if(event.key === 'ArrowRight') next = (i + 1) % tabs.length; if(event.key === 'ArrowLeft') next = (i + tabs.length - 1) % tabs.length; if(event.key === 'Home') next = 0; if(event.key === 'End') next = tabs.length - 1; if(next !== undefined) {event.preventDefault();stage(next, true);} }); });
const scenarios = {
 conflict: ['conflicting_evidence', 'VirusTotal has one flag while AbuseIPDB is available with zero confidence. The disagreement needs investigation; it does not establish maliciousness.', ['1', '0', 'Complete']],
 corroborated: ['cross_source_signals', 'Elevated AbuseIPDB confidence with reports and multiple VirusTotal flags meet the first ordered rule. Review observation dates and event context before deciding a disposition.', ['4', '85', 'Complete']],
 partial: ['inconclusive', 'VirusTotal is unavailable after its job finishes. With no positive signal and incomplete reputation coverage, the system keeps uncertainty visible. IPinfo context cannot fill this gap.', ['Unavailable', '0', 'Partial']],
 old: ['outdated_evidence', 'Both reputation providers returned without positive signals, but a relevant underlying observation is older than 30 days. Recent retrieval alone does not establish fresh evidence.', ['0', '0', 'Complete · stale']]
};
all('[data-scenario]').forEach(button => button.addEventListener('click', () => { const chosen = scenarios[button.dataset.scenario]; all('[data-scenario]').forEach(other => other.setAttribute('aria-pressed', String(other === button))); $('#verdict').textContent = chosen[0]; $('#scenario-copy').textContent = chosen[1]; all('#scenario-values dd').forEach((value, index) => {value.textContent = chosen[2][index];}); }));
const links = all('nav a');
$('#search').addEventListener('input', event => { const query = event.target.value.trim().toLowerCase(); let matches = 0; links.forEach(link => { const section = $(link.hash); const match = !query || section.textContent.toLowerCase().includes(query); link.hidden = !match; if(match) matches++; }); $('#search-status').textContent = query ? `${matches} matching section${matches === 1 ? '' : 's'}` : ''; });
$('#search').addEventListener('keydown', event => { if(event.key === 'Enter') { const link = links.find(item => !item.hidden); if(link) {link.click(); $(link.hash).scrollIntoView();} } });
document.addEventListener('keydown', event => { const typing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName); if((event.key === '/' && !typing) || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k')) { event.preventDefault(); if(innerWidth <= 760) {document.body.classList.add('menu-open');$('#menu').setAttribute('aria-expanded','true');} $('#search').focus(); } if(event.key === 'Escape') {$('#search').value = '';$('#search').dispatchEvent(new Event('input'));document.body.classList.remove('menu-open');$('#menu').setAttribute('aria-expanded','false');$('#search').blur();} });
if('IntersectionObserver' in window) { const observer = new IntersectionObserver(entries => { const entry = entries.filter(item => item.isIntersecting).sort((a,b) => b.intersectionRatio - a.intersectionRatio)[0]; if(entry) links.forEach(link => { const active = link.hash === `#${entry.target.id}`; link.classList.toggle('active', active); if(active) link.setAttribute('aria-current', 'location'); else link.removeAttribute('aria-current'); }); }, {rootMargin: '-10% 0px -55% 0px', threshold: 0}); all('main>section').forEach(section => observer.observe(section)); }
$('#copy-command').addEventListener('click', async () => { try { await navigator.clipboard.writeText($('#serve-command').textContent); $('#copy-command').textContent = 'Copied'; } catch (_) { const range = document.createRange(); range.selectNodeContents($('#serve-command')); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); $('#copy-command').textContent = 'Select & copy'; } setTimeout(() => {$('#copy-command').textContent = 'Copy';}, 2500); });
