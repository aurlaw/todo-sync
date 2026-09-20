-- N8: manual ordering. Additive only. Existing rows read 0; the client backfills real values.
ALTER TABLE todos ADD COLUMN sort_order REAL NOT NULL DEFAULT 0;
