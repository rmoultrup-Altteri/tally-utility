-- NOT EXECUTED. Owner, fresh clone with frozen r6 applied. No role DDL.
-- r6 matrices: every case validates both input documents, prints comparison and combined section.
-- Predict fraction ordering, customer-dependent pay alternatives, any_time widest;
-- the no-finding stage control changes only final. See codex-r6.md N3.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE base_l jsonb; base_t jsonb; l jsonb; t jsonb; c jsonb; k text; v jsonb; errs text[];
BEGIN
 SELECT terms INTO STRICT base_l FROM public.dispute_rules
 WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 base_t := base_l - 'governs';
 FOREACH k IN ARRAY ARRAY['subjects','shelter_earned','shelter_ends','must_pay','blocks','duties'] LOOP
  base_t := jsonb_set(base_t,ARRAY[k],(base_t->k)-'citation');
 END LOOP;
 base_t := jsonb_set(base_t,'{stages}',(SELECT jsonb_agg(x-'citation' ORDER BY n) FROM jsonb_array_elements(base_t->'stages') WITH ORDINALITY z(x,n)));
 FOR c IN SELECT value FROM jsonb_array_elements($cases$[
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1}",
    "section": "must_pay",
    "law": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1,
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'}",
    "section": "must_pay",
    "law": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'full_bill', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'undisputed_charges', 'version': 1, 'id': 'm1'} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "undisputed_charges",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 0.9} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 0.9
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1
    }
  },
  {
    "name": "pay {'strategy': 'withhold_cap', 'version': 1, 'id': 'm1', 'fraction': 1.1} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "withhold_cap",
      "version": 1,
      "id": "m1",
      "fraction": 1.1
    }
  },
  {
    "name": "pay {'strategy': 'average_usage_cap', 'version': 1, 'id': 'm1', 'history_years': 2, 'no_history': 'similar_customers'} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "average_usage_cap",
      "version": 1,
      "id": "m1",
      "history_years": 2,
      "no_history": "similar_customers"
    }
  },
  {
    "name": "pay {'strategy': 'full_bill', 'version': 1, 'id': 'm1'} / law {'strategy': 'unruled', 'version': 1, 'id': 'm1'}",
    "section": "must_pay",
    "law": {
      "strategy": "unruled",
      "version": 1,
      "id": "m1",
      "citation": "probe"
    },
    "tariff": {
      "strategy": "full_bill",
      "version": 1,
      "id": "m1"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'before_termination'}",
    "section": "shelter_earned",
    "law": {
      "kind": "before_termination",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'before_termination'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "before_termination"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'before_delinquency'}",
    "section": "shelter_earned",
    "law": {
      "kind": "before_delinquency",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'before_delinquency'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "before_delinquency"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'within_days', 'days': 21, 'from': 'receipt'}",
    "section": "shelter_earned",
    "law": {
      "kind": "within_days",
      "days": 21,
      "from": "receipt",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'within_days', 'days': 21, 'from': 'receipt'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "within_days",
      "days": 21,
      "from": "receipt"
    }
  },
  {
    "name": "start {'kind': 'any_time'} / law {'kind': 'on_regulator_complaint'}",
    "section": "shelter_earned",
    "law": {
      "kind": "on_regulator_complaint",
      "citation": "probe"
    },
    "tariff": {
      "kind": "any_time"
    }
  },
  {
    "name": "start {'kind': 'on_regulator_complaint'} / law {'kind': 'any_time'}",
    "section": "shelter_earned",
    "law": {
      "kind": "any_time",
      "citation": "probe"
    },
    "tariff": {
      "kind": "on_regulator_complaint"
    }
  },
  {
    "name": "no-stage-finding law final false",
    "section": "stages",
    "law": [
      {
        "id": "law_s",
        "decider": "regulator",
        "file_within": {
          "kind": "days",
          "days": 20,
          "from": "receipt"
        },
        "decide_within": {
          "kind": "days",
          "days": 20
        },
        "final": false,
        "citation": "probe"
      }
    ],
    "tariff": [
      {
        "id": "policy_s",
        "decider": "regulator",
        "file_within": {
          "kind": "days",
          "days": 30,
          "from": "receipt"
        },
        "decide_within": {
          "kind": "days",
          "days": 10
        },
        "final": true
      }
    ]
  }
]$cases$::jsonb) LOOP
  BEGIN
   k:=c->>'section'; l:=jsonb_set(base_l,ARRAY[k],c->'law'); t:=jsonb_set(base_t,ARRAY[k],c->'tariff');
   SELECT public.rule_terms_errors(json_schema,l,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'law schema errors %',errs; END IF;
   SELECT public.rule_terms_errors(json_schema,t,true) INTO errs FROM public.rule_term_schemas WHERE terms_kind='dispute_tariff' AND terms_version=1;
   IF cardinality(errs)>0 THEN RAISE EXCEPTION 'tariff schema errors %',errs; END IF;
   PERFORM public.dispute_terms_check('law probe',l); PERFORM public.dispute_terms_check('tariff probe',t);
   RAISE NOTICE '% comparison=%',c->>'name',(SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]') FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms',t),jsonb_build_array(jsonb_build_object('terms',l))) f);
   v:=public.dispute_terms_combined(jsonb_build_object('terms',t),jsonb_build_object('terms',l));
   RAISE NOTICE '% SQLSTATE=00000 law=% tariff=% combined=%',c->>'name',l->k,t->k,v->k;
   IF k='stages' THEN
    RAISE NOTICE 'nonfinal properties identical=% final_false=%', (v#>'{stages,0}')-'final' = (t#>'{stages,0}')-'final', v#>'{stages,0,final}'='false'::jsonb;
   END IF;
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE '% SQLSTATE=% message=%',c->>'name',SQLSTATE,SQLERRM;
  END;
 END LOOP;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'setup SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
-- The newly granted comparator is an invoker and reads only the shared vocabulary.
SET LOCAL ROLE tally_core;
DO $$ DECLARE l jsonb; v jsonb; BEGIN
 SELECT to_jsonb(r) INTO STRICT l FROM public.dispute_rules r WHERE customer_class='protected' AND 'investor_owned'=ANY(owner_types) AND effective_to IS NULL;
 v:=public.dispute_terms_combined(l,l);
 RAISE NOTICE 'core helper SQLSTATE=00000 terms_nonnull=%',v IS NOT NULL;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'core helper SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
RESET ROLE;
ROLLBACK;
