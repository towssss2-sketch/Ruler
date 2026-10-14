BEGIN;

-- CreateTable
CREATE TABLE "DeliveryPlatformRule" (
    "id" UUID NOT NULL,
    "domain" VARCHAR(253) NOT NULL,
    "province" VARCHAR(64),
    "platformName" VARCHAR(128) NOT NULL,
    "mode" "DeliveryMode" NOT NULL DEFAULT 'MANUAL',
    "parseRules" JSONB NOT NULL DEFAULT '{}',
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "successCount" INTEGER NOT NULL DEFAULT 0,
    "failCount" INTEGER NOT NULL DEFAULT 0,
    "lastSuccessAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "DeliveryPlatformRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ClientAccess" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "casePartyId" UUID NOT NULL,
    "grantedBy" UUID NOT NULL,
    "tokenHash" BYTEA NOT NULL,
    "status" "ClientAccessStatus" NOT NULL DEFAULT 'PENDING',
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "revokedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "ClientAccess_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ClientAccessLog" (
    "id" UUID NOT NULL,
    "clientAccessId" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "action" VARCHAR(128) NOT NULL,
    "resourceType" VARCHAR(64) NOT NULL,
    "resourceId" UUID,
    "succeeded" BOOLEAN NOT NULL,
    "ip" INET,
    "occurredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "ClientAccessLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "caseId" UUID,
    "action" VARCHAR(128) NOT NULL,
    "resourceType" VARCHAR(64) NOT NULL,
    "resourceId" UUID,
    "detail" JSONB NOT NULL DEFAULT '{}',
    "ip" INET,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RTWallet" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "balance" DECIMAL(20,6) NOT NULL DEFAULT 0,
    "totalCharged" DECIMAL(20,6) NOT NULL DEFAULT 0,
    "totalConsumed" DECIMAL(20,6) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "RTWallet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RTTransaction" (
    "id" UUID NOT NULL,
    "walletId" UUID NOT NULL,
    "sequence" BIGSERIAL NOT NULL,
    "type" "RTTransactionType" NOT NULL,
    "amount" DECIMAL(20,6) NOT NULL,
    "balanceAfter" DECIMAL(20,6) NOT NULL,
    "relatedOrderId" UUID,
    "relatedResourceId" UUID,
    "remark" VARCHAR(255),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "RTTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PriceConfig" (
    "id" UUID NOT NULL,
    "itemKey" VARCHAR(128) NOT NULL,
    "itemType" "PriceItemType" NOT NULL,
    "rtPrice" DECIMAL(20,6) NOT NULL,
    "yuanPrice" DECIMAL(14,2),
    "quota" JSONB NOT NULL DEFAULT '{}',
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "PriceConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Document" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "category" "DocumentCategory" NOT NULL,
    "fileName" VARCHAR(255) NOT NULL,
    "storageKey" TEXT NOT NULL,
    "mimeType" VARCHAR(128) NOT NULL,
    "sizeBytes" BIGINT NOT NULL,
    "versionGroupId" UUID NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "isCurrentVersion" BOOLEAN NOT NULL DEFAULT true,
    "isClientVisible" BOOLEAN NOT NULL DEFAULT false,
    "source" "DocumentSource" NOT NULL DEFAULT 'MANUAL',
    "ingestionId" UUID,
    "uploadedBy" UUID NOT NULL,
    "uploadedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "Document_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IngestionRecord" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "channel" "IngestionChannel" NOT NULL,
    "rawContent" BYTEA NOT NULL,
    "deliveryLink" BYTEA,
    "attachmentKeys" JSONB NOT NULL DEFAULT '[]',
    "aiResult" JSONB,
    "contentHash" CHAR(64) NOT NULL,
    "matchedCaseId" UUID,
    "status" "IngestionStatus" NOT NULL DEFAULT 'PENDING_MATCH',
    "stage" "IngestionStage" NOT NULL DEFAULT 'RECEIVE',
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "lastErrorCode" VARCHAR(64),
    "nextRetryAt" TIMESTAMPTZ(3),
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "IngestionRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EmailBinding" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "email" VARCHAR(254) NOT NULL,
    "authType" "EmailAuthType" NOT NULL,
    "credentials" BYTEA NOT NULL,
    "lastSyncAt" TIMESTAMPTZ(3),
    "status" "EmailBindingStatus" NOT NULL DEFAULT 'PAUSED',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "EmailBinding_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Task" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" BYTEA,
    "dueDate" DATE,
    "status" "TaskStatus" NOT NULL DEFAULT 'TODO',
    "source" "TaskSource" NOT NULL DEFAULT 'MANUAL',
    "isClientVisible" BOOLEAN NOT NULL DEFAULT false,
    "completedAt" TIMESTAMPTZ(3),
    "deadlineType" "DeadlineType",
    "baseDate" DATE,
    "proposedDueDate" DATE,
    "deadlineConfirmedAt" TIMESTAMPTZ(3),
    "deadlineConfirmedById" UUID,
    "deadlineRuleVersion" VARCHAR(64),
    "alertDays" JSONB NOT NULL DEFAULT '[7,3,1]',
    "lastAlertedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "Task_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TimelineEvent" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "eventDate" DATE NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" BYTEA,
    "sourceDocumentId" UUID,
    "isAiGenerated" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "TimelineEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CaseAnalysis" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "summary" BYTEA NOT NULL,
    "generatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "modelVersion" VARCHAR(128) NOT NULL,
    "isConfirmed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "CaseAnalysis_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DocumentDraft" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "docType" "DraftType" NOT NULL,
    "content" BYTEA NOT NULL,
    "modelVersion" VARCHAR(128) NOT NULL,
    "status" "DraftStatus" NOT NULL DEFAULT 'DRAFT',
    "adoptedDocumentId" UUID,
    "createdBy" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "DocumentDraft_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "email" VARCHAR(254),
    "phone" BYTEA,
    "phoneLookupHash" BYTEA,
    "passwordHash" TEXT NOT NULL,
    "name" VARCHAR(128) NOT NULL,
    "barLicenseNo" BYTEA,
    "tier" "UserTier" NOT NULL DEFAULT 'FREE',
    "tierExpireAt" TIMESTAMPTZ(3),
    "storageQuotaBytes" BIGINT NOT NULL DEFAULT 1073741824,
    "storageUsedBytes" BIGINT NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Case" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "caseNo" VARCHAR(80) NOT NULL,
    "cause" VARCHAR(128) NOT NULL,
    "court" VARCHAR(128) NOT NULL,
    "judge" VARCHAR(128),
    "clerk" VARCHAR(128),
    "clerkPhone" BYTEA,
    "fee" DECIMAL(14,2),
    "feeStatus" "FeeStatus" NOT NULL DEFAULT 'UNPAID',
    "stage" "CaseStage" NOT NULL DEFAULT 'FIRST_INSTANCE',
    "status" "CaseStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" BYTEA,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "Case_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CaseParty" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "role" "PartyRole" NOT NULL,
    "name" VARCHAR(128) NOT NULL,
    "idCard" BYTEA,
    "phone" BYTEA,
    "address" BYTEA,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "CaseParty_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CaseMember" (
    "id" UUID NOT NULL,
    "caseId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "role" "MemberRole" NOT NULL DEFAULT 'VIEWER',
    "invitedBy" UUID NOT NULL,
    "invitedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acceptedAt" TIMESTAMPTZ(3),
    "status" "MemberStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "deletedAt" TIMESTAMPTZ(3),

    CONSTRAINT "CaseMember_pkey" PRIMARY KEY ("id")
);


COMMIT;
