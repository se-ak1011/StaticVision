-- StaticVision – Storage RLS policies
-- Run AFTER creating the private buckets `project-media` and `blueprints`.
--
-- Objects are stored under "<user_id>/<project_id>/<file>", so access is scoped
-- to the owner by matching the first path segment against the caller's user id.
-- The comparison is case-insensitive because the app builds paths from Swift's
-- uppercase UUID string while auth.uid() is lowercase.

-- project-media -----------------------------------------------------------
create policy "Users manage their own project-media objects"
    on storage.objects
    for all
    to authenticated
    using (
        bucket_id = 'project-media'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    )
    with check (
        bucket_id = 'project-media'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );

-- blueprints --------------------------------------------------------------
create policy "Users manage their own blueprints objects"
    on storage.objects
    for all
    to authenticated
    using (
        bucket_id = 'blueprints'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    )
    with check (
        bucket_id = 'blueprints'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );
