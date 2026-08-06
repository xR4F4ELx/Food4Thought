-- Body metrics history and history-preserving goal sets.
-- Editing goals inserts a new goal_sets row and closes the previous one, so the
-- dashboard can always answer "what were my targets on that date".

create table public.body_metrics (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    recorded_at timestamptz not null default now(),
    weight_kg   numeric(5, 2) not null check (weight_kg > 0),
    height_cm   numeric(5, 2) check (height_cm > 0),
    source      text not null default 'manual' check (source in ('manual', 'healthkit')),
    created_at  timestamptz not null default now()
);

create index body_metrics_user_recorded_idx
    on public.body_metrics (user_id, recorded_at desc);

alter table public.body_metrics enable row level security;

create policy "Users read their own body metrics"
    on public.body_metrics for select using (auth.uid() = user_id);

create policy "Users insert their own body metrics"
    on public.body_metrics for insert with check (auth.uid() = user_id);

create policy "Users update their own body metrics"
    on public.body_metrics for update
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users delete their own body metrics"
    on public.body_metrics for delete using (auth.uid() = user_id);


create table public.goal_sets (
    id                   uuid primary key default gen_random_uuid(),
    user_id              uuid not null references auth.users (id) on delete cascade,
    goal_type            text not null check (
                             goal_type in ('lose_weight', 'cut', 'maintain', 'lean_bulk', 'gain_weight')),
    activity_level       text not null check (
                             activity_level in ('sedentary', 'lightly_active', 'moderately_active',
                                                'very_active', 'extremely_active')),
    -- Snapshotted at calc time so historical targets stay explainable.
    bmr                  numeric(7, 2) not null check (bmr > 0),
    tdee                 numeric(7, 2) not null check (tdee > 0),
    bmi                  numeric(5, 2),
    daily_calorie_target integer not null check (daily_calorie_target > 0),
    protein_g_target     numeric(6, 2) not null check (protein_g_target >= 0),
    carbs_g_target       numeric(6, 2) not null check (carbs_g_target >= 0),
    fat_g_target         numeric(6, 2) not null check (fat_g_target >= 0),
    effective_from       timestamptz not null default now(),
    effective_to         timestamptz,
    created_at           timestamptz not null default now(),
    constraint goal_sets_effective_range check (effective_to is null or effective_to > effective_from)
);

-- At most one open goal set per user; closing a row means setting effective_to.
create unique index goal_sets_one_open_per_user
    on public.goal_sets (user_id) where effective_to is null;

create index goal_sets_user_effective_idx
    on public.goal_sets (user_id, effective_from desc);

alter table public.goal_sets enable row level security;

create policy "Users read their own goal sets"
    on public.goal_sets for select using (auth.uid() = user_id);

create policy "Users insert their own goal sets"
    on public.goal_sets for insert with check (auth.uid() = user_id);

create policy "Users update their own goal sets"
    on public.goal_sets for update
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
