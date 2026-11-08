
begin;
do $test$
declare src jsonb; cid uuid; r jsonb; r2 jsonb; sid uuid; count_before int;
begin
 src:='{"abuseipdb":{"status":"ok","evidence":{"abuse_confidence":0,"total_reports":188}},"virustotal":{"status":"ok","evidence":{"analysis_stats":{"malicious":1,"suspicious":0}}},"ipinfo":{"status":"ok","evidence":{"asn":"SYNTHETIC"}}}';
 if ipintel.evaluate_evidence(src)->>'assessment'<>'conflicting_evidence' then raise exception 'Conflict classification failed';end if;
 if ipintel.evaluate_evidence(jsonb_set(src,'{abuseipdb,evidence,abuse_confidence}','80'))->>'assessment'<>'cross_source_signals' then raise exception 'Cross-source classification failed';end if;
 if ipintel.evaluate_evidence(src-'abuseipdb')->>'assessment'<>'isolated_signal' then raise exception 'Isolated classification failed';end if;
 if (ipintel.evaluate_evidence(src-'abuseipdb')->>'coverage_complete')::boolean then raise exception 'Coverage failed';end if;
 if ipintel.evaluate_evidence(jsonb_set(src,'{virustotal,evidence,analysis_stats,malicious}','0'))->>'assessment'<>'no_known_malicious_evidence' then raise exception 'Negative evidence failed';end if;
 if ipintel.evaluate_evidence('{"virustotal":{"status":"queued"}}')->>'assessment'<>'pending' then raise exception 'Pending failed';end if;
 if ipintel.evaluate_evidence('{}')->>'assessment'<>'inconclusive' then raise exception 'Incomplete failed';end if;
 insert into ipintel.cases(request_key,ip) values('rollback-analyst-layer-acceptance','8.8.8.8') returning id into cid;
 insert into ipintel.case_sources(case_id,provider,evidence) select cid,key,value from jsonb_each(src);
 r:=public.ipintel_api('report',jsonb_build_object('case_id',cid));sid:=(r->>'assessment_id')::uuid;
 r2:=public.ipintel_api('report',jsonb_build_object('case_id',cid));
 if sid is null or r2->>'assessment_id'<>r->>'assessment_id' then raise exception 'Snapshot idempotency failed';end if;
 if (select count(*) from ipintel.assessments where case_id=cid)<>1 then raise exception 'Duplicate snapshots';end if;
 update ipintel.case_sources set evidence=jsonb_set(evidence,'{evidence,analysis_stats,malicious}','0') where case_id=cid and provider='virustotal';
 r2:=public.ipintel_api('report',jsonb_build_object('case_id',cid));
 if r2->>'assessment_id'=r->>'assessment_id' or (select count(*) from ipintel.assessments where case_id=cid)<>2 then raise exception 'Changed evidence not snapshotted';end if;
 if (select conclusion->>'assessment' from ipintel.assessments where id=sid)<>'conflicting_evidence' then raise exception 'Original conclusion changed';end if;
 begin update ipintel.assessments set rules_version='tampered' where id=sid;raise exception 'Mutation accepted';exception when others then if sqlerrm='Mutation accepted' then raise;end if;end;
 begin perform public.ipintel_api('case_update',jsonb_build_object('case_id',cid,'status','closed','disposition','confirmed_benign','note','Test'));raise exception 'Anonymous review accepted';exception when others then if sqlerrm='Anonymous review accepted' then raise;end if;end;
 r:=public.ipintel_api('case_update',jsonb_build_object('case_id',cid,'status','closed','disposition','confirmed_benign','note','Synthetic test decision only','assessment_id',r2->>'assessment_id','actor',jsonb_build_object('id','synthetic-test-actor','name','Test reviewer','source','n8n_authenticated_user')));
 if not (r->>'updated')::boolean then raise exception 'Attributed review failed';end if;
 if (select actor_id from ipintel.reviews where case_id=cid)<>'synthetic-test-actor' then raise exception 'Attribution failed';end if;
 begin update ipintel.reviews set explanation='tampered' where case_id=cid;raise exception 'Review mutation accepted';exception when others then if sqlerrm='Review mutation accepted' then raise;end if;end;
 begin perform public.ipintel_api('case_update',jsonb_build_object('case_id',cid,'status','closed','disposition','under_review','note','Still reviewing','actor',jsonb_build_object('id','test','name','Test','source','n8n_authenticated_user')));raise exception 'Pending closure accepted';exception when others then if sqlerrm='Pending closure accepted' then raise;end if;end;
 if has_table_privilege('anon','ipintel.assessments','select') or has_table_privilege('anon','ipintel.reviews','insert') then raise exception 'History exposed';end if;
end;$test$;
select 'passed' as analyst_layer_acceptance;
rollback;
