BEGIN;

-- 使用 PG 提供的 schema 标识并用 %I 引用、USING 绑定值，避免临时表或跨 schema 错绑。
CREATE FUNCTION ruler_assert_case_owner(schema_name text, target_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_owner uuid; valid boolean;
BEGIN
  EXECUTE format('SELECT "ownerId" FROM %I."Case" WHERE id=$1 AND "deletedAt" IS NULL', schema_name)
    INTO actual_owner USING target_id;
  IF actual_owner IS NULL THEN RETURN; END IF;
  EXECUTE format(
    'SELECT count(*)=1 AND bool_and("userId"=$2) FROM %I."CaseMember" WHERE "caseId"=$1 AND role=''OWNER'' AND status=''ACCEPTED'' AND "deletedAt" IS NULL',
    schema_name
  ) INTO valid USING target_id, actual_owner;
  IF NOT coalesce(valid, false) THEN
    RAISE EXCEPTION '主办律师与有效 OWNER 成员不一致' USING ERRCODE = '23514';
  END IF;
END
$$;

CREATE FUNCTION ruler_check_case_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'Case' THEN
    PERFORM ruler_assert_case_owner(TG_TABLE_SCHEMA, NEW.id);
  ELSE
    IF TG_OP <> 'DELETE' THEN PERFORM ruler_assert_case_owner(TG_TABLE_SCHEMA, NEW."caseId"); END IF;
    IF TG_OP <> 'INSERT' THEN PERFORM ruler_assert_case_owner(TG_TABLE_SCHEMA, OLD."caseId"); END IF;
  END IF;
  RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER "Case_owner_consistent" AFTER INSERT OR UPDATE ON "Case"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_case_owner();
CREATE CONSTRAINT TRIGGER "CaseMember_owner_consistent" AFTER INSERT OR UPDATE OR DELETE ON "CaseMember"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_case_owner();

CREATE FUNCTION ruler_assert_ingestion_documents(schema_name text, target_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE invalid boolean;
BEGIN
  EXECUTE format(
    'SELECT EXISTS(SELECT 1 FROM %I."Document" d JOIN %I."IngestionRecord" i ON i.id=d."ingestionId" WHERE i.id=$1 AND d."deletedAt" IS NULL AND (i."matchedCaseId" IS DISTINCT FROM d."caseId" OR i.channel::text <> d.source::text))',
    schema_name, schema_name
  ) INTO invalid USING target_id;
  IF invalid THEN
    RAISE EXCEPTION '活跃文档与归集来源的案件或渠道不一致' USING ERRCODE = '23514';
  END IF;
END
$$;
CREATE FUNCTION ruler_check_ingestion_documents() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'IngestionRecord' THEN
    PERFORM ruler_assert_ingestion_documents(TG_TABLE_SCHEMA, NEW.id);
  ELSE
    IF NEW."ingestionId" IS NOT NULL THEN PERFORM ruler_assert_ingestion_documents(TG_TABLE_SCHEMA, NEW."ingestionId"); END IF;
    IF TG_OP = 'UPDATE' AND OLD."ingestionId" IS NOT NULL THEN
      PERFORM ruler_assert_ingestion_documents(TG_TABLE_SCHEMA, OLD."ingestionId");
    END IF;
  END IF;
  RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER "Document_ingestion_consistent" AFTER INSERT OR UPDATE ON "Document"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_ingestion_documents();
CREATE CONSTRAINT TRIGGER "IngestionRecord_documents_consistent" AFTER INSERT OR UPDATE ON "IngestionRecord"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_ingestion_documents();

-- 只建立流水数据一致性，不接入支付、不定义兑换、退款或真实价格政策。
CREATE FUNCTION ruler_check_ledger_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE previous numeric; wallet_exists boolean;
BEGIN
  EXECUTE format('SELECT true FROM %I."RTWallet" WHERE id=$1 FOR UPDATE', TG_TABLE_SCHEMA)
    INTO wallet_exists USING NEW."walletId";
  IF wallet_exists IS NULL THEN RAISE EXCEPTION '钱包不存在' USING ERRCODE='23503'; END IF;
  EXECUTE format(
    'SELECT coalesce((SELECT "balanceAfter" FROM %I."RTTransaction" WHERE "walletId"=$1 ORDER BY sequence DESC LIMIT 1),0)',
    TG_TABLE_SCHEMA
  ) INTO previous USING NEW."walletId";
  IF NEW."balanceAfter" IS DISTINCT FROM previous + NEW.amount THEN
    RAISE EXCEPTION 'RT 流水余额快照不连续' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER "RTTransaction_balance_sequence" BEFORE INSERT ON "RTTransaction"
  FOR EACH ROW EXECUTE FUNCTION ruler_check_ledger_insert();

CREATE FUNCTION ruler_assert_wallet_balance(schema_name text, target_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual numeric; expected numeric;
BEGIN
  EXECUTE format('SELECT balance FROM %I."RTWallet" WHERE id=$1', schema_name)
    INTO actual USING target_id;
  IF actual IS NULL THEN RETURN; END IF;
  EXECUTE format(
    'SELECT coalesce((SELECT "balanceAfter" FROM %I."RTTransaction" WHERE "walletId"=$1 ORDER BY sequence DESC LIMIT 1),0)',
    schema_name
  ) INTO expected USING target_id;
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION '钱包余额必须等于最后一笔流水快照' USING ERRCODE='23514';
  END IF;
END
$$;
CREATE FUNCTION ruler_check_wallet_balance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'RTWallet' THEN
    PERFORM ruler_assert_wallet_balance(TG_TABLE_SCHEMA, NEW.id);
  ELSE
    PERFORM ruler_assert_wallet_balance(TG_TABLE_SCHEMA, NEW."walletId");
  END IF;
  RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER "RTWallet_ledger_consistent" AFTER INSERT OR UPDATE ON "RTWallet"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_wallet_balance();
CREATE CONSTRAINT TRIGGER "RTTransaction_wallet_consistent" AFTER INSERT ON "RTTransaction"
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ruler_check_wallet_balance();

COMMIT;
