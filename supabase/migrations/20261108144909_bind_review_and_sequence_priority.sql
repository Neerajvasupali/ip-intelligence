begin;
create or replace function ipintel.event_context(cid uuid) returns jsonb
language sql stable set search_path='' as $$
 with events as (select *,nullif(trim(raw->>'account'),'') account from ipintel.events where case_id=cid),
 counts as (select count(*) total,count(*) filter(where outcome='failure') failures,count(*) filter(where outcome='success') successes,min(occurred_at) first_at,max(occurred_at) last_at,count(distinct account) filter(where outcome='failure') targeted_accounts,count(*) filter(where account is null) missing_account_events from events),
 sequence as (select exists(select 1 from events s where s.outcome='success' and s.account is not null and (select count(*) from events f where f.outcome='failure' and f.account=s.account and f.occurred_at<s.occurred_at)>=3) as same_account_success_after_failures),
 context as (select c.*,s.*,g.asset_id,g.asset_criticality,g.demo from counts c cross join sequence s left join ipintel.event_groups g on g.case_id=cid)
 select to_jsonb(x)||jsonb_build_object('priority',case when same_account_success_after_failures then 'high' when failures>=3 and asset_criticality='critical' then 'high' when failures>=3 then 'medium' else 'unassessed' end,
 'priority_reason',case when same_account_success_after_failures then 'At least three failures precede a success for the same supplied account; investigate whether access was authorized.' when failures>=3 and asset_criticality='critical' then 'Repeated failures target a declared critical asset.' when failures>=3 then 'At least three authentication failures in the correlation bucket; a same-account subsequent success is not established.' else 'Insufficient activity context for an elevated priority.' end,
 'priority_rules_version','1.1','events',coalesce((select jsonb_agg(jsonb_build_object('source',source,'event_id',event_id,'occurred_at',occurred_at,'asset_id',asset_id,'outcome',outcome,'account',account) order by occurred_at,event_id) from events),'[]'::jsonb)) from context x;
$$;

-- Preserve the previous routing implementation privately. Every public review
-- compares its supplied snapshot to a fresh report while event and provider
-- writes are fenced by the same transaction locks used by ingestion/finish.
do $$declare def text;begin
 def:=pg_get_functiondef('public.ipintel_api(text,jsonb)'::regprocedure);
 execute replace(def,'public.ipintel_api(', 'ipintel.event_api_v3(');
 def:=pg_get_functiondef('ipintel.core_api(text,jsonb)'::regprocedure);
 if position('select id into snapshot_id from ipintel.assessments where case_id=c.id order by created_at desc,id desc limit 1;' in def)=0 then raise exception 'Unexpected review implementation; migration requires inspection';end if;
 def:=replace(def,'select id into snapshot_id from ipintel.assessments where case_id=c.id order by created_at desc,id desc limit 1;','select id into snapshot_id from ipintel.assessments where case_id=c.id and id=(payload->>''assessment_id'')::uuid;');
 execute def;
end;$$;
revoke all on function ipintel.event_api_v3(text,jsonb) from public,anon,authenticated;

create or replace function public.ipintel_api(action text,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_report jsonb;
begin
 if action in ('report','case_update') then
  perform pg_advisory_xact_lock(719210);
  perform pg_advisory_xact_lock(719211);
 end if;
 if action='case_update' then
  if payload->'actor'->>'source' is distinct from 'n8n_authenticated_user' or coalesce(payload->'actor'->>'id','')='' then raise exception 'Authenticated n8n reviewer identity is required';end if;
  if coalesce(payload->>'assessment_id','')='' then raise exception 'Submit the assessment ID shown in the report';end if;
  current_report:=ipintel.core_api('report',jsonb_build_object('case_id',payload->>'case_id'));
  if current_report->>'assessment_id' is distinct from payload->>'assessment_id' then raise exception 'Evidence changed or assessment does not match this case. Refresh the report before reviewing.';end if;
 end if;
 return ipintel.event_api_v3(action,payload);
end;$$;
revoke all on function public.ipintel_api(text,jsonb) from public,anon,authenticated;
grant execute on function public.ipintel_api(text,jsonb) to service_role;
commit;
