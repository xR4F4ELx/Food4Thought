-- Food catalogue, log entries, and favourites.
-- USDA-sourced rows are a shared cache readable by every authenticated user;
-- user_custom rows are private to their creator.

create extension if not exists pg_trgm;

create table public.food_items (
    id              uuid primary key default gen_random_uuid(),
    source          text not null check (source in ('usda_fdc', 'user_custom')),
    external_id     text,
    created_by      uuid references auth.users (id) on delete cascade,
    name            text not null check (length(trim(name)) > 0),
    brand           text,
    serving_size    numeric(8, 2) check (serving_size > 0),
    serving_unit    text,
    calories        numeric(8, 2) not null default 0 check (calories >= 0),
    protein_g       numeric(8, 2) not null default 0 check (protein_g >= 0),
    carbs_g         numeric(8, 2) not null default 0 check (carbs_g >= 0),
    fat_g           numeric(8, 2) not null default 0 check (fat_g >= 0),
    fiber_g         numeric(8, 2) check (fiber_g >= 0),
    sugar_g         numeric(8, 2) check (sugar_g >= 0),
    sodium_mg       numeric(8, 2) check (sodium_mg >= 0),
    -- Long tail of USDA nutrient codes, e.g. {"208": 250.0, "203": 12.5}.
    -- jsonb avoids a migration every time a new micronutrient matters.
    micronutrients  jsonb not null default '{}'::jsonb,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    constraint food_items_custom_has_owner check (source <> 'user_custom' or created_by is not null),
    constraint food_items_usda_has_external_id check (source <> 'usda_fdc' or external_id is not null)
);

create unique index food_items_source_external_idx
    on public.food_items (source, external_id) where external_id is not null;

-- Local search so repeat lookups hit Supabase instead of round-tripping to USDA.
create index food_items_search_idx on public.food_items
    using gin ((name || ' ' || coalesce(brand, '')) gin_trgm_ops);

create trigger food_items_set_updated_at
    before update on public.food_items
    for each row execute function public.set_updated_at();

alter table public.food_items enable row level security;

create policy "Anyone reads USDA foods; users read their own custom foods"
    on public.food_items for select
    to authenticated
    using (source = 'usda_fdc' or created_by = auth.uid());

create policy "Users cache USDA foods and create their own"
    on public.food_items for insert
    to authenticated
    with check (source = 'usda_fdc' or created_by = auth.uid());

create policy "Users edit only their own custom foods"
    on public.food_items for update
    using (created_by = auth.uid()) with check (created_by = auth.uid());

create policy "Users delete only their own custom foods"
    on public.food_items for delete using (created_by = auth.uid());


create table public.food_log_entries (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null references auth.users (id) on delete cascade,
    food_item_id   uuid not null references public.food_items (id) on delete restrict,
    logged_at      timestamptz not null default now(),
    -- Matches a `key` from profiles.meal_schedule — deliberately not a fixed
    -- breakfast/lunch/dinner constraint, so OMAD and custom routines fit.
    meal_key       text not null,
    quantity       numeric(8, 2) not null check (quantity > 0),
    -- Snapshotted at log time: correcting a cached food_items row must never
    -- silently rewrite history.
    calories       numeric(8, 2) not null check (calories >= 0),
    protein_g      numeric(8, 2) not null check (protein_g >= 0),
    carbs_g        numeric(8, 2) not null check (carbs_g >= 0),
    fat_g          numeric(8, 2) not null check (fat_g >= 0),
    micronutrients jsonb not null default '{}'::jsonb,
    created_at     timestamptz not null default now()
);

create index food_log_entries_user_logged_idx
    on public.food_log_entries (user_id, logged_at desc);

alter table public.food_log_entries enable row level security;

create policy "Users read their own log entries"
    on public.food_log_entries for select using (auth.uid() = user_id);

create policy "Users insert their own log entries"
    on public.food_log_entries for insert with check (auth.uid() = user_id);

create policy "Users update their own log entries"
    on public.food_log_entries for update
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users delete their own log entries"
    on public.food_log_entries for delete using (auth.uid() = user_id);


-- Favourites power the one-tap repeat flow, the highest-leverage anti-tedium feature.
create table public.food_favorites (
    user_id      uuid not null references auth.users (id) on delete cascade,
    food_item_id uuid not null references public.food_items (id) on delete cascade,
    created_at   timestamptz not null default now(),
    primary key (user_id, food_item_id)
);

alter table public.food_favorites enable row level security;

create policy "Users manage their own favourites"
    on public.food_favorites for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
