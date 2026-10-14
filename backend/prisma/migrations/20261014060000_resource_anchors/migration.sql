BEGIN;

-- 单独追加迁移，不改写已经执行的迁移；防止父资源更新借级联扩大访问范围。
CREATE OR REPLACE FUNCTION ruler_identity_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE anchor text;
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION '业务记录标识不可修改' USING ERRCODE = '23514';
  END IF;
  FOREACH anchor IN ARRAY coalesce(TG_ARGV, ARRAY[]::text[]) LOOP
    IF (to_jsonb(NEW)->anchor) IS DISTINCT FROM (to_jsonb(OLD)->anchor) THEN
      RAISE EXCEPTION '记录所属资源或来源标识不可修改' USING ERRCODE = '23514';
    END IF;
  END LOOP;
  RETURN NEW;
END
$$;

DROP TRIGGER ruler_identity_immutable ON "CaseParty";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "CaseParty"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId');
DROP TRIGGER ruler_identity_immutable ON "CaseMember";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "CaseMember"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','userId');
DROP TRIGGER ruler_identity_immutable ON "Document";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "Document"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','uploadedBy','versionGroupId','version','source','ingestionId');
DROP TRIGGER ruler_identity_immutable ON "IngestionRecord";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "IngestionRecord"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId','channel','contentHash');
DROP TRIGGER ruler_identity_immutable ON "Task";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "Task"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','source');
DROP TRIGGER ruler_identity_immutable ON "TimelineEvent";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "TimelineEvent"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId');
DROP TRIGGER ruler_identity_immutable ON "CaseAnalysis";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "CaseAnalysis"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId');
DROP TRIGGER ruler_identity_immutable ON "DocumentDraft";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "DocumentDraft"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','createdBy');
DROP TRIGGER ruler_identity_immutable ON "EmailBinding";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "EmailBinding"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId','email');
DROP TRIGGER ruler_identity_immutable ON "ClientAccess";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "ClientAccess"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('caseId','casePartyId','grantedBy');
DROP TRIGGER ruler_identity_immutable ON "RTWallet";
CREATE TRIGGER ruler_identity_immutable BEFORE UPDATE ON "RTWallet"
  FOR EACH ROW EXECUTE FUNCTION ruler_identity_immutable('userId');

COMMIT;
