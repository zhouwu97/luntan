DROP INDEX IF EXISTS activities_publication_status_idx;
ALTER TABLE activities DROP CONSTRAINT IF EXISTS activities_publication_status_check;
ALTER TABLE activities DROP COLUMN IF EXISTS publication_status;
