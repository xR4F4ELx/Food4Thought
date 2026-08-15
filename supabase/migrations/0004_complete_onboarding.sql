-- Atomic onboarding completion.
--
-- Finishing onboarding touches three tables: the profile gets its identity
-- fields, body_metrics gets the starting weight, and goal_sets gets the first
-- computed target set. Doing that as three client round trips means a failure
-- on the third leaves a user with a profile and no targets — onboarded by the
-- routing check, but with nothing to show on the dashboard. One function keeps
-- it in a single transaction.
--
-- Deliberately security invoker, not definer: every write below is already
-- permitted by the caller's own RLS policies, so there is nothing to elevate.
-- RLS stays as a second line of defence behind the explicit auth.uid() checks.
--
-- The same function serves later goal edits. It closes any open goal set before
-- opening a new one, so re-running it is safe and never trips
-- goal_sets_one_open_per_user. onboarding_completed_at is preserved once set,
-- so a goal edit in month six does not rewrite the original completion date.
--
-- Call it once per transaction. The closed and newly opened goal sets share a
-- single now() so history has no gap between them, which means a second call in
-- the same transaction would try to close a goal set at its own effective_from
-- and trip goal_sets_effective_range. Each client call is its own transaction,
-- so this only ever surfaces in tests.

create function public.complete_onboarding(
    p_birth_date           date,
    p_biological_sex       text,
    p_height_cm            numeric,
    p_weight_kg            numeric,
    p_meal_schedule        jsonb,
    p_goal_type            text,
    p_activity_level       text,
    -- Snapshotted from the client's TDEECalculator rather than recomputed here.
    -- See the note at the bottom of this file on why, and what it costs.
    p_bmr                  numeric,
    p_tdee                 numeric,
    p_bmi                  numeric,
    p_daily_calorie_target integer,
    p_protein_g_target     numeric,
    p_carbs_g_target       numeric,
    p_fat_g_target         numeric,
    p_display_name         text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_user_id      uuid := auth.uid();
    v_now          timestamptz := now();
    v_share_total  numeric;
    v_macro_kcal   numeric;
    v_goal_set_id  uuid;
begin
    if v_user_id is null then
        raise exception 'complete_onboarding requires an authenticated caller'
            using errcode = '28000';
    end if;

    -- Mifflin-St Jeor is not validated for children, and a calorie deficit is
    -- not something to hand an adolescent on the strength of a birth-date picker.
    if p_birth_date is null or p_birth_date > (current_date - interval '13 years') then
        raise exception 'Users must be at least 13 years old'
            using errcode = '22023';
    end if;

    if p_birth_date < (current_date - interval '120 years') then
        raise exception 'Birth date is implausible'
            using errcode = '22023';
    end if;

    if jsonb_typeof(p_meal_schedule) <> 'array' or jsonb_array_length(p_meal_schedule) = 0 then
        raise exception 'Meal schedule must be a non-empty array'
            using errcode = '22023';
    end if;

    -- expected_share drives the pace curve on the dashboard; shares that do not
    -- sum to 1.0 silently skew every "are you on track" readout for the life of
    -- the account. MealSchedule.normalised() should have run client-side, so a
    -- failure here means a bug, not bad user input.
    select coalesce(sum((slot ->> 'expected_share')::numeric), 0)
      into v_share_total
      from jsonb_array_elements(p_meal_schedule) as slot;

    if abs(v_share_total - 1.0) > 0.01 then
        raise exception 'Meal schedule shares must sum to 1.0 (got %)', v_share_total
            using errcode = '22023';
    end if;

    -- TDEECalculator.macroTargets reconciles exactly to the calorie target at
    -- every input, including where the protein and fat floors collide at very
    -- high body weight. So anything beyond storage rounding here is a client
    -- bug, and a dashboard whose macro rings contradict its own headline number
    -- is worth failing loudly over. 25 kcal is generous: an integer calorie
    -- target plus three numeric(6,2) macros cannot drift past 1 kcal.
    v_macro_kcal := p_protein_g_target * 4 + p_carbs_g_target * 4 + p_fat_g_target * 9;

    if abs(v_macro_kcal - p_daily_calorie_target) > 25 then
        raise exception 'Macro targets (% kcal) do not reconcile with calorie target (%)',
            round(v_macro_kcal), p_daily_calorie_target
            using errcode = '22023';
    end if;

    -- Serialises concurrent calls (double-tapped Finish, or a retry racing the
    -- original) so only one can be between closing and opening a goal set.
    perform 1 from public.profiles where id = v_user_id for update;

    update public.profiles
       set display_name            = coalesce(p_display_name, display_name),
           birth_date              = p_birth_date,
           biological_sex          = p_biological_sex,
           height_cm               = p_height_cm,
           meal_schedule           = p_meal_schedule,
           onboarding_completed_at = coalesce(onboarding_completed_at, v_now)
     where id = v_user_id;

    if not found then
        -- handle_new_user() should have created this at signup; if it is missing
        -- the account is in a state no amount of client retrying will fix.
        raise exception 'No profile row for user %', v_user_id
            using errcode = 'P0002';
    end if;

    insert into public.body_metrics (user_id, recorded_at, weight_kg, height_cm, source)
    values (v_user_id, v_now, p_weight_kg, p_height_cm, 'manual');

    update public.goal_sets
       set effective_to = v_now
     where user_id = v_user_id
       and effective_to is null;

    insert into public.goal_sets (
        user_id, goal_type, activity_level,
        bmr, tdee, bmi,
        daily_calorie_target, protein_g_target, carbs_g_target, fat_g_target,
        effective_from
    )
    values (
        v_user_id, p_goal_type, p_activity_level,
        p_bmr, p_tdee, p_bmi,
        p_daily_calorie_target, p_protein_g_target, p_carbs_g_target, p_fat_g_target,
        v_now
    )
    returning id into v_goal_set_id;

    return v_goal_set_id;
end;
$$;

comment on function public.complete_onboarding is
    'Atomically writes profile identity, starting weight, and the first goal set. '
    'Also serves later goal edits: closes any open goal set before opening a new one.';

revoke all on function public.complete_onboarding from public, anon;
grant execute on function public.complete_onboarding to authenticated;


-- On snapshotting client-computed targets rather than recomputing them here:
--
-- The alternative is porting Mifflin-St Jeor, the activity multipliers, the
-- calorie floor, and the macro split into plpgsql — a second implementation of
-- logic that already has unit tests in Food4ThoughtCore, free to drift from the
-- Swift one on any future edit. With a single first-party client, the drift risk
-- is the larger one, so the client stays authoritative and this function
-- validates rather than recalculates.
--
-- Revisit if a second client (web, Android, a server-side recalculation job)
-- ever needs to produce targets. At that point the math belongs in one place,
-- and this is the place.
