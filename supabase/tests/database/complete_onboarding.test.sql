-- pgTAP coverage for public.complete_onboarding.
--
-- The function is the only multi-table write in the app, so what matters here
-- is less "does it write the right values" than "does it refuse to write a
-- half-finished account" — hence the emphasis on validation and on re-running
-- it, which is both the retry path and the later goal-edit path.
--
-- Run with: supabase test db

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);


-- ---------------------------------------------------------------- fixtures --

-- The on_auth_user_created trigger creates the profile row, so this fixture
-- exercises that path too rather than inserting a profile by hand.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated',
    'authenticated',
    'onboarding-test@example.com',
    'not-a-real-hash',
    now(),
    now()
);

create function pg_temp.meal_schedule() returns jsonb language sql immutable as $$
    select '[
        {"key": "breakfast", "label": "Breakfast", "typical_time": "08:00", "expected_share": 0.30},
        {"key": "lunch",     "label": "Lunch",     "typical_time": "12:30", "expected_share": 0.30},
        {"key": "dinner",    "label": "Dinner",    "typical_time": "19:00", "expected_share": 0.40}
    ]'::jsonb
$$;


-- --------------------------------------------------------- unauthenticated --

-- Runs before any jwt claim is set, so auth.uid() is genuinely null.
select throws_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80, pg_temp.meal_schedule(),
        'maintain', 'moderately_active',
        1805, 2797.75, 24.69, 2798, 144, 380.58, 77.72
    ) $$,
    '28000',
    'complete_onboarding requires an authenticated caller',
    'refuses to run without an authenticated caller'
);


-- Both forms deliberately: auth.uid() reads the singular request.jwt.claim.sub
-- in the local CLI image but the request.jwt.claims JSON on hosted Supabase.
-- Setting only one makes this file pass in one environment and fail in the other.
set local role authenticated;
set local request.jwt.claim.sub to '11111111-1111-1111-1111-111111111111';
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';


-- ------------------------------------------------------------- happy path --

-- Values mirror the Swift maintainSplit test: 25yo male, 80kg, 180cm,
-- moderately active. Macros total 2797.8 kcal against a 2798 target.
select lives_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80, pg_temp.meal_schedule(),
        'maintain', 'moderately_active',
        1805, 2797.75, 24.69, 2798, 144, 380.58, 77.72
    ) $$,
    'completes onboarding for an authenticated user'
);

select is(
    (select birth_date from public.profiles where id = auth.uid()),
    '1990-01-01'::date,
    'stores birth date on the profile'
);

select is(
    (select biological_sex from public.profiles where id = auth.uid()),
    'male',
    'stores biological sex on the profile'
);

select is(
    (select height_cm from public.profiles where id = auth.uid()),
    180.00::numeric,
    'stores height on the profile'
);

select ok(
    (select onboarding_completed_at is not null from public.profiles where id = auth.uid()),
    'stamps onboarding_completed_at, which is what routing reads'
);

select is(
    (select jsonb_array_length(meal_schedule) from public.profiles where id = auth.uid()),
    3,
    'stores the meal schedule as a jsonb array'
);

select is(
    (select count(*) from public.body_metrics where user_id = auth.uid()),
    1::bigint,
    'records exactly one starting weight'
);

select is(
    (select weight_kg from public.body_metrics where user_id = auth.uid()),
    80.00::numeric,
    'records the starting weight passed in'
);

select is(
    (select count(*) from public.goal_sets where user_id = auth.uid() and effective_to is null),
    1::bigint,
    'opens exactly one goal set'
);

select is(
    (select daily_calorie_target from public.goal_sets where user_id = auth.uid() and effective_to is null),
    2798,
    'snapshots the calorie target on the goal set'
);


-- ------------------------------------------------------------- validation --

-- Each of these must abort before writing anything; the goal-set counts at the
-- end of the file are what prove they did.

select throws_ok(
    format(
        $$ select public.complete_onboarding(
            %L::date, 'male', 180, 80, pg_temp.meal_schedule(),
            'maintain', 'moderately_active',
            1805, 2797.75, 24.69, 2798, 144, 380.58, 77.72
        ) $$,
        current_date - interval '10 years'
    ),
    '22023',
    'Users must be at least 13 years old',
    'rejects a caller under 13, where Mifflin-St Jeor is not validated'
);

select throws_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80,
        '[{"key": "a", "label": "A", "typical_time": "08:00", "expected_share": 0.5},
          {"key": "b", "label": "B", "typical_time": "18:00", "expected_share": 0.3}]'::jsonb,
        'maintain', 'moderately_active',
        1805, 2797.75, 24.69, 2798, 144, 380.58, 77.72
    ) $$,
    '22023',
    'Meal schedule shares must sum to 1.0 (got 0.8)',
    'rejects meal shares that do not sum to 1.0, which would skew every pace readout'
);

select throws_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80, pg_temp.meal_schedule(),
        'maintain', 'moderately_active',
        1805, 2797.75, 24.69, 2798, 144, 100.00, 77.72
    ) $$,
    '22023',
    'Macro targets (1675 kcal) do not reconcile with calorie target (2798)',
    'rejects macros that do not reconcile with the calorie target'
);

select throws_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80, '[]'::jsonb,
        'maintain', 'moderately_active',
        1805, 2797.75, 24.69, 2798, 144, 380.58, 77.72
    ) $$,
    '22023',
    'Meal schedule must be a non-empty array',
    'rejects an empty meal schedule'
);


-- ------------------------------------- re-run: retry and goal-edit path --

reset role;

create temporary table onboarding_stamp as
    select onboarding_completed_at from public.profiles
     where id = '11111111-1111-1111-1111-111111111111';

-- Created as postgres but read back after switching to authenticated.
grant select on onboarding_stamp to authenticated;

-- Backdate the first goal set so it looks like it came from an earlier session,
-- which is the only way this path ever happens in production. now() is the
-- transaction timestamp, so without this the new goal set's effective_from
-- would equal the old one's effective_to and trip goal_sets_effective_range —
-- an artifact of pgTAP running every test in a single transaction, not a
-- reachable state through the client.
update public.goal_sets
   set effective_from = now() - interval '1 day'
 where user_id = '11111111-1111-1111-1111-111111111111';

set local role authenticated;

-- Same person switching to a cut: target 2238, macros total 2238.21.
select lives_ok(
    $$ select public.complete_onboarding(
        '1990-01-01'::date, 'male', 180, 80, pg_temp.meal_schedule(),
        'cut', 'moderately_active',
        1805, 2797.75, 24.69, 2238, 176, 243.67, 62.17
    ) $$,
    're-runs cleanly, serving both the retry path and later goal edits'
);

select is(
    (select count(*) from public.goal_sets where user_id = auth.uid()),
    2::bigint,
    'keeps the superseded goal set for history rather than overwriting it'
);

select is(
    (select count(*) from public.goal_sets where user_id = auth.uid() and effective_to is null),
    1::bigint,
    'leaves exactly one open goal set, as goal_sets_one_open_per_user requires'
);

select is(
    (select goal_type from public.goal_sets where user_id = auth.uid() and effective_to is null),
    'cut',
    'the open goal set is the new one'
);

select is(
    (select onboarding_completed_at from public.profiles where id = auth.uid()),
    (select onboarding_completed_at from onboarding_stamp),
    'a later goal edit does not rewrite the original completion date'
);


select * from finish();
rollback;
