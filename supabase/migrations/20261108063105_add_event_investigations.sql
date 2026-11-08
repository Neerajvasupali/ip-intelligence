begin;
create table ipintel.events (
 id uuid primary key default gen_random_uuid(),
 source text not null, event_id text not null,
 case_id uuid not null references ipintel.cases(id) on delete cascade,
 occurred_at timestamptz not null, received_at timestamptz not null default now(),
 source_ip inet not null, asset_id text not null, outcome text not null check(outcome in ('success','failure')),
 raw jsonb not null, actor_id text not null, demo boolean not null default false,
 unique(source,event_id,demo)
);
create index on ipintel.events(case_id,occurred_at);
create index on ipintel.events(received_at);
create table ipintel.event_groups (
 case_id uuid primary key references ipintel.cases(id) on delete cascade,
 source text not null, source_ip inet not null, asset_id text not null,
 bucket timestamptz not null, demo boolean not null,
 asset_criticality text not null default 'unknown' check(asset_criticality in ('unknown','standard','critical'))
);
create index on ipintel.event_groups(source,source_ip,asset_id,bucket,demo);
alter table ipintel.events enable row level security;
alter table ipintel.event_groups enable row level security;
revoke all on ipintel.events,ipintel.event_groups from public,anon,authenticated;

create function ipintel.event_preview(payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare e jsonb; errors jsonb; rows jsonb:='[]'; idx int:=0; addr inet; stamp timestamptz; previous jsonb; normalized jsonb;
 seen jsonb:='{}'; k text; demo_mode boolean:=coalesce((payload->>'demo')::boolean,false);
begin
 if octet_length(payload::text)>262144 then raise exception 'Import exceeds 256 KiB';end if;
 if coalesce(payload->>'asset_criticality','unknown') not in ('unknown','standard','critical') then raise exception 'Invalid asset criticality';end if;
 if payload->>'schema_version' is distinct from '1.0' then raise exception 'schema_version must be 1.0';end if;
 if jsonb_typeof(payload->'events') is distinct from 'array' then raise exception 'events must be an array';end if;
 if jsonb_array_length(payload->'events') not between 1 and 100 then raise exception 'Import requires 1–100 events';end if;
 for e in select value from jsonb_array_elements(payload->'events') loop
  errors:='[]'; normalized:=e;
  if jsonb_typeof(e) is distinct from 'object' then errors:='["Record must be an object"]';
  else
   if exists(select 1 from jsonb_object_keys(e) key where key not in ('source','event_id','occurred_at','event_type','source_ip','asset_id','account','outcome')) then errors:=errors||'"Unknown event fields"'::jsonb;end if;
   foreach k in array array['source','event_id','asset_id'] loop
    if jsonb_typeof(e->k) is distinct from 'string' or length(trim(coalesce(e->>k,''))) not between 1 and 150 then errors:=errors||to_jsonb(k||': required string, maximum 150 characters');end if;
   end loop;
   if e->>'event_type' is distinct from 'ssh_authentication' then errors:=errors||'"Unsupported event_type"'::jsonb;end if;
   if coalesce(e->>'outcome','') not in ('success','failure') then errors:=errors||'"Invalid outcome"'::jsonb;end if;
   if e ? 'account' and (jsonb_typeof(e->'account') is distinct from 'string' or length(e->>'account')>150) then errors:=errors||'"Invalid account"'::jsonb;end if;
   begin
    if coalesce(e->>'occurred_at','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|\+00:00)$' then raise exception 'format';end if;
    stamp:=(e->>'occurred_at')::timestamptz;
    if not isfinite(stamp) or stamp>now()+interval '5 minutes' then raise exception 'future';end if;
   exception when others then errors:=errors||'"occurred_at: valid UTC timestamp required; future events excluded"'::jsonb;end;
   begin
    addr:=(e->>'source_ip')::inet;
    if addr is null or masklen(addr)<>(case when family(addr)=4 then 32 else 128 end) then raise exception 'single IP';end if;
    if demo_mode then
     if not (addr <<= any(array['192.0.2.0/24','198.51.100.0/24','203.0.113.0/24','2001:db8::/32']::inet[])) then raise exception 'Demo requires documentation address';end if;
    else
     if family(addr)=4 and addr <<= any(array['0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.0.0.0/24','192.0.2.0/24','192.88.99.0/24','192.168.0.0/16','198.18.0.0/15','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','240.0.0.0/4']::inet[]) then raise exception 'Special-use IP';end if;
     if family(addr)=6 and (not addr <<= '2000::/3'::inet or addr <<= any(array['2001::/23','2001:db8::/32','2002::/16','3fff::/20']::inet[])) then raise exception 'Special-use IP';end if;
    end if;
   exception when others then errors:=errors||'"source_ip: public single IP required; demo accepts documentation addresses only"'::jsonb;end;
   if errors='[]' then
    k:=jsonb_build_array(e->>'source',e->>'event_id')::text;
    previous:=seen->k;
    if previous is null then select raw into previous from ipintel.events where source=e->>'source' and event_id=e->>'event_id' and events.demo=demo_mode;end if;
    if previous is not null and previous<>e then errors:=errors||'"Conflicting event identifier"'::jsonb;end if;
    seen:=jsonb_set(seen,array[k],e);
   end if;
  end if;
  rows:=rows||jsonb_build_object('index',idx,'status',case when errors<>'[]' then 'rejected' when previous is not null then 'duplicate' else 'accepted' end,'errors',errors);
  idx:=idx+1;previous:=null;
 end loop;
 return jsonb_build_object('rows',rows,'can_import',not exists(select 1 from jsonb_array_elements(rows) r where r->>'status'='rejected'),'demo',demo_mode,'preview_only',true);
end;$$;

create function ipintel.event_context(cid uuid) returns jsonb
language sql stable set search_path='' as $$
 with counts as (select count(*) as total,count(*) filter(where outcome='failure') as failures,count(*) filter(where outcome='success') as successes,min(occurred_at) as first_at,max(occurred_at) as last_at from ipintel.events where case_id=cid),
 context as (select c.*,g.asset_id,g.asset_criticality,g.demo from counts c left join ipintel.event_groups g on g.case_id=cid)
 select to_jsonb(x)||jsonb_build_object('priority',case when failures>=3 and successes>0 then 'high' when failures>=3 and asset_criticality='critical' then 'high' when failures>=3 then 'medium' else 'unassessed' end,
 'priority_reason',case when failures>=3 and successes>0 then 'Repeated failures and a success occur in this group; investigate their sequence and relationship.' when failures>=3 and asset_criticality='critical' then 'Repeated failures target a declared critical asset.' when failures>=3 then 'At least three authentication failures in the same correlation bucket.' else 'Insufficient activity context for an elevated priority.' end,
 'priority_rules_version','1.0','events',coalesce((select jsonb_agg(jsonb_build_object('source',source,'event_id',event_id,'occurred_at',occurred_at,'asset_id',asset_id,'outcome',outcome,'account',raw->>'account') order by occurred_at,event_id) from ipintel.events where case_id=cid),'[]'::jsonb)) from context x;
$$;

-- Retain the deployed implementation privately; the public API remains backward-compatible.
do $$declare def text;begin
 def:=pg_get_functiondef('public.ipintel_api(text,jsonb)'::regprocedure);
 def:=replace(def,'public.ipintel_api(', 'ipintel.core_api(');
 def:=replace(def,'evaluation:=ipintel.evaluate_evidence(result_report->''sources'');','evaluation:=ipintel.evaluate_evidence(result_report->''sources'')||jsonb_build_object(''event_context'',ipintel.event_context(c.id));');
 execute def;
end;$$;
revoke all on function ipintel.core_api(text,jsonb) from public,anon,authenticated;

create or replace function public.ipintel_api(action text,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; e jsonb; cid uuid; bucket_value timestamptz; addr inet; group_row ipintel.event_groups%rowtype; actor jsonb:=payload->'actor'; demo_mode boolean:=coalesce((payload->>'demo')::boolean,false); inserted int:=0; duplicates int:=0; ids jsonb:='[]'; row_value jsonb; prior jsonb;
begin
 if action in ('events_preview','events_ingest') then
  if actor->>'source' is distinct from 'n8n_authenticated_user' or length(coalesce(actor->>'id','')) not between 1 and 200 then raise exception 'Authenticated n8n user required';end if;
  perform pg_advisory_xact_lock(719210);
  result:=ipintel.event_preview(payload);
  if action='events_preview' or not (result->>'can_import')::boolean then return result;end if;
  if (select count(*) from ipintel.events where received_at>now()-interval '1 day')+jsonb_array_length(payload->'events')>1000 then raise exception 'Daily event admission limit reached';end if;
  for e in select value from jsonb_array_elements(payload->'events') loop
   select case_id into cid from ipintel.events where source=e->>'source' and event_id=e->>'event_id' and events.demo=demo_mode;
   if found then duplicates:=duplicates+1;
   else
    addr:=(e->>'source_ip')::inet;
    bucket_value:=date_bin(interval '15 minutes',(e->>'occurred_at')::timestamptz,'2000-01-01Z'::timestamptz);
    select g.* into group_row from ipintel.event_groups g join ipintel.cases c on c.id=g.case_id where g.source=e->>'source' and g.source_ip=addr and g.asset_id=e->>'asset_id' and g.bucket=bucket_value and g.demo=demo_mode and c.status<>'closed' order by c.created_at desc limit 1;
    if found then cid:=group_row.case_id;
    else
     if demo_mode then
      if (select count(*) from ipintel.cases where created_at>now()-interval '1 day')>=200 then raise exception 'Case admission limit reached';end if;
      insert into ipintel.cases(request_key,ip,reason) values('event-demo-'||gen_random_uuid()::text,addr,'Synthetic SSH investigation; no live provider calls') returning id into cid;
      insert into ipintel.case_sources(case_id,provider,evidence) select cid,name,jsonb_build_object('status','unavailable','reason','Synthetic demo: provider requests disabled') from ipintel.providers;
     else
      row_value:=ipintel.core_api('enqueue',jsonb_build_object('request_key','event-'||gen_random_uuid()::text,'ip',host(addr),'reason','SSH authentication activity for asset '||(e->>'asset_id')));
      cid:=(row_value->>'case_id')::uuid;
     end if;
     insert into ipintel.event_groups(case_id,source,source_ip,asset_id,bucket,demo,asset_criticality) values(cid,e->>'source',addr,e->>'asset_id',bucket_value,demo_mode,coalesce(payload->>'asset_criticality','unknown'));
    end if;
    insert into ipintel.events(source,event_id,case_id,occurred_at,source_ip,asset_id,outcome,raw,actor_id,demo) values(e->>'source',e->>'event_id',cid,(e->>'occurred_at')::timestamptz,addr,e->>'asset_id',e->>'outcome',e,actor->>'id',demo_mode);
    insert into ipintel.audit(case_id,event,details) values(cid,'event_received',jsonb_build_object('source',e->>'source','event_id',e->>'event_id','actor_id',actor->>'id','demo',demo_mode));
    inserted:=inserted+1;
   end if;
   if not ids @> jsonb_build_array(cid) then ids:=ids||to_jsonb(cid);end if;
  end loop;
  return result||jsonb_build_object('preview_only',false,'inserted',inserted,'duplicates',duplicates,'case_ids',ids);
 elsif action='worklist' then
  return jsonb_build_object('cases',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select c.id,host(c.ip) ip,c.status,c.owner_name,c.created_at,ipintel.event_context(c.id) as context from ipintel.cases c where (coalesce(payload->>'status','')='' or c.status=payload->>'status') order by c.created_at desc limit 50)x));
 else return ipintel.core_api(action,payload);
 end if;
end;$$;
revoke all on function public.ipintel_api(text,jsonb) from public,anon,authenticated;
grant execute on function public.ipintel_api(text,jsonb) to service_role;
revoke all on function ipintel.event_preview(jsonb),ipintel.event_context(uuid) from public,anon,authenticated;
commit;
