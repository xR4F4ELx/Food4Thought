-- Whole kilocalories in the rollup.
--
-- balance_days mixed two precisions. consumed_kcal and burned_kcal kept the
-- fractional totals the entries summed to, while closing_balance_kcal is an
-- integer, so a day of two 1250.30 servings recorded "2500.60 consumed, 500.60
-- over" and then moved the balance by 501. Every figure on the row is
-- snapshotted so a past day stays explainable, and a row whose own subtraction
-- does not reconcile is not explainable.
--
-- Nothing is lost by rounding here. food_log_entries and activity_entries keep
-- their decimals and remain the source of truth; only the derived daily figures
-- round, half a kcal at a time, against entries whose real accuracy is ±30 kcal
-- for a piece of fruit.

-- The generated column has to go first: it is defined over the two columns
-- whose type changes.
alter table public.balance_days drop column overage_kcal;

alter table public.balance_days
    alter column consumed_kcal type integer using round(consumed_kcal)::integer,
    alter column burned_kcal   type integer using round(burned_kcal)::integer;

alter table public.balance_days
    add column overage_kcal integer not null
        generated always as (greatest(0, consumed_kcal - daily_calorie_target)) stored;


-- The function rounded each figure a second time on its way into the
-- arithmetic, which is now the only rounding: the day's totals are reduced to
-- whole kilocalories once, and the same integers are both stored and scored.
--
-- Restated in full because create or replace resets the function's attributes:
-- security and search_path are part of the definition, so leaving them out here
-- would silently revert 0006 and hand the caller back a security invoker.
create or replace function public.recompute_balance(
    p_from_day date default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    -- Fixed here rather than taken as an argument. The cap is a product rule,
    -- and this function is callable straight from PostgREST by any signed-in
    -- user: a cap passed in by the caller is a default, not a rule, and lets
    -- anyone bank the burn the cap exists to drop.
    c_credit_cap constant integer := 500;

    v_user_id  uuid := auth.uid();
    v_zone     text;
    v_start    date;
    v_today    date;
    v_previous integer;
    v_day      date;
    v_target   integer;
    v_consumed integer;
    v_burned   integer;
    v_closing  integer;
begin
    if v_user_id is null then
        raise exception 'recompute_balance requires an authenticated caller'
            using errcode = '28000';
    end if;

    select coalesce(time_zone, 'UTC') into v_zone
      from public.profiles where id = v_user_id;

    if v_zone is null then
        raise exception 'No profile row for user %', v_user_id using errcode = 'P0002';
    end if;

    v_today := (now() at time zone v_zone)::date;

    -- Default to the earliest day the user has any data for, or that the rollup
    -- has already scored. The stored days matter: taking an entry back has to
    -- unwind the day it was scored on, and a day whose last entry was deleted
    -- has no entry left to be found by the first two.
    v_start := coalesce(
        p_from_day,
        least(
            (select min((logged_at at time zone v_zone)::date) from public.food_log_entries where user_id = v_user_id),
            (select min((started_at at time zone v_zone)::date) from public.activity_entries where user_id = v_user_id),
            (select min(day) from public.balance_days where user_id = v_user_id)
        )
    );

    if v_start is null or v_start > v_today then
        return 0;
    end if;

    -- Carry in the balance as it stood the day before the rebuild starts.
    select closing_balance_kcal into v_previous
      from public.balance_days
     where user_id = v_user_id and day < v_start
     order by day desc
     limit 1;

    v_previous := coalesce(v_previous, 0);

    for v_day in select generate_series(v_start, v_today, interval '1 day')::date loop
        -- The target in force at the end of that day, so a goal edit does not
        -- retroactively rescore days that were lived under the old number.
        select g.daily_calorie_target into v_target
          from public.goal_sets g
         where g.user_id = v_user_id
           and (g.effective_from at time zone v_zone)::date <= v_day
           and (g.effective_to is null or (g.effective_to at time zone v_zone)::date > v_day)
         order by g.effective_from desc
         limit 1;

        -- Before the first goal set there is no target to score against.
        if v_target is null then
            continue;
        end if;

        -- Rounded once, here, and then used everywhere: what the row records is
        -- exactly what the balance was scored on.
        select round(coalesce(sum(calories), 0))::integer into v_consumed
          from public.food_log_entries
         where user_id = v_user_id and (logged_at at time zone v_zone)::date = v_day;

        select round(coalesce(sum(active_energy_kcal), 0))::integer into v_burned
          from public.activity_entries
         where user_id = v_user_id and (started_at at time zone v_zone)::date = v_day;

        v_closing := least(
            c_credit_cap,
            v_previous + v_burned - greatest(0, v_consumed - v_target)
        );

        insert into public.balance_days as b (
            user_id, day, daily_calorie_target, consumed_kcal, burned_kcal,
            closing_balance_kcal, recomputed_at
        )
        values (v_user_id, v_day, v_target, v_consumed, v_burned, v_closing, now())
        on conflict (user_id, day) do update
            set daily_calorie_target = excluded.daily_calorie_target,
                consumed_kcal        = excluded.consumed_kcal,
                burned_kcal          = excluded.burned_kcal,
                closing_balance_kcal = excluded.closing_balance_kcal,
                recomputed_at        = excluded.recomputed_at;

        v_previous := v_closing;
    end loop;

    return v_previous;
end;
$$;
