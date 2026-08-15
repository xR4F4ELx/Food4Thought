-- pgTAP coverage for public.recompute_balance.
--
-- The balance is the one number in the app that is path-dependent: the credit
-- cap means the order days are applied changes the answer, so no aggregate
-- query can check the function's work. Everything below is therefore a chain —
-- a sequence of days whose closing balances are only right if every earlier day
-- was right too.
--
-- Rules under test, from docs/design/handoff.md "The balance model":
--   * accrues from daily overage only; a deficit day adds nothing
--   * burn pays down debt first, remainder becomes credit
--   * credit caps at +500, and burn past the cap is dropped, not banked
--   * debt rolls indefinitely, with no floor
--   * a rebuild from a mid-history day carries in the prior day's close
--   * the target is the one in force at the END of each day, so a goal edit
--     never retroactively rescores days lived under the old number
--   * days are the user's own days, per profiles.time_zone, not UTC
--
-- Run with: supabase test db

begin;

create extension if not exists pgtap with schema extensions;

select plan(35);


-- ----------------------------------------------------------------- helpers --

-- Every timestamp in this file is derived from the same frozen now(), so the
-- fixtures and the function's own notion of "today" can never disagree — even
-- if the suite runs a millisecond before midnight.
create function pg_temp.local_day(p_offset int, p_zone text default 'UTC')
returns date language sql stable as $$
    select (now() at time zone p_zone)::date + p_offset
$$;

-- An instant, specified by the wall clock the user would have seen. Building
-- fixtures this way is what makes the timezone cases legible: "01:00 on their
-- Tuesday" is the intent, and which UTC day that lands on is the point.
create function pg_temp.local_at(p_offset int, p_time time, p_zone text default 'UTC')
returns timestamptz language sql stable as $$
    select ((now() at time zone p_zone)::date + p_offset + p_time) at time zone p_zone
$$;

-- Both claim forms deliberately: auth.uid() reads the singular
-- request.jwt.claim.sub in the local CLI image but the request.jwt.claims JSON
-- on hosted Supabase. Setting only one makes this file pass in one environment
-- and fail in the other.
create function pg_temp.become(p_user_id uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', p_user_id::text, true);
    perform set_config(
        'request.jwt.claims',
        json_build_object('sub', p_user_id, 'role', 'authenticated')::text,
        true
    );
end;
$$;

create function pg_temp.new_user(p_user_id uuid, p_zone text default 'UTC')
returns void language plpgsql as $$
begin
    -- The on_auth_user_created trigger creates the profile row, so this
    -- exercises that path rather than inserting a profile by hand.
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
    values (
        '00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
        'balance-' || left(p_user_id::text, 8) || '@example.com', 'not-a-real-hash', now(), now()
    );

    update public.profiles set time_zone = p_zone where id = p_user_id;
end;
$$;

create function pg_temp.set_goal(
    p_user_id uuid, p_target integer, p_from timestamptz, p_to timestamptz default null
) returns void language sql as $$
    insert into public.goal_sets (
        user_id, goal_type, activity_level, bmr, tdee, daily_calorie_target,
        protein_g_target, carbs_g_target, fat_g_target, effective_from, effective_to
    )
    values (
        p_user_id, 'maintain', 'moderately_active', 1805, 2797.75, p_target,
        144, 380.58, 77.72, p_from, p_to
    );
$$;

create function pg_temp.log_food(p_user_id uuid, p_at timestamptz, p_kcal numeric)
returns void language sql as $$
    insert into public.food_log_entries (
        user_id, food_item_id, logged_at, meal_key, quantity, calories, protein_g, carbs_g, fat_g
    )
    values (
        p_user_id, '99999999-9999-9999-9999-999999999999', p_at, 'lunch', 1, p_kcal, 0, 0, 0
    );
$$;

create function pg_temp.log_activity(p_user_id uuid, p_at timestamptz, p_kcal numeric)
returns void language sql as $$
    insert into public.activity_entries (user_id, source, started_at, active_energy_kcal)
    values (p_user_id, 'manual', p_at, p_kcal);
$$;

-- Reads back a single day for the *current* caller, so every assertion goes
-- through the same RLS the client does.
create function pg_temp.closing(p_offset int, p_zone text default 'UTC')
returns integer language sql stable as $$
    select closing_balance_kcal from public.balance_days
     where user_id = auth.uid() and day = pg_temp.local_day(p_offset, p_zone)
$$;


-- ---------------------------------------------------------------- fixtures --

-- One shared catalogue row; the log entries snapshot their own calories, so its
-- nutrition is irrelevant to everything below.
insert into public.food_items (id, source, external_id, name, calories)
values ('99999999-9999-9999-9999-999999999999', 'usda_fdc', 'balance-test-food', 'Test food', 100);

-- U1 · the main chain: accrual, deficit, paydown, credit, cap, cap-drop.
select pg_temp.new_user('11111111-1111-1111-1111-111111111111');
select pg_temp.set_goal('11111111-1111-1111-1111-111111111111', 2000, pg_temp.local_at(-30, '00:00'));
select pg_temp.log_food('11111111-1111-1111-1111-111111111111', pg_temp.local_at(-6, '12:00'), 2500);
select pg_temp.log_food('11111111-1111-1111-1111-111111111111', pg_temp.local_at(-5, '12:00'), 1200);
select pg_temp.log_activity('11111111-1111-1111-1111-111111111111', pg_temp.local_at(-4, '18:00'), 300);
select pg_temp.log_activity('11111111-1111-1111-1111-111111111111', pg_temp.local_at(-3, '18:00'), 400);
select pg_temp.log_activity('11111111-1111-1111-1111-111111111111', pg_temp.local_at(-2, '18:00'), 560);
select pg_temp.log_food('11111111-1111-1111-1111-111111111111', pg_temp.local_at(0, '09:00'), 2300);

-- U6 · a day that gets taken back after it has been scored.
select pg_temp.new_user('66666666-6666-6666-6666-666666666666');
select pg_temp.set_goal('66666666-6666-6666-6666-666666666666', 2000, pg_temp.local_at(-30, '00:00'));
select pg_temp.log_food('66666666-6666-6666-6666-666666666666', pg_temp.local_at(-3, '12:00'), 2600);
select pg_temp.log_food('66666666-6666-6666-6666-666666666666', pg_temp.local_at(-2, '12:00'), 2600);

-- U2 · timezone. UTC+14 year round, so no DST rule can rescue a UTC-bucketed
-- implementation by accident.
select pg_temp.new_user('22222222-2222-2222-2222-222222222222', 'Pacific/Kiritimati');
select pg_temp.set_goal('22222222-2222-2222-2222-222222222222', 2000,
                        pg_temp.local_at(-30, '00:00', 'Pacific/Kiritimati'));
-- Anchors the rebuild's start day; nothing else depends on it.
select pg_temp.log_food('22222222-2222-2222-2222-222222222222',
                        pg_temp.local_at(-4, '12:00', 'Pacific/Kiritimati'), 1000);
-- 01:00 local is still the previous day in UTC. Bucketed by UTC these two land
-- a day early, on days the user had not started living yet.
select pg_temp.log_food('22222222-2222-2222-2222-222222222222',
                        pg_temp.local_at(-2, '01:00', 'Pacific/Kiritimati'), 2500);
select pg_temp.log_activity('22222222-2222-2222-2222-222222222222',
                            pg_temp.local_at(-1, '01:00', 'Pacific/Kiritimati'), 300);

-- U3 · debt with no floor: three heavy days in a row.
select pg_temp.new_user('33333333-3333-3333-3333-333333333333');
select pg_temp.set_goal('33333333-3333-3333-3333-333333333333', 2000, pg_temp.local_at(-30, '00:00'));
select pg_temp.log_food('33333333-3333-3333-3333-333333333333', pg_temp.local_at(-3, '12:00'), 3200);
select pg_temp.log_food('33333333-3333-3333-3333-333333333333', pg_temp.local_at(-2, '12:00'), 3200);
select pg_temp.log_food('33333333-3333-3333-3333-333333333333', pg_temp.local_at(-1, '12:00'), 3200);

-- U4 · a late correction to a past day, rebuilt from that day only.
select pg_temp.new_user('44444444-4444-4444-4444-444444444444');
select pg_temp.set_goal('44444444-4444-4444-4444-444444444444', 2000, pg_temp.local_at(-30, '00:00'));
select pg_temp.log_food('44444444-4444-4444-4444-444444444444', pg_temp.local_at(-4, '12:00'), 2300);
select pg_temp.log_food('44444444-4444-4444-4444-444444444444', pg_temp.local_at(-3, '12:00'), 2200);
select pg_temp.log_activity('44444444-4444-4444-4444-444444444444', pg_temp.local_at(-2, '18:00'), 100);

-- U5 · a goal edit two days ago: 2000 before it, 1500 from it.
select pg_temp.new_user('55555555-5555-5555-5555-555555555555');
select pg_temp.set_goal('55555555-5555-5555-5555-555555555555', 2000,
                        pg_temp.local_at(-30, '00:00'), pg_temp.local_at(-2, '12:00'));
select pg_temp.set_goal('55555555-5555-5555-5555-555555555555', 1500, pg_temp.local_at(-2, '12:00'));
select pg_temp.log_food('55555555-5555-5555-5555-555555555555', pg_temp.local_at(-4, '12:00'), 2200);
select pg_temp.log_food('55555555-5555-5555-5555-555555555555', pg_temp.local_at(-1, '12:00'), 1700);


-- --------------------------------------------------------- unauthenticated --

-- Runs before any jwt claim is set, so auth.uid() is genuinely null.
select throws_ok(
    $$ select public.recompute_balance() $$,
    '28000',
    'recompute_balance requires an authenticated caller',
    'refuses to run without an authenticated caller'
);


set local role authenticated;


-- ------------------------------------------------------------- U1 · chain --

select pg_temp.become('11111111-1111-1111-1111-111111111111');

select lives_ok(
    $$ select public.recompute_balance() $$,
    'rebuilds the whole history for an authenticated caller'
);

select is(pg_temp.closing(-6), -500,
    'a 500 kcal overage becomes 500 kcal of debt');

select is(
    (select overage_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-6)),
    500.00::numeric,
    'the day stores the overage it was scored on');

select is(pg_temp.closing(-5), -500,
    'eating 800 under target earns nothing — the debt is unchanged');

select is(
    (select overage_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-5)),
    0.00::numeric,
    'a deficit day records zero overage rather than a negative one');

select is(pg_temp.closing(-4), -200,
    'burn pays down debt first: 300 burned against 500 owed leaves 200 owed');

select is(pg_temp.closing(-3), 200,
    'burn past the debt becomes credit: 400 against 200 owed leaves +200');

select is(pg_temp.closing(-2), 500,
    'credit is capped at +500, not the +760 the raw arithmetic gives');

select is(
    (select burned_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-2)),
    560.00::numeric,
    'the day still records the full burn, so the cap stays explainable');

select is(pg_temp.closing(-1), 500,
    'a quiet day neither adds nor decays credit');

-- The one that distinguishes a cap from a ceiling: if the 60 kcal over the cap
-- had been banked, today would close at 460.
select is(pg_temp.closing(0), 200,
    'burn past the cap is dropped, not banked — a 300 overage lands on +500, not +760');

select is(
    (select public.recompute_balance()),
    200,
    'returns the current balance');

select is(
    (select public.recompute_balance()),
    200,
    'is idempotent: a retry after a dropped connection changes nothing');

-- The cap is the reason balance_days exists at all: it makes the balance
-- path-dependent, so no aggregate query can reproduce it. A cap the caller
-- passes in is a default, not a rule — and this function is reachable straight
-- from PostgREST by any signed-in user.
select throws_ok(
    $$ select public.recompute_balance(null::date, 100000) $$,
    '42883',
    'function public.recompute_balance(date, integer) does not exist',
    'the credit cap is fixed by the function, not chosen by the caller');


-- --------------------------------------------------- U3 · debt has no floor --

select pg_temp.become('33333333-3333-3333-3333-333333333333');

select is(
    (select public.recompute_balance()),
    -3600,
    'debt rolls indefinitely: three 1200 kcal overages compound to -3600');

select is(pg_temp.closing(-1), -3600,
    'nothing clamps or resets the debt along the way');


-- ------------------------------------------- U4 · rebuild from a past day --

select pg_temp.become('44444444-4444-4444-4444-444444444444');

select is(
    (select public.recompute_balance()),
    -400,
    'establishes the baseline: -300, then -500, then 100 burned back');

-- The realistic trigger: a meal remembered two days late.
select pg_temp.log_food('44444444-4444-4444-4444-444444444444', pg_temp.local_at(-3, '20:00'), 100);

select is(
    (select public.recompute_balance(pg_temp.local_day(-3))),
    -500,
    'a partial rebuild returns the current balance, not just the day it started from');

select is(pg_temp.closing(-4), -300,
    'days before the rebuild window are left alone');

select is(pg_temp.closing(-3), -600,
    'the rebuild carries in the prior day''s close rather than starting from zero');


-- ------------------------------------------------------- U5 · goal edits --

select pg_temp.become('55555555-5555-5555-5555-555555555555');

select lives_ok(
    $$ select public.recompute_balance() $$,
    'rebuilds across a goal change');

select is(
    (select daily_calorie_target from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-4)),
    2000,
    'a day lived before the edit keeps the target it was lived under');

select is(pg_temp.closing(-4), -200,
    'so it is scored at 200 over, not the 700 the new target would imply');

select is(
    (select daily_calorie_target from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-2)),
    1500,
    'the day of the edit uses the target in force at its end');

select is(pg_temp.closing(-1), -400,
    'days after the edit are scored against the new target');


-- ------------------------------------------------ U6 · entries taken back --

-- Undoing a mis-logged meal is a first-class flow, not an edge case. The
-- rollup is a cache of the entries, so removing the entries has to unwind the
-- days they were scored on — otherwise the stored history and the number the
-- function returns disagree, and the ring shows one while Trends shows the other.
select pg_temp.become('66666666-6666-6666-6666-666666666666');

select is(
    (select public.recompute_balance()),
    -1200,
    'establishes the baseline: two 600 kcal overages');

delete from public.food_log_entries where user_id = auth.uid();

select is(
    (select public.recompute_balance()),
    0,
    'deleting the entries returns the balance they created');

select is(pg_temp.closing(-3), 0,
    'and unwinds the stored day rather than leaving it behind');

select is(
    (select consumed_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-3)),
    0.00::numeric,
    'the rollup stays a cache of the entries, never a record of its own');


-- ---------------------------------------------------------- U2 · timezone --

select pg_temp.become('22222222-2222-2222-2222-222222222222');

select lives_ok(
    $$ select public.recompute_balance() $$,
    'rebuilds for a user whose day boundary is not UTC midnight');

select is(
    (select consumed_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-2, 'Pacific/Kiritimati')),
    2500.00::numeric,
    'a 01:00 meal counts on the user''s day, not the UTC day it fell in');

select is(
    (select consumed_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-3, 'Pacific/Kiritimati')),
    0.00::numeric,
    'and does not leak onto the previous day, where UTC bucketing would put it');

select is(
    (select burned_kcal from public.balance_days
      where user_id = auth.uid() and day = pg_temp.local_day(-1, 'Pacific/Kiritimati')),
    300.00::numeric,
    'activity is bucketed by the same boundary as food');

select is(pg_temp.closing(-1, 'Pacific/Kiritimati'), -200,
    'and the two land on the days that make the running balance right');


select * from finish();
rollback;
