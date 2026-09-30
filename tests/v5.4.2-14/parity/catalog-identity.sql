\pset format unaligned
\pset tuples_only on
SELECT 'rel ' || c.relkind::text || ' ' || c.relname || ' force=' || c.relforcerowsecurity || ' rls=' || c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY 1;
SELECT 'col ' || c.relname || '.' || a.attname || ' ' || format_type(a.atttypid,a.atttypmod) || ' nn=' || a.attnotnull || ' def=' || coalesce(pg_get_expr(d.adbin,d.adrelid),'') FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE n.nspname='public' AND a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','v','m') ORDER BY 1;
SELECT 'con ' || conrelid::regclass || ' ' || conname || ' ' || pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace WHERE n.nspname='public' ORDER BY 1;
SELECT 'trg ' || tgrelid::regclass || ' ' || tgname || ' ' || tgenabled::text || ' ' || pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY 1;
SELECT 'fn ' || p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) || ' ' || coalesce(array_to_string(p.proacl,','),'') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN ('f','p') ORDER BY 1;
SELECT 'pol ' || tablename || ' ' || policyname || ' ' || coalesce(qual,'') || ' ' || coalesce(with_check,'') FROM pg_policies WHERE schemaname='public' ORDER BY 1;
SELECT 'idx ' || indexname || ' ' || indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1;
SELECT 'acl ' || c.relname || ' ' || coalesce(array_to_string(c.relacl,','),'') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY 1;
SELECT 'rows backbilling_rules ' || count(*) FROM public.backbilling_rules;
SELECT 'rows backbilling_rule_window_terms ' || count(*) FROM public.backbilling_rule_window_terms;
SELECT 'cmt fn ' || p.oid::regprocedure || ' ' || md5(coalesce(obj_description(p.oid,'pg_proc'),'')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1;
SELECT 'cmt rel ' || c.relname || ' ' || md5(coalesce(obj_description(c.oid,'pg_class'),'')) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY 1;
SELECT 'cmt col ' || c.relname || '.' || a.attname || ' ' || md5(coalesce(col_description(c.oid,a.attnum),'')) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','v','m') ORDER BY 1;
