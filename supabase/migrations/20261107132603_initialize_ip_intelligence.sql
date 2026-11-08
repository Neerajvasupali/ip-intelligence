begin;
create schema if not exists ipintel;
create table if not exists ipintel.providers(
 name text primary key, enabled boolean not null default false,
 daily_limit int not null default 100 check(daily_limit between 1 and 100),
 day date not null default (now() at time zone 'UTC')::date,
 used int not null default 0, next_at timestamptz not null default now(),
 ttl_seconds int not null, last_status text);
insert into ipintel.providers(name,ttl_seconds) values ('abuseipdb',21600),('virustotal',21600),('ipinfo',604800) on conflict do nothing;
create table if not exists ipintel.cases(
 id uuid primary key default gen_random_uuid(), request_key text unique not null,
 ip inet not null, reason text not null default '', status text not null default 'open'
 check(status in ('open','investigating','closed')), owner_name text not null default '',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists ipintel.jobs(
 id uuid primary key default gen_random_uuid(), ip inet not null,
 provider text not null references ipintel.providers(name), status text not null default 'queued'
 check(status in ('queued','running','done','failed')), attempts int not null default 0,
 due_at timestamptz not null default now(), lease_until timestamptz, token uuid,
 result jsonb, created_at timestamptz not null default now());
create unique index if not exists ipintel_active_job on ipintel.jobs(ip,provider) where status in ('queued','running');
create index if not exists ipintel_due_jobs on ipintel.jobs(status,due_at);
create table if not exists ipintel.case_sources(
 case_id uuid references ipintel.cases(id) on delete cascade, provider text not null,
 job_id uuid references ipintel.jobs(id), evidence jsonb, primary key(case_id,provider));
create index if not exists ipintel_case_sources_job on ipintel.case_sources(job_id);
create index if not exists ipintel_cases_created on ipintel.cases(created_at);
create table if not exists ipintel.cache(
 ip inet not null,provider text not null,result jsonb not null, expires_at timestamptz not null,
 primary key(ip,provider));
create table if not exists ipintel.audit(
 id bigint generated always as identity primary key,case_id uuid references ipintel.cases(id) on delete cascade,
 event text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
create index if not exists ipintel_audit_case_time on ipintel.audit(case_id,created_at desc);
alter table ipintel.providers enable row level security;
alter table ipintel.cases enable row level security;
alter table ipintel.jobs enable row level security;
alter table ipintel.case_sources enable row level security;
alter table ipintel.cache enable row level security;
alter table ipintel.audit enable row level security;
revoke all on schema ipintel from public,anon,authenticated;
create or replace function public.ipintel_api(action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 c ipintel.cases%rowtype; j ipintel.jobs%rowtype; p ipintel.providers%rowtype;
 addr inet; cid uuid; jid uuid; ev jsonb; n int; result_status text;
 next_time timestamptz; requested_time timestamptz; today date := (now() at time zone 'UTC')::date;
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
  return jsonb_build_object('found',true,'case',to_jsonb(c),'sources',
   (select jsonb_object_agg(s.provider,coalesce(s.evidence,
      case when j.status in ('done','failed') then j.result else jsonb_build_object('status',j.status,'attempts',j.attempts,'retry_at',j.due_at,'last_result',j.result) end))
    from ipintel.case_sources s left join ipintel.jobs j on j.id=s.job_id where s.case_id=c.id),
   'timeline',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select event,details,created_at from ipintel.audit where case_id=c.id order by created_at desc limit 100)x));
 elsif action='case_update' then
  select * into c from ipintel.cases where id=(payload->>'case_id')::uuid for update;
  if not found then raise exception 'Case not found';end if;
  if coalesce(payload->>'status','') not in ('open','investigating','closed') then raise exception 'Invalid case status';end if;
  if length(trim(coalesce(payload->>'note','')))<3 then raise exception 'A note is required for every update';end if;
  update ipintel.cases set status=payload->>'status',owner_name=left(coalesce(payload->>'owner',''),100),updated_at=now() where id=c.id;
  insert into ipintel.audit(case_id,event,details) values(c.id,'case_updated',jsonb_build_object('previous_status',c.status,'status',payload->>'status','owner',left(coalesce(payload->>'owner',''),100),'note',left(payload->>'note',2000)));
  return jsonb_build_object('updated',true,'case_id',c.id);
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
  delete from ipintel.jobs j where status in ('done','failed') and created_at<now()-interval '7 days' and not exists(select 1 from ipintel.case_sources s where s.job_id=j.id);
  return '{"completed":true,"policy":"Closed cases older than 90 days; expired cache older than 7 days; unreferenced completed jobs older than 7 days"}'::jsonb;
 else raise exception 'Unknown action';
 end if;
end;
$fn$;
revoke all on function public.ipintel_api(text,jsonb) from public,anon,authenticated;
grant execute on function public.ipintel_api(text,jsonb) to service_role;
commit;
