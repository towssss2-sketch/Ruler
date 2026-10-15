CREATE TABLE "DocumentUpload" (
  "id" UUID NOT NULL PRIMARY KEY,
  "caseId" UUID NOT NULL REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "ownerId" UUID NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "uploadedBy" UUID NOT NULL REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "documentId" UUID NOT NULL,
  "versionGroupId" UUID NOT NULL,
  "version" INTEGER NOT NULL,
  "fileName" VARCHAR(255) NOT NULL,
  "mimeType" VARCHAR(128) NOT NULL,
  "sizeBytes" BIGINT NOT NULL,
  "contentMd5" VARCHAR(24) NOT NULL,
  "pendingKey" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "source" "DocumentSource" NOT NULL DEFAULT 'MANUAL',
  "ingestionId" UUID,
  "expiresAt" TIMESTAMPTZ(3) NOT NULL,
  "completedAt" TIMESTAMPTZ(3),
  "cleanedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "DocumentUpload_size_version_valid" CHECK ("sizeBytes" BETWEEN 1 AND 209715200 AND "version" > 0),
  CONSTRAINT "DocumentUpload_keys_distinct" CHECK ("pendingKey" <> "storageKey"),
  CONSTRAINT "DocumentUpload_source_valid" CHECK (("source" = 'MANUAL') = ("ingestionId" IS NULL))
);
CREATE UNIQUE INDEX "DocumentUpload_documentId_key" ON "DocumentUpload"("documentId");
CREATE UNIQUE INDEX "DocumentUpload_pendingKey_key" ON "DocumentUpload"("pendingKey");
CREATE UNIQUE INDEX "DocumentUpload_storageKey_key" ON "DocumentUpload"("storageKey");
CREATE UNIQUE INDEX "DocumentUpload_caseId_versionGroupId_version_key" ON "DocumentUpload"("caseId", "versionGroupId", "version");
CREATE INDEX "DocumentUpload_ownerId_expiresAt_idx" ON "DocumentUpload"("ownerId", "expiresAt");
CREATE INDEX "DocumentUpload_cleanedAt_expiresAt_idx" ON "DocumentUpload"("cleanedAt", "expiresAt");
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "DocumentUpload"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','ownerId','uploadedBy','documentId','versionGroupId','version','pendingKey','storageKey','fileName','mimeType','sizeBytes','contentMd5','source','ingestionId','expiresAt');
