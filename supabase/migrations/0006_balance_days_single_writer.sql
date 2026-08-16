-- Make recompute_balance the only writer of balance_days.
--
-- 0005 gave the client the same write policy it gives every other table, which
-- is right for tables that record what the user did — food_log_entries,
-- activity_entries, body_metrics — and wrong for the one table that records
-- what the app concluded. balance_days is derived: the credit cap is what makes
-- it derived rather than summable, and a cap enforced inside a function is
-- worth nothing while a signed-in user can PATCH the closing balance straight
-- through PostgREST.
--
-- So writes go through the function or not at all. Reads stay exactly as they
-- were, on the caller's own policy.

drop policy "Users write their own balance history" on public.balance_days;


-- Now that no policy grants the caller a write, the function needs to stop
-- being one. Security definer here is not a shortcut around RLS in general —
-- it is scoped to this one table's integrity:
--
--   * every statement in the function already filters on v_user_id, which is
--     auth.uid() read once at entry and never taken from an argument, so a
--     caller cannot address another user's rows;
--   * the inserted user_id is v_user_id, so the on-conflict update can only
--     ever land on a row the caller already owns;
--   * search_path is pinned to '' in the function definition, so no caller can
--     shadow the tables or operators it resolves.
--
-- complete_onboarding stays invoker: every write it makes is one the caller is
-- separately allowed to make, which is no longer true here.
alter function public.recompute_balance(date) security definer;


-- Belt and braces. With no permissive policy the writes are already refused,
-- but revoking the privileges means a policy added by hand later cannot quietly
-- reopen the path — and it closes TRUNCATE, which RLS does not police at all.
revoke insert, update, delete, truncate on public.balance_days from anon, authenticated;


comment on function public.recompute_balance is
    'Rebuilds balance_days forward from a day and returns the current balance. '
    'The sole writer of balance_days — clients read that table but cannot write '
    'it, so the credit cap holds on every path. '
    'Call after any change to a past day: food entry, workout sync, or goal edit.';
