CREATE UNIQUE INDEX "IngestionRecord_id_userId_key" ON "IngestionRecord"("id", "userId");

CREATE TABLE "IngestionUpload" (
  "id" UUID NOT NULL PRIMARY KEY,
  "userId" UUID NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "fileName" VARCHAR(255) NOT NULL,
  "mimeType" VARCHAR(128) NOT NULL,
  "sizeBytes" BIGINT NOT NULL CHECK ("sizeBytes" BETWEEN 1 AND 209715200),
  "contentMd5" VARCHAR(24) NOT NULL,
  "pendingKey" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "ingestionId" UUID,
  "expiresAt" TIMESTAMPTZ(3) NOT NULL,
  "completedAt" TIMESTAMPTZ(3),
  "cleanedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "IngestionUpload_keys_distinct" CHECK ("pendingKey" <> "storageKey"),
  CONSTRAINT "IngestionUpload_completion_valid" CHECK (("completedAt" IS NULL) = ("ingestionId" IS NULL)),
  CONSTRAINT "IngestionUpload_ingestionId_userId_fkey" FOREIGN KEY ("ingestionId", "userId")
    REFERENCES "IngestionRecord"("id", "userId") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "IngestionUpload_pendingKey_key" ON "IngestionUpload"("pendingKey");
CREATE UNIQUE INDEX "IngestionUpload_storageKey_key" ON "IngestionUpload"("storageKey");
CREATE INDEX "IngestionUpload_userId_expiresAt_idx" ON "IngestionUpload"("userId", "expiresAt");
CREATE INDEX "IngestionUpload_cleanedAt_expiresAt_idx" ON "IngestionUpload"("cleanedAt", "expiresAt");
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "IngestionUpload"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId','fileName','mimeType','sizeBytes','contentMd5','pendingKey','storageKey','expiresAt');

CREATE TABLE "IngestionFile" (
  "id" UUID NOT NULL PRIMARY KEY,
  "ingestionId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "fileName" VARCHAR(255) NOT NULL,
  "mimeType" VARCHAR(128) NOT NULL,
  "sizeBytes" BIGINT NOT NULL CHECK ("sizeBytes" BETWEEN 1 AND 209715200),
  "storageKey" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "IngestionFile_ingestionId_userId_fkey" FOREIGN KEY ("ingestionId", "userId")
    REFERENCES "IngestionRecord"("id", "userId") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "IngestionFile_ingestionId_key" ON "IngestionFile"("ingestionId");
CREATE UNIQUE INDEX "IngestionFile_ingestionId_userId_key" ON "IngestionFile"("ingestionId", "userId");
CREATE UNIQUE INDEX "IngestionFile_storageKey_key" ON "IngestionFile"("storageKey");
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "IngestionFile"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId','ingestionId','fileName','mimeType','sizeBytes','storageKey');

-- 完成/清理结果只能向前，不允许把票据重置后重新写入或重复占容量。
CREATE FUNCTION ruler_ingestion_upload_terminal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD."completedAt" IS NOT NULL AND
    (NEW."completedAt" IS DISTINCT FROM OLD."completedAt" OR NEW."ingestionId" IS DISTINCT FROM OLD."ingestionId") THEN
    RAISE EXCEPTION 'ingestion upload completion is immutable';
  END IF;
  IF OLD."cleanedAt" IS NOT NULL AND NEW."cleanedAt" IS DISTINCT FROM OLD."cleanedAt" THEN
    RAISE EXCEPTION 'ingestion upload cleanup is immutable';
  END IF;
  IF OLD."cleanedAt" IS NOT NULL AND OLD."completedAt" IS NULL AND NEW."completedAt" IS NOT NULL THEN
    RAISE EXCEPTION 'cleaned ingestion upload cannot complete';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ruler_ingestion_upload_terminal BEFORE UPDATE ON "IngestionUpload"
  FOR EACH ROW EXECUTE FUNCTION ruler_ingestion_upload_terminal();
