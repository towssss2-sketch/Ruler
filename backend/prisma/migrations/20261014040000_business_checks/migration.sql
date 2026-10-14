BEGIN;

-- 结构检查防止误写明文；GCM 标签真实性由应用加密接口校验，数据库不保存主密钥。
CREATE FUNCTION ruler_ciphertext_valid(payload bytea) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT octet_length(payload) > 32
    AND substring(payload FROM 1 FOR 4) = decode('47434d31', 'hex')
$$;

ALTER TABLE "User"
  ADD CONSTRAINT "User_contact_required" CHECK ("email" IS NOT NULL OR "phone" IS NOT NULL),
  ADD CONSTRAINT "User_email_canonical" CHECK ("email" IS NULL OR (length("email") > 0 AND "email" = lower(btrim("email")))),
  ADD CONSTRAINT "User_storage_nonnegative" CHECK ("storageQuotaBytes" >= 0 AND "storageUsedBytes" >= 0),
  ADD CONSTRAINT "User_phone_encrypted" CHECK ("phone" IS NULL OR ruler_ciphertext_valid("phone")),
  ADD CONSTRAINT "User_phone_index_pair" CHECK (
    ("phone" IS NULL AND "phoneLookupHash" IS NULL)
    OR ("phone" IS NOT NULL AND "phoneLookupHash" IS NOT NULL AND octet_length("phoneLookupHash") = 32)
  ),
  ADD CONSTRAINT "User_license_encrypted" CHECK ("barLicenseNo" IS NULL OR ruler_ciphertext_valid("barLicenseNo"));

ALTER TABLE "Case"
  ADD CONSTRAINT "Case_fee_valid" CHECK ("fee" IS NULL OR ("fee" >= 0 AND "fee" < 'Infinity'::numeric)),
  ADD CONSTRAINT "Case_phone_encrypted" CHECK ("clerkPhone" IS NULL OR ruler_ciphertext_valid("clerkPhone")),
  ADD CONSTRAINT "Case_notes_encrypted" CHECK ("notes" IS NULL OR ruler_ciphertext_valid("notes"));

ALTER TABLE "CaseParty"
  ADD CONSTRAINT "CaseParty_idCard_encrypted" CHECK ("idCard" IS NULL OR ruler_ciphertext_valid("idCard")),
  ADD CONSTRAINT "CaseParty_phone_encrypted" CHECK ("phone" IS NULL OR ruler_ciphertext_valid("phone")),
  ADD CONSTRAINT "CaseParty_address_encrypted" CHECK ("address" IS NULL OR ruler_ciphertext_valid("address"));

ALTER TABLE "CaseMember"
  ADD CONSTRAINT "CaseMember_acceptance_timestamp" CHECK (
    ("status" <> 'ACCEPTED' OR "acceptedAt" IS NOT NULL)
    AND ("status" <> 'PENDING' OR "acceptedAt" IS NULL)
  );

ALTER TABLE "Document"
  ADD CONSTRAINT "Document_size_version_valid" CHECK ("sizeBytes" >= 0 AND "sizeBytes" <= 209715200 AND "version" > 0),
  ADD CONSTRAINT "Document_channel_has_ingestion" CHECK ("source" = 'MANUAL' OR "ingestionId" IS NOT NULL),
  ADD CONSTRAINT "Document_storage_key_safe" CHECK (
    length("storageKey") > 0 AND "storageKey" NOT LIKE '/%'
    AND "storageKey" NOT LIKE '%..%' AND "storageKey" !~ '[[:cntrl:]]'
  );

ALTER TABLE "IngestionRecord"
  ADD CONSTRAINT "IngestionRecord_raw_encrypted" CHECK (ruler_ciphertext_valid("rawContent")),
  ADD CONSTRAINT "IngestionRecord_link_encrypted" CHECK ("deliveryLink" IS NULL OR ruler_ciphertext_valid("deliveryLink")),
  ADD CONSTRAINT "IngestionRecord_hash_valid" CHECK ("contentHash" ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT "IngestionRecord_retry_nonnegative" CHECK ("attemptCount" >= 0),
  ADD CONSTRAINT "IngestionRecord_match_state" CHECK (
    ("status" = 'PENDING_MATCH' AND "matchedCaseId" IS NULL)
    OR ("status" IN ('MATCHED', 'ASSIGNED') AND "matchedCaseId" IS NOT NULL)
    OR "status" = 'IGNORED'
  );

ALTER TABLE "EmailBinding"
  ADD CONSTRAINT "EmailBinding_credentials_encrypted" CHECK (ruler_ciphertext_valid("credentials"));

ALTER TABLE "Task"
  ADD CONSTRAINT "Task_description_encrypted" CHECK ("description" IS NULL OR ruler_ciphertext_valid("description")),
  ADD CONSTRAINT "Task_completion_state" CHECK (("status" = 'DONE') = ("completedAt" IS NOT NULL)),
  ADD CONSTRAINT "Task_deadline_confirmation" CHECK (
    ("source" <> 'DEADLINE_RULE' OR ("deadlineType" IS NOT NULL AND "baseDate" IS NOT NULL))
    AND (
      ("deadlineType" IS NULL AND "deadlineConfirmedAt" IS NULL AND "deadlineConfirmedById" IS NULL AND "proposedDueDate" IS NULL)
      OR ("deadlineType" IS NOT NULL AND (
        ("deadlineConfirmedAt" IS NULL AND "deadlineConfirmedById" IS NULL AND "dueDate" IS NULL)
        OR ("deadlineConfirmedAt" IS NOT NULL AND "deadlineConfirmedById" IS NOT NULL AND "dueDate" IS NOT NULL)
      ))
    )
  );

ALTER TABLE "TimelineEvent"
  ADD CONSTRAINT "TimelineEvent_description_encrypted" CHECK ("description" IS NULL OR ruler_ciphertext_valid("description"));
ALTER TABLE "CaseAnalysis"
  ADD CONSTRAINT "CaseAnalysis_summary_encrypted" CHECK (ruler_ciphertext_valid("summary"));
ALTER TABLE "DocumentDraft"
  ADD CONSTRAINT "DocumentDraft_content_encrypted" CHECK (ruler_ciphertext_valid("content")),
  ADD CONSTRAINT "DocumentDraft_adoption_state" CHECK (("status" = 'ADOPTED') = ("adoptedDocumentId" IS NOT NULL));

ALTER TABLE "DeliveryPlatformRule"
  ADD CONSTRAINT "DeliveryPlatformRule_counts_valid" CHECK ("successCount" >= 0 AND "failCount" >= 0),
  ADD CONSTRAINT "DeliveryPlatformRule_domain_host_only" CHECK (
    length("domain") > 0 AND "domain" = lower(btrim("domain")) AND "domain" !~ '[/ :[:cntrl:]]'
  );
ALTER TABLE "ClientAccess"
  ADD CONSTRAINT "ClientAccess_token_digest" CHECK (octet_length("tokenHash") = 32),
  ADD CONSTRAINT "ClientAccess_lifetime" CHECK ("expiresAt" > "createdAt"),
  ADD CONSTRAINT "ClientAccess_revoke_state" CHECK (("status" = 'REVOKED') = ("revokedAt" IS NOT NULL));
ALTER TABLE "ClientAccessLog" ADD CONSTRAINT "ClientAccessLog_live_record" CHECK ("deletedAt" IS NULL);
ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_live_record" CHECK ("deletedAt" IS NULL);

-- 使用量可高于配额，保留会员降级后的只读业务；这里仅禁止负容量。
ALTER TABLE "RTWallet" ADD CONSTRAINT "RTWallet_finite_nonnegative" CHECK (
  "balance" >= 0 AND "balance" < 'Infinity'::numeric
  AND "totalCharged" >= 0 AND "totalCharged" < 'Infinity'::numeric
  AND "totalConsumed" >= 0 AND "totalConsumed" < 'Infinity'::numeric
);
ALTER TABLE "RTTransaction" ADD CONSTRAINT "RTTransaction_valid_snapshot" CHECK (
  "amount" <> 0 AND abs("amount") < 'Infinity'::numeric
  AND "balanceAfter" >= 0 AND "balanceAfter" < 'Infinity'::numeric
  AND "sequence" > 0 AND "deletedAt" IS NULL
);
ALTER TABLE "PriceConfig" ADD CONSTRAINT "PriceConfig_finite_nonnegative" CHECK (
  "rtPrice" >= 0 AND "rtPrice" < 'Infinity'::numeric
  AND ("yuanPrice" IS NULL OR ("yuanPrice" >= 0 AND "yuanPrice" < 'Infinity'::numeric))
);

CREATE UNIQUE INDEX "Case_active_identity" ON "Case" ("ownerId", "caseNo", "court") WHERE "deletedAt" IS NULL;
CREATE UNIQUE INDEX "CaseMember_one_active_owner" ON "CaseMember" ("caseId")
  WHERE "role" = 'OWNER' AND "status" = 'ACCEPTED' AND "deletedAt" IS NULL;
CREATE UNIQUE INDEX "Document_one_current_version" ON "Document" ("caseId", "versionGroupId")
  WHERE "isCurrentVersion" AND "deletedAt" IS NULL;

CREATE FUNCTION ruler_reject_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '追加记录不可修改或删除' USING ERRCODE = '55000';
END
$$;
CREATE TRIGGER "RTTransaction_append_only" BEFORE UPDATE OR DELETE ON "RTTransaction"
  FOR EACH ROW EXECUTE FUNCTION ruler_reject_mutation();
CREATE TRIGGER "AuditLog_append_only" BEFORE UPDATE OR DELETE ON "AuditLog"
  FOR EACH ROW EXECUTE FUNCTION ruler_reject_mutation();
CREATE TRIGGER "ClientAccessLog_append_only" BEFORE UPDATE OR DELETE ON "ClientAccessLog"
  FOR EACH ROW EXECUTE FUNCTION ruler_reject_mutation();

CREATE FUNCTION ruler_identity_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION '业务记录标识不可修改' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;
DO $$
DECLARE entity text;
BEGIN
  FOREACH entity IN ARRAY ARRAY[
    'User','Case','CaseParty','CaseMember','Document','IngestionRecord','Task','TimelineEvent',
    'CaseAnalysis','DocumentDraft','EmailBinding','DeliveryPlatformRule','ClientAccess',
    'ClientAccessLog','AuditLog','RTWallet','RTTransaction','PriceConfig'
  ] LOOP
    EXECUTE format('CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable()', entity);
  END LOOP;
END
$$;

COMMIT;
