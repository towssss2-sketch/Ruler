import { DocumentCategory } from '@prisma/client';

export interface DocumentSuggestion {
  ruleVersion: 'title-v1'; category: DocumentCategory | null;
  reason: 'TITLE_MATCH' | 'NO_TITLE' | 'CONFLICTING_TITLES';
  caseNumbers: string[]; caseNumbersTruncated: boolean; requiresConfirmation: true;
}

const TITLES: Readonly<Record<string, DocumentCategory>> = {
  起诉状: 'PLEADING', 民事起诉状: 'PLEADING', 行政起诉状: 'PLEADING',
  答辩状: 'DEFENSE', 民事答辩状: 'DEFENSE', 行政答辩状: 'DEFENSE',
  证据目录: 'EVIDENCE', 证据清单: 'EVIDENCE', 传票: 'SUMMONS', 开庭传票: 'SUMMONS',
  授权委托书: 'AUTHORIZATION', 庭审笔录: 'HEARING_RECORD', 法庭审理笔录: 'HEARING_RECORD',
  代理词: 'REPRESENTATION', 代理意见: 'REPRESENTATION',
  民事判决书: 'JUDGMENT', 行政判决书: 'JUDGMENT', 刑事判决书: 'JUDGMENT',
  民事裁定书: 'COURT_DOCUMENT', 行政裁定书: 'COURT_DOCUMENT', 刑事裁定书: 'COURT_DOCUMENT',
  应诉通知书: 'COURT_DOCUMENT', 举证通知书: 'COURT_DOCUMENT',
  法律服务合同: 'SERVICE_CONTRACT', 委托代理合同: 'SERVICE_CONTRACT',
};

/** 只对开头独立标题给候选；冲突/不明保留人工选择，不依据文件名、引用或置信度自动归档。 */
export function suggestDocument(text: string): DocumentSuggestion {
  const headings = text.slice(0, 1500).split('\n').map((line): string => line.replace(/[ \t\u3000]/g, '').trim())
    .filter(Boolean).slice(0, 12);
  const categories = new Set(headings.map((line): DocumentCategory | undefined => Object.hasOwn(TITLES, line) ? TITLES[line] : undefined)
    .filter(Boolean));
  const numbers = [...new Set([...text.matchAll(/[（(]([12]\d{3})[）)]([\p{Script=Han}\d]{1,60})号/gu)]
    .map((match): string => `(${match[1]})${match[2]}号`))];
  return { ruleVersion: 'title-v1', category: categories.size === 1 ? [...categories][0]! : null,
    reason: categories.size === 1 ? 'TITLE_MATCH' : categories.size > 1 ? 'CONFLICTING_TITLES' : 'NO_TITLE',
    caseNumbers: numbers.slice(0, 10), caseNumbersTruncated: numbers.length > 10, requiresConfirmation: true };
}
