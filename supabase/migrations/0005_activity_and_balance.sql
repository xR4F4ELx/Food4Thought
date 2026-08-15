-- Activity tracking and the calorie balance (debt/credit) mechanic.
--
-- The balance is a single signed kcal figure per user:
--   negative = debt owed (ate over, not yet burned back)
--   zero     = square
--   positive = credit (burned more than owed)
--
-- Rules it has to honour, from docs/design/handoff.md:
--   * accrues from daily overage only — eating under target earns nothing
--   * cleared and built by active energy; debt is paid down first
--   * rolls indefinitely, never auto-resets
--   * credit is capped, and burn past the cap is dropped rather than banked,
--     because it is already reflected in the weight trend
--   * exercise never inflates the day's food target; habitual activity is
--     already priced into TDEE through activity_level
--
-- The cap is what forces a stored daily rollup rather than a derived sum: it
-- makes the balance path-dependent, so the order days are applied in changes
-- the answer and no single aggregate query can reproduce it.


-- Daily rollups need a day boundary, and "day" is only meaningful in the
-- user's own timezone. Defaulting to UTC keeps existing rows valid; the client
-- sets the real IANA name.
alter table public.profiles
    add column time_zone text not null default 'UTC';


create table public.activity_entries (
    id                 uuid primary key default gen_random_uuid(),
    user_id            uuid not null references auth.users (id) on delete cascade,
    source             text not null check (source in ('healthkit', 'manual')),
    -- HealthKit's own UUID, so a re-sync updates rather than duplicates.
    external_id        text,
    -- Free text rather than an enum: HealthKit's workout taxonomy is long and
    -- changes between OS releases, and nothing here branches on the value.
    activity_type      text,
    started_at         timestamptz not null,
    ended_at           timestamptz,
    -- Always an estimate, and labelled as one wherever it is shown.
    active_energy_kcal numeric(7, 2) not null check (active_energy_kcal >= 0),
    created_at         timestamptz not null default now(),
    constraint activity_entries_time_range check (ended_at is null or ended_at >= started_at),
    constraint activity_entries_healthkit_has_external_id
        check (source <> 'healthkit' or external_id is not null)
);

create unique index activity_entries_source_external_idx
    on public.activity_entries (user_id, source, external_id) where external_id is not null;

create index activity_entries_user_started_idx
    on public.activity_entries (user_id, started_at desc);

alter table public.activity_entries enable row level security;

create policy "Users manage their own activity"
    on public.activity_entries for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- One row per day the user has any data for. Every figure is snapshotted so a
-- past day stays explainable after targets change, matching how goal_sets and
-- food_log_entries already treat history.
create table public.balance_days (
    user_id              uuid not null references auth.users (id) on delete cascade,
    day                  date not null,
    daily_calorie_target integer not null check (daily_calorie_target > 0),
    consumed_kcal        numeric(8, 2) not null default 0 check (consumed_kcal >= 0),
    burned_kcal          numeric(8, 2) not null default 0 check (burned_kcal >= 0),
    -- Only eating over contributes; a deficit day adds nothing to the balance.
    overage_kcal         numeric(8, 2) not null
                             generated always as (greatest(0, consumed_kcal - daily_calorie_target)) stored,
    -- Signed, and the value the UI reads. Bounded above by the credit cap and
    -- unbounded below, so debt can roll indefinitely.
    closing_balance_kcal integer not null,
    recomputed_at        timestamptz not null default now(),
    primary key (user_id, day)
);

alter table public.balance_days enable row level security;

create policy "Users read their own balance history"
    on public.balance_days for select using (auth.uid() = user_id);

create policy "Users write their own balance history"
    on public.balance_days for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- Rebuilds the rollup forward from a day, which is the only correct way to
-- apply a cap that depends on the running total. Call it after anything that
-- changes a past day: a food entry, a workout sync, or a goal edit.
--
-- Idempotent, so a retry after a dropped connection is safe.
create function public.recompute_balance(
    p_from_day date default null
)
returns integer
language plpgsql
security invoker
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
    v_consumed numeric;
    v_burned   numeric;
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

        select coalesce(sum(calories), 0) into v_consumed
          from public.food_log_entries
         where user_id = v_user_id and (logged_at at time zone v_zone)::date = v_day;

        select coalesce(sum(active_energy_kcal), 0) into v_burned
          from public.activity_entries
         where user_id = v_user_id and (started_at at time zone v_zone)::date = v_day;

        v_closing := least(
            c_credit_cap,
            v_previous + round(v_burned)::integer - greatest(0, round(v_consumed)::integer - v_target)
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

comment on function public.recompute_balance is
    'Rebuilds balance_days forward from a day and returns the current balance. '
    'Call after any change to a past day: food entry, workout sync, or goal edit.';

revoke all on function public.recompute_balance from public, anon;
grant execute on function public.recompute_balance to authenticated;
