CREATE TYPE "PreviewAttemptStatus" AS ENUM ('RUNNING', 'SUCCEEDED', 'MANUAL_REQUIRED', 'INTERRUPTED');
CREATE TABLE "IngestionPreviewAttempt" (
  "id" UUID NOT NULL,
  "ingestionId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "status" "PreviewAttemptStatus" NOT NULL DEFAULT 'RUNNING',
  "reason" VARCHAR(32),
  "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "leaseExpiresAt" TIMESTAMPTZ(3) NOT NULL,
  "finishedAt" TIMESTAMPTZ(3),
  CONSTRAINT "IngestionPreviewAttempt_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "IngestionPreviewAttempt_file_fkey" FOREIGN KEY ("ingestionId", "userId")
    REFERENCES "IngestionFile"("ingestionId", "userId") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "preview_attempt_time" CHECK ("leaseExpiresAt" > "startedAt" AND
    ("finishedAt" IS NULL OR "finishedAt" >= "startedAt")),
  CONSTRAINT "preview_attempt_result" CHECK (
    ("status" = 'RUNNING' AND "reason" IS NULL AND "finishedAt" IS NULL) OR
    ("status" = 'SUCCEEDED' AND "reason" IS NULL AND "finishedAt" IS NOT NULL AND "finishedAt" < "leaseExpiresAt") OR
    ("status" = 'MANUAL_REQUIRED' AND "finishedAt" IS NOT NULL AND "reason" IS NOT NULL AND
      "finishedAt" < "leaseExpiresAt" AND "reason" IN ('UNSUPPORTED_FORMAT','FILE_TOO_LARGE','CONTENT_LIMIT','NO_TEXT',
        'INVALID_DOCUMENT','UNSUPPORTED_CONTENT','TIMEOUT','UNAVAILABLE')) OR
    ("status" = 'INTERRUPTED' AND "reason" IS NULL AND "finishedAt" IS NOT NULL AND "finishedAt" = "leaseExpiresAt")
  )
);
CREATE INDEX "IngestionPreviewAttempt_ingestionId_startedAt_id_idx"
  ON "IngestionPreviewAttempt"("ingestionId", "startedAt", "id");
CREATE INDEX "IngestionPreviewAttempt_userId_status_leaseExpiresAt_idx"
  ON "IngestionPreviewAttempt"("userId", "status", "leaseExpiresAt");
CREATE UNIQUE INDEX "preview_one_running_per_user" ON "IngestionPreviewAttempt"("userId") WHERE "status" = 'RUNNING';

-- 失败与中断记录保留；身份/期限不可重写，结束记录不可复用成新请求。
CREATE FUNCTION ruler_preview_attempt_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'preview attempts are retained'; END IF;
  IF NEW."id" IS DISTINCT FROM OLD."id" OR NEW."ingestionId" IS DISTINCT FROM OLD."ingestionId"
    OR NEW."userId" IS DISTINCT FROM OLD."userId" OR NEW."startedAt" IS DISTINCT FROM OLD."startedAt"
    OR NEW."leaseExpiresAt" IS DISTINCT FROM OLD."leaseExpiresAt" THEN
    RAISE EXCEPTION 'preview attempt identity is immutable';
  END IF;
  IF OLD."status" <> 'RUNNING' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'preview attempt is terminal';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preview_attempt_guard BEFORE UPDATE OR DELETE ON "IngestionPreviewAttempt"
  FOR EACH ROW EXECUTE FUNCTION ruler_preview_attempt_guard();
