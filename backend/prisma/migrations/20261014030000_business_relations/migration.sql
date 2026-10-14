BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryPlatformRule_domain_key" ON "DeliveryPlatformRule"("domain");

-- CreateIndex
CREATE UNIQUE INDEX "ClientAccess_tokenHash_key" ON "ClientAccess"("tokenHash");

-- CreateIndex
CREATE INDEX "ClientAccess_caseId_status_idx" ON "ClientAccess"("caseId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ClientAccess_id_caseId_key" ON "ClientAccess"("id", "caseId");

-- CreateIndex
CREATE INDEX "ClientAccessLog_clientAccessId_occurredAt_idx" ON "ClientAccessLog"("clientAccessId", "occurredAt");

-- CreateIndex
CREATE INDEX "AuditLog_userId_createdAt_idx" ON "AuditLog"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditLog_caseId_createdAt_idx" ON "AuditLog"("caseId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "RTWallet_userId_key" ON "RTWallet"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "RTTransaction_sequence_key" ON "RTTransaction"("sequence");

-- CreateIndex
CREATE INDEX "RTTransaction_walletId_sequence_idx" ON "RTTransaction"("walletId", "sequence");

-- CreateIndex
CREATE UNIQUE INDEX "PriceConfig_itemKey_key" ON "PriceConfig"("itemKey");

-- CreateIndex
CREATE UNIQUE INDEX "Document_storageKey_key" ON "Document"("storageKey");

-- CreateIndex
CREATE INDEX "Document_caseId_category_idx" ON "Document"("caseId", "category");

-- CreateIndex
CREATE UNIQUE INDEX "Document_id_caseId_key" ON "Document"("id", "caseId");

-- CreateIndex
CREATE UNIQUE INDEX "Document_caseId_versionGroupId_version_key" ON "Document"("caseId", "versionGroupId", "version");

-- CreateIndex
CREATE INDEX "IngestionRecord_userId_status_receivedAt_idx" ON "IngestionRecord"("userId", "status", "receivedAt");

-- CreateIndex
CREATE INDEX "IngestionRecord_stage_nextRetryAt_idx" ON "IngestionRecord"("stage", "nextRetryAt");

-- CreateIndex
CREATE UNIQUE INDEX "IngestionRecord_userId_channel_contentHash_key" ON "IngestionRecord"("userId", "channel", "contentHash");

-- CreateIndex
CREATE UNIQUE INDEX "EmailBinding_userId_email_key" ON "EmailBinding"("userId", "email");

-- CreateIndex
CREATE INDEX "Task_caseId_dueDate_status_idx" ON "Task"("caseId", "dueDate", "status");

-- CreateIndex
CREATE INDEX "TimelineEvent_caseId_eventDate_idx" ON "TimelineEvent"("caseId", "eventDate");

-- CreateIndex
CREATE INDEX "CaseAnalysis_caseId_generatedAt_idx" ON "CaseAnalysis"("caseId", "generatedAt");

-- CreateIndex
CREATE INDEX "DocumentDraft_caseId_status_idx" ON "DocumentDraft"("caseId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_phoneLookupHash_key" ON "User"("phoneLookupHash");

-- CreateIndex
CREATE INDEX "Case_ownerId_caseNo_court_idx" ON "Case"("ownerId", "caseNo", "court");

-- CreateIndex
CREATE INDEX "Case_ownerId_status_updatedAt_idx" ON "Case"("ownerId", "status", "updatedAt");

-- CreateIndex
CREATE INDEX "CaseParty_caseId_role_idx" ON "CaseParty"("caseId", "role");

-- CreateIndex
CREATE UNIQUE INDEX "CaseParty_id_caseId_key" ON "CaseParty"("id", "caseId");

-- CreateIndex
CREATE INDEX "CaseMember_userId_status_idx" ON "CaseMember"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "CaseMember_caseId_userId_key" ON "CaseMember"("caseId", "userId");

-- AddForeignKey
ALTER TABLE "ClientAccess" ADD CONSTRAINT "ClientAccess_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ClientAccess" ADD CONSTRAINT "ClientAccess_casePartyId_caseId_fkey" FOREIGN KEY ("casePartyId", "caseId") REFERENCES "CaseParty"("id", "caseId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ClientAccess" ADD CONSTRAINT "ClientAccess_grantedBy_fkey" FOREIGN KEY ("grantedBy") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ClientAccessLog" ADD CONSTRAINT "ClientAccessLog_clientAccessId_caseId_fkey" FOREIGN KEY ("clientAccessId", "caseId") REFERENCES "ClientAccess"("id", "caseId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ClientAccessLog" ADD CONSTRAINT "ClientAccessLog_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RTWallet" ADD CONSTRAINT "RTWallet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RTTransaction" ADD CONSTRAINT "RTTransaction_walletId_fkey" FOREIGN KEY ("walletId") REFERENCES "RTWallet"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Document" ADD CONSTRAINT "Document_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Document" ADD CONSTRAINT "Document_uploadedBy_fkey" FOREIGN KEY ("uploadedBy") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Document" ADD CONSTRAINT "Document_ingestionId_fkey" FOREIGN KEY ("ingestionId") REFERENCES "IngestionRecord"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IngestionRecord" ADD CONSTRAINT "IngestionRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IngestionRecord" ADD CONSTRAINT "IngestionRecord_matchedCaseId_fkey" FOREIGN KEY ("matchedCaseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EmailBinding" ADD CONSTRAINT "EmailBinding_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Task" ADD CONSTRAINT "Task_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Task" ADD CONSTRAINT "Task_deadlineConfirmedById_fkey" FOREIGN KEY ("deadlineConfirmedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TimelineEvent" ADD CONSTRAINT "TimelineEvent_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TimelineEvent" ADD CONSTRAINT "TimelineEvent_sourceDocumentId_caseId_fkey" FOREIGN KEY ("sourceDocumentId", "caseId") REFERENCES "Document"("id", "caseId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CaseAnalysis" ADD CONSTRAINT "CaseAnalysis_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DocumentDraft" ADD CONSTRAINT "DocumentDraft_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DocumentDraft" ADD CONSTRAINT "DocumentDraft_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DocumentDraft" ADD CONSTRAINT "DocumentDraft_adoptedDocumentId_caseId_fkey" FOREIGN KEY ("adoptedDocumentId", "caseId") REFERENCES "Document"("id", "caseId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Case" ADD CONSTRAINT "Case_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CaseParty" ADD CONSTRAINT "CaseParty_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CaseMember" ADD CONSTRAINT "CaseMember_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "Case"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CaseMember" ADD CONSTRAINT "CaseMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CaseMember" ADD CONSTRAINT "CaseMember_invitedBy_fkey" FOREIGN KEY ("invitedBy") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


COMMIT;
