-- Profiles: one row per authenticated user, created automatically on signup.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
    id                      uuid primary key references auth.users (id) on delete cascade,
    display_name            text,
    -- Birth date rather than age so it never goes stale; age is derived at calc time.
    birth_date              date,
    -- Drives the Mifflin-St Jeor constant only. Label distinctly from gender identity in UI.
    biological_sex          text check (biological_sex in ('male', 'female')),
    height_cm               numeric(5, 2) check (height_cm > 0),
    -- [{key, label, typical_time:"HH:mm", expected_share}] — shares sum to 1.0.
    meal_schedule           jsonb not null default '[]'::jsonb,
    onboarding_completed_at timestamptz,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;

create policy "Users read their own profile"
    on public.profiles for select
    using (auth.uid() = id);

create policy "Users insert their own profile"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "Users update their own profile"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Auto-create the profile row so the client never races signup against a missing row.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
