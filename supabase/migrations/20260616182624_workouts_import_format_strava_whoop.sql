-- Align workouts.import_format with iOS WorkoutImportFormat (Strava/WHOOP sync).

alter table public.workouts
  drop constraint if exists workouts_import_format_check;

alter table public.workouts
  add constraint workouts_import_format_check
  check (
    import_format is null
    or import_format = any (array['tcx', 'fit', 'gpx', 'strava', 'whoop'])
  );
