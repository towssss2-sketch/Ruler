-- 旧尝试保持 NULL，不回填推测的历史分类。结束记录仍受既有不可变触发器保护。
ALTER TABLE "IngestionPreviewAttempt"
  ADD COLUMN "classificationCategory" "DocumentCategory",
  ADD COLUMN "classificationReason" VARCHAR(32),
  ADD COLUMN "classificationRuleVersion" VARCHAR(32),
  ADD CONSTRAINT "preview_classification_result" CHECK (
    ("classificationCategory" IS NULL AND "classificationReason" IS NULL AND "classificationRuleVersion" IS NULL) OR
    ("status" = 'SUCCEEDED' AND "classificationRuleVersion" IS NOT NULL AND "classificationRuleVersion" = 'title-v1'
      AND "classificationReason" IS NOT NULL AND (
        ("classificationReason" = 'TITLE_MATCH' AND "classificationCategory" IS NOT NULL) OR
        ("classificationReason" IN ('NO_TITLE', 'CONFLICTING_TITLES') AND "classificationCategory" IS NULL)
      ))
  );
