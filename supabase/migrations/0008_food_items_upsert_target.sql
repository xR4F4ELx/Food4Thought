-- Make the USDA cache index usable as an ON CONFLICT target.
--
-- 0003 created the uniqueness on (source, external_id) as a *partial* index,
-- predicated on `external_id is not null`. That is a correct constraint and it
-- indexes fewer rows, but it cannot arbitrate an upsert issued through
-- PostgREST.
--
-- Postgres will only infer a partial index as an ON CONFLICT arbiter when the
-- statement repeats the index predicate:
--
--     insert ... on conflict (source, external_id) where external_id is not null
--
-- PostgREST's `on_conflict` parameter takes a column list and nothing else, so
-- the statement it builds carries no predicate, the inference finds no matching
-- index, and the insert fails with
--
--     there is no unique or exclusion constraint matching the ON CONFLICT
--     specification
--
-- That is every attempt to cache a USDA food: logging one, and starring one.
-- Both go through cacheIfNeeded, so the whole remote-search path terminated at
-- this error and only local foods could ever be logged.
--
-- Dropping the predicate costs nothing in correctness. Unique indexes treat
-- NULLs as distinct by default, so the full index still permits any number of
-- user_custom rows with a null external_id — two hand-entered foods with the
-- same name stay two different foods, exactly as before. The predicate was
-- only ever keeping those rows out of the index.

drop index public.food_items_source_external_idx;

create unique index food_items_source_external_idx
    on public.food_items (source, external_id);

comment on index public.food_items_source_external_idx is
    'Caches one row per external food. Deliberately not partial: PostgREST '
    'upserts cannot name an index predicate, so a partial index here cannot '
    'arbitrate ON CONFLICT. NULLs remain distinct, so user_custom rows are '
    'unaffected.';
