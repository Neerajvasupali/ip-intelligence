
create table ipintel.assessments(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references ipintel.cases(id) on delete cascade,
 rules_version text not null,
 fingerprint text not null,
 evidence jsonb not null,
 conclusion jsonb not null,
 created_at timestamptz not null default now(),
 unique(case_id,rules_version,fingerprint)
);
create index ipintel_assessments_case_time on ipintel.assessments(case_id,created_at desc);
create table ipintel.reviews(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references ipintel.cases(id) on delete cascade,
 assessment_id uuid references ipintel.assessments(id),
 disposition text not null check(disposition in ('under_review','confirmed_malicious','confirmed_benign','insufficient_evidence','duplicate')),
 explanation text not null check(length(trim(explanation))>=3),
 actor_id text not null,
 actor_name text not null,
 actor_source text not null check(actor_source='n8n_authenticated_user'),
 case_status text not null,
 created_at timestamptz not null default now()
);
create index ipintel_reviews_case_time on ipintel.reviews(case_id,created_at desc);
alter table ipintel.assessments enable row level security;
alter table ipintel.reviews enable row level security;
revoke all on ipintel.assessments,ipintel.reviews from public,anon,authenticated;
create function ipintel.reject_history_update() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'History records cannot be updated; append a new record instead';end;$$;
create trigger assessments_immutable before update on ipintel.assessments for each row execute function ipintel.reject_history_update();
create trigger reviews_immutable before update on ipintel.reviews for each row execute function ipintel.reject_history_update();
revoke all on function ipintel.reject_history_update() from public,anon,authenticated;
create function ipintel.evaluate_evidence(sources jsonb) returns jsonb language plpgsql set search_path='' as $$
declare
 a jsonb:=sources->'abuseipdb';v jsonb:=sources->'virustotal';
 flags int:=0; confidence int:=0; reports int:=0;
 covered boolean; pending boolean; stale boolean:=false; verdict text;
 reasons jsonb:='[]';warnings jsonb:='[]'; stamp timestamptz;
begin
 covered:=coalesce(a->>'status'='ok' and v->>'status'='ok',false);
 pending:=exists(select 1 from jsonb_each(sources) x where x.value->>'status' in ('queued','running'));
 if v->>'status'='ok' then flags:=coalesce((v#>>'{evidence,analysis_stats,malicious}')::int,0)+coalesce((v#>>'{evidence,analysis_stats,suspicious}')::int,0);end if;
 if a->>'status'='ok' then confidence:=coalesce((a#>>'{evidence,abuse_confidence}')::int,0);reports:=coalesce((a#>>'{evidence,total_reports}')::int,0);end if;
 begin
  if v#>>'{evidence,last_analysis_date}' is not null then
   stamp:=to_timestamp((v#>>'{evidence,last_analysis_date}')::double precision);
   if stamp<now()-interval '30 days' then stale:=true;warnings:=warnings||jsonb_build_array('VirusTotal underlying analysis is more than 30 days old.');end if;
  elsif v->>'status'='ok' then warnings:=warnings||jsonb_build_array('VirusTotal underlying analysis date is unavailable.');end if;
 exception when others then warnings:=warnings||jsonb_build_array('VirusTotal observation date could not be interpreted.');end;
 begin
  if reports>0 and a#>>'{evidence,last_reported_at}' is not null and (a#>>'{evidence,last_reported_at}')::timestamptz<now()-interval '30 days' then
   stale:=true;warnings:=warnings||jsonb_build_array('The latest AbuseIPDB abuse report is more than 30 days old.');
  end if;
 exception when others then warnings:=warnings||jsonb_build_array('AbuseIPDB observation date could not be interpreted.');end;
 if confidence>=50 and reports>0 and flags>0 then verdict:='cross_source_signals';reasons:=reasons||jsonb_build_array('VirusTotal flags and elevated AbuseIPDB confidence both warrant investigation. These sources are not assumed independent.');
 elsif confidence>=50 and reports>0 then verdict:='abuse_signal';reasons:=reasons||jsonb_build_array('AbuseIPDB confidence is at least 50 with reported abuse; verify the associated activity.');
 elsif flags=1 and a->>'status'='ok' and confidence=0 then verdict:='conflicting_evidence';reasons:=reasons||jsonb_build_array('An isolated VirusTotal flag is not corroborated by AbuseIPDB current confidence of 0. Zero confidence does not establish that the IP is benign.');
 elsif flags=1 then verdict:='isolated_signal';reasons:=reasons||jsonb_build_array('One VirusTotal vendor reported a flag. Treat it as an isolated signal requiring verification.');
 elsif flags>1 then verdict:='multiple_vendor_signals';reasons:=reasons||jsonb_build_array('Multiple VirusTotal vendor flags warrant review; vendor results may overlap and are not independent proof.');
 elsif pending then verdict:='pending';reasons:=reasons||jsonb_build_array('Provider jobs are still queued or running.');
 elsif not covered then verdict:='inconclusive';reasons:=reasons||jsonb_build_array('Reputation evidence is incomplete.');
 elsif stale then verdict:='outdated_evidence';reasons:=reasons||jsonb_build_array('No rule found a positive signal, but underlying evidence is old. Do not infer current safety.');
 else verdict:='no_known_malicious_evidence';reasons:=reasons||jsonb_build_array('No available evidence met the project signal rules. This does not prove the IP is safe.');end if;
 if not covered and verdict not in ('pending','inconclusive') then reasons:=reasons||jsonb_build_array('Some reputation evidence is missing; the assessment is partial.');end if;
 return jsonb_build_object('assessment',verdict,'rules_version','2.0','reasons',reasons,'age_warnings',warnings,'coverage_complete',covered,
 'evidence_quality',case when not covered then 'partial' when stale then 'stale' else 'available' end,
 'recommendation','Correlate these findings with observed activity and asset context. Record an analyst disposition with an explanation; no automatic blocking.');
end;$$;
revoke all on function ipintel.evaluate_evidence(jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ipintel_api(action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 c ipintel.cases%rowtype; j ipintel.jobs%rowtype; p ipintel.providers%rowtype;
 addr inet; cid uuid; jid uuid; ev jsonb; result_status text;
 next_time timestamptz; requested_time timestamptz; today date := (now() at time zone 'UTC')::date;
 result_report jsonb; evaluation jsonb; snapshot_id uuid; fp text; actor jsonb; disposition_value text;
begin
 if action='enqueue' then
  if length(coalesce(payload->>'request_key','')) not between 1 and 150 then raise exception 'A request key is required'; end if;
  addr:=(payload->>'ip')::inet;
  if masklen(addr)<>(case when family(addr)=4 then 32 else 128 end) then raise exception 'A single IP is required'; end if;
  if family(addr)=4 then
   if addr <<= any(array['0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.0.0.0/24','192.0.2.0/24','192.88.99.0/24','192.168.0.0/16','198.18.0.0/15','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','240.0.0.0/4']::inet[]) then raise exception 'Special-use IP excluded'; end if;
  elsif not addr <<= '2000::/3'::inet or addr <<= any(array['2001::/23','2001:db8::/32','2002::/16','3fff::/20']::inet[]) then raise exception 'Special-use IPv6 excluded'; end if;
  perform pg_advisory_xact_lock(719210);
  select * into c from ipintel.cases where request_key=payload->>'request_key';
  if found then
   if c.ip<>addr then raise exception 'Request key already belongs to a different IP'; end if;
   return jsonb_build_object('case_id',c.id,'duplicate',true);
  end if;
  if (select count(*) from ipintel.cases where created_at>=now()-interval '1 day')>=200 then raise exception 'Submission budget reached; retry later';end if;
  insert into ipintel.cases(request_key,ip,reason) values(payload->>'request_key',addr,left(coalesce(payload->>'reason',''),2000)) returning id into cid;
  for p in select * from ipintel.providers order by name loop
   ev:=null;jid:=null;
   select result into ev from ipintel.cache where ip=addr and provider=p.name and expires_at>now();
   if ev is not null then ev:=ev||'{"from_cache":true}'::jsonb;
   elsif not p.enabled then ev:=jsonb_build_object('status','not_configured','reason','Provider is disabled');
   else
    insert into ipintel.jobs(ip,provider) values(addr,p.name)
     on conflict(ip,provider) where status in ('queued','running') do update set ip=excluded.ip returning id into jid;
   end if;
   insert into ipintel.case_sources(case_id,provider,job_id,evidence) values(cid,p.name,jid,ev);
  end loop;
  insert into ipintel.audit(case_id,event,details) values(cid,'submitted',jsonb_build_object('source','n8n','ip',host(addr)));
  return jsonb_build_object('case_id',cid,'duplicate',false,'message','Investigation recorded. Save this ID to retrieve results.');
 elsif action='claim' then
  if not pg_try_advisory_xact_lock(719211) then return '{"available":false}'::jsonb;end if;
  update ipintel.jobs set status='failed',result='{"status":"unavailable","reason":"Worker lease expired after maximum attempts"}'::jsonb,token=null
    where status='running' and lease_until<now() and attempts>=3;
  update ipintel.jobs set status='queued',due_at=now(),token=null where status='running' and lease_until<now() and attempts<3;
  for p in select * from ipintel.providers where enabled order by next_at,name for update loop
   if p.day<>today then update ipintel.providers set day=today,used=0 where name=p.name;p.used:=0;end if;
   if p.used>=p.daily_limit or p.next_at>now() then continue;end if;
   select * into j from ipintel.jobs where provider=p.name and status='queued' and due_at<=now() order by due_at,created_at limit 1 for update skip locked;
   if not found then continue;end if;
   update ipintel.jobs set status='running',attempts=attempts+1,token=gen_random_uuid(),lease_until=now()+interval '10 minutes' where id=j.id returning * into j;
   update ipintel.providers set used=used+1,next_at=now()+interval '60 seconds' where name=p.name;
   return jsonb_build_object('available',true,'job_id',j.id,'token',j.token,'ip',host(j.ip),'provider',j.provider,'attempt',j.attempts,'lease_until',j.lease_until);
  end loop;
  return '{"available":false}'::jsonb;
 elsif action='finish' then
  perform pg_advisory_xact_lock(719211);
  select * into j from ipintel.jobs where id=(payload->>'job_id')::uuid for update;
  if not found then raise exception 'Unknown job';end if;
  if j.token is null or (payload->>'token') is null or j.token is distinct from (payload->>'token')::uuid then return '{"accepted":false,"reason":"stale lease"}'::jsonb;end if;
  if j.status in ('done','failed') then return '{"accepted":true,"duplicate":true}'::jsonb;end if;
  if j.status<>'running' or j.lease_until is null or j.lease_until<now() then return '{"accepted":false,"reason":"expired lease"}'::jsonb;end if;
  ev:=payload->'result';result_status:=ev->>'status';
  if result_status is null or result_status not in ('ok','not_found','unavailable','rate_limited','authentication_error') then raise exception 'Invalid result status';end if;
  if octet_length(ev::text)>50000 then raise exception 'Result exceeds storage limit';end if;
  select * into p from ipintel.providers where name=j.provider for update;
  if result_status in ('ok','not_found') then
   ev:=ev||jsonb_build_object('checked_at',now(),'from_cache',false);
   update ipintel.jobs set status='done',result=ev where id=j.id;
   insert into ipintel.cache(ip,provider,result,expires_at) values(j.ip,j.provider,ev,now()+make_interval(secs=>case when result_status='not_found' then 3600 else p.ttl_seconds end))
    on conflict(ip,provider) do update set result=excluded.result,expires_at=excluded.expires_at;
  else
   next_time:=now()+make_interval(secs=>case when result_status='rate_limited' then 3600 else 60*power(2,j.attempts)::int end);
   if payload->>'retry_at' is not null then
    begin requested_time:=(payload->>'retry_at')::timestamptz; next_time:=greatest(next_time,requested_time);exception when others then null;end;
   end if;
   update ipintel.providers set next_at=greatest(next_at,next_time),enabled=case when result_status='authentication_error' then false else enabled end where name=j.provider;
   update ipintel.jobs set status=case when j.attempts>=3 or result_status='authentication_error' then 'failed' else 'queued' end,due_at=next_time,result=ev where id=j.id;
  end if;
  update ipintel.providers set last_status=result_status where name=j.provider;
  insert into ipintel.audit(case_id,event,details) select case_id,'provider_result',jsonb_build_object('provider',j.provider,'status',result_status,'attempt',j.attempts) from ipintel.case_sources where job_id=j.id;
  return jsonb_build_object('accepted',true,'job_id',j.id,'result_status',result_status);
 elsif action='report' then
  select * into c from ipintel.cases where id=(payload->>'case_id')::uuid;
  if not found then return '{"found":false}'::jsonb;end if;
  result_report:=jsonb_build_object('found',true,'case',to_jsonb(c),'sources',
   (select jsonb_object_agg(s.provider,coalesce(s.evidence,
      case when jobrow.status in ('done','failed') then jobrow.result else jsonb_build_object('status',jobrow.status,'attempts',jobrow.attempts,'retry_at',jobrow.due_at,'last_result',jobrow.result) end))
    from ipintel.case_sources s left join ipintel.jobs jobrow on jobrow.id=s.job_id where s.case_id=c.id),
   'timeline',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select event,details,created_at from ipintel.audit where case_id=c.id order by created_at desc limit 100)x));

  evaluation:=ipintel.evaluate_evidence(result_report->'sources');
  fp:=md5(jsonb_build_object('sources',result_report->'sources','evaluation',evaluation)::text);
  insert into ipintel.assessments(case_id,rules_version,fingerprint,evidence,conclusion)
    values(c.id,'2.0',fp,result_report->'sources',evaluation) on conflict do nothing;
  select id into snapshot_id from ipintel.assessments where case_id=c.id and rules_version='2.0' and fingerprint=fp;
  return result_report||evaluation||jsonb_build_object('assessment_id',snapshot_id,
   'assessment_history',(select coalesce(jsonb_agg(x),'[]') from (select id,rules_version,conclusion,created_at from ipintel.assessments where case_id=c.id order by created_at desc,id desc limit 20)x),
   'analyst_reviews',(select coalesce(jsonb_agg(x),'[]') from (select id,disposition,explanation,actor_id,actor_name,actor_source,case_status,assessment_id,created_at from ipintel.reviews where case_id=c.id order by created_at desc,id desc limit 20)x),
   'generated_at',now());

 elsif action='case_update' then
  select * into c from ipintel.cases where id=(payload->>'case_id')::uuid for update;
  if not found then raise exception 'Case not found';end if;
  actor:=payload->'actor';disposition_value:=payload->>'disposition';
  if actor->>'source' is distinct from 'n8n_authenticated_user' or length(coalesce(actor->>'id',''))<1 then raise exception 'Authenticated n8n reviewer identity is required';end if;
  if coalesce(payload->>'status','') not in ('open','investigating','closed') then raise exception 'Invalid case status';end if;
  if coalesce(disposition_value,'') not in ('under_review','confirmed_malicious','confirmed_benign','insufficient_evidence','duplicate') then raise exception 'Choose an analyst disposition';end if;
  if payload->>'status'='closed' and disposition_value='under_review' then raise exception 'Choose a final disposition before closing the case';end if;
  if length(trim(coalesce(payload->>'note','')))<3 then raise exception 'An explanation is required';end if;
  select id into snapshot_id from ipintel.assessments where case_id=c.id order by created_at desc,id desc limit 1;
  insert into ipintel.reviews(case_id,assessment_id,disposition,explanation,actor_id,actor_name,actor_source,case_status)
   values(c.id,snapshot_id,disposition_value,left(payload->>'note',2000),left(actor->>'id',200),left(coalesce(nullif(actor->>'name',''),actor->>'id'),200),'n8n_authenticated_user',payload->>'status');
  update ipintel.cases set status=payload->>'status',owner_name=left(coalesce(payload->>'owner',''),100),updated_at=now() where id=c.id;
  insert into ipintel.audit(case_id,event,details) values(c.id,'analyst_reviewed',jsonb_build_object('previous_status',c.status,'status',payload->>'status','owner',payload->>'owner','note',left(payload->>'note',2000),'disposition',disposition_value,'actor_id',actor->>'id','actor_name',actor->>'name','assessment_id',snapshot_id));
  return jsonb_build_object('updated',true,'case_id',c.id,'disposition',disposition_value,'reviewed_by',actor->>'name');
 elsif action='metrics' then
  return jsonb_build_object('generated_at',now(),'providers',(select jsonb_agg(to_jsonb(x)) from (select name,enabled,daily_limit,case when day=today then used else 0 end as requests_today,next_at,last_status from ipintel.providers)x),
   'jobs',(select coalesce(jsonb_object_agg(status,n),'{}'::jsonb) from (select status,count(*) n from ipintel.jobs group by status)x),
   'cases',(select coalesce(jsonb_object_agg(status,n),'{}'::jsonb) from (select status,count(*) n from ipintel.cases group by status)x),
   'oldest_queued_at',(select min(created_at) from ipintel.jobs where status='queued'),
   'cache_entries',(select count(*) from ipintel.cache),
   'recent_cases',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select id,host(ip) as ip,status,created_at from ipintel.cases order by created_at desc limit 25)x));
 elsif action='configure' then
  if coalesce(payload->>'provider','') not in ('abuseipdb','virustotal','ipinfo') then raise exception 'Unknown provider';end if;
  update ipintel.providers set enabled=(payload->>'enabled')::boolean,next_at=greatest(next_at,now()) where name=payload->>'provider';
  return '{"updated":true}'::jsonb;
 elsif action='maintenance' then
  delete from ipintel.cases where status='closed' and updated_at<now()-interval '90 days';
  delete from ipintel.cache where expires_at<now()-interval '7 days';
  delete from ipintel.jobs stalejob where status in ('done','failed') and created_at<now()-interval '7 days' and not exists(select 1 from ipintel.case_sources s where s.job_id=stalejob.id);
  return '{"completed":true,"policy":"Closed cases older than 90 days; expired cache older than 7 days; unreferenced completed jobs older than 7 days"}'::jsonb;
 else raise exception 'Unknown action';
 end if;
end;
$function$
