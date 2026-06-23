-- StaticVision – initial schema
-- Run in Supabase SQL editor or via `supabase db push`

-- ──────────────────────────────────────────────────
-- Extensions
-- ──────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ──────────────────────────────────────────────────
-- projects
-- ──────────────────────────────────────────────────
create table if not exists public.projects (
    id           uuid primary key default uuid_generate_v4(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    name         text not null,
    description  text not null default '',
    status       text not null default 'draft'
                 check (status in ('draft','processing','ready','failed')),
    media_count  integer not null default 0,
    blueprint_id uuid,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- Row-Level Security: users can only see/modify their own projects
alter table public.projects enable row level security;

create policy "Users can manage their own projects"
    on public.projects
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create index if not exists projects_user_id_idx on public.projects(user_id);

-- ──────────────────────────────────────────────────
-- project_media
-- ──────────────────────────────────────────────────
create table if not exists public.project_media (
    id             uuid primary key default uuid_generate_v4(),
    project_id     uuid not null references public.projects(id) on delete cascade,
    media_type     text not null check (media_type in ('photo','video')),
    storage_path   text not null,
    thumbnail_path text,
    created_at     timestamptz not null default now()
);

alter table public.project_media enable row level security;

create policy "Users can manage media for their projects"
    on public.project_media
    for all
    using  (exists (
        select 1 from public.projects p
        where p.id = project_id and p.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.projects p
        where p.id = project_id and p.user_id = auth.uid()
    ));

create index if not exists project_media_project_id_idx on public.project_media(project_id);

-- ──────────────────────────────────────────────────
-- blueprints
-- ──────────────────────────────────────────────────
create table if not exists public.blueprints (
    id            uuid primary key default uuid_generate_v4(),
    project_id    uuid not null references public.projects(id) on delete cascade,
    rooms         jsonb not null default '[]',
    scale         double precision not null default 10,
    canvas_width  double precision not null default 460,
    canvas_height double precision not null default 340,
    generated_at  timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    unique (project_id)
);

alter table public.blueprints enable row level security;

create policy "Users can manage blueprints for their projects"
    on public.blueprints
    for all
    using  (exists (
        select 1 from public.projects p
        where p.id = project_id and p.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.projects p
        where p.id = project_id and p.user_id = auth.uid()
    ));

create index if not exists blueprints_project_id_idx on public.blueprints(project_id);

-- ──────────────────────────────────────────────────
-- Storage buckets
-- (create via Supabase dashboard or with the management API)
-- ──────────────────────────────────────────────────
-- Bucket: project-media  (private, max 500 MB per file)
-- Bucket: blueprints     (private, max 10 MB per file)
--
-- Storage RLS policy for project-media:
--   Allow authenticated users to read/write their own paths (user_id/project_id/…)

-- ──────────────────────────────────────────────────
-- Helper function: auto-update updated_at
-- ──────────────────────────────────────────────────
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger projects_updated_at
    before update on public.projects
    for each row execute procedure public.handle_updated_at();

create trigger blueprints_updated_at
    before update on public.blueprints
    for each row execute procedure public.handle_updated_at();
