ALTER TABLE "IngestionRecord" ADD COLUMN "assignmentRevision" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "IngestionRecord" ADD CONSTRAINT "IngestionRecord_assignment_revision_nonnegative" CHECK ("assignmentRevision" >= 0);
