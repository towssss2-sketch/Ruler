-- 仅开发环境基座探针；无真实用户或案件数据。
CREATE TABLE "EnvironmentProbe" (
    "id" UUID NOT NULL,
    "label" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "EnvironmentProbe_pkey" PRIMARY KEY ("id")
);
