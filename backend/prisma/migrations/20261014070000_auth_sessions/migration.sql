BEGIN;
-- CreateTable
CREATE TABLE "AuthSession" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "revokedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "AuthSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefreshCredential" (
    "id" UUID NOT NULL,
    "sessionId" UUID NOT NULL,
    "tokenHash" CHAR(64) NOT NULL,
    "consumedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "RefreshCredential_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AuthSession_userId_revokedAt_expiresAt_idx" ON "AuthSession"("userId", "revokedAt", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshCredential_tokenHash_key" ON "RefreshCredential"("tokenHash");

-- CreateIndex
CREATE INDEX "RefreshCredential_sessionId_consumedAt_idx" ON "RefreshCredential"("sessionId", "consumedAt");

-- AddForeignKey
ALTER TABLE "AuthSession" ADD CONSTRAINT "AuthSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefreshCredential" ADD CONSTRAINT "RefreshCredential_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "AuthSession"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


ALTER TABLE "AuthSession" ADD CONSTRAINT "AuthSession_lifetime_check" CHECK ("expiresAt" > "createdAt");
ALTER TABLE "RefreshCredential" ADD CONSTRAINT "RefreshCredential_hash_check" CHECK ("tokenHash" ~ '^[a-f0-9]{64}$');
CREATE UNIQUE INDEX "RefreshCredential_one_active" ON "RefreshCredential" ("sessionId") WHERE "consumedAt" IS NULL AND "deletedAt" IS NULL;
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "AuthSession" FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId');
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "RefreshCredential" FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('sessionId','tokenHash');
COMMIT;
