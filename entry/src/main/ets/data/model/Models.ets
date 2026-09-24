/**
 * DO-01 ~ DO-11 序列化模型（§5 数据模型）。
 * 全部以「键值 + JSON」承载于 Preferences（A-5），每个对象带 schemaVersion。
 */

/** DO-01 / DO-02 库存项。 */
export interface InventoryItem {
  id: string;
  category: string;
  normalizedKey: string;
  remaining: string;
  isExpiring: boolean;
  firstSeenAt: string;
}

/** DO-01 当前库存快照 / DO-02 历史快照（只读）。 */
export interface Snapshot {
  schemaVersion: number;
  capturedAt: string;
  confirmedAt: string;
  source: string;
  items: InventoryItem[];
}

/** DO-03 本次消耗（自动差集结果）。 */
export interface DiffResult {
  schemaVersion: number;
  computedAt: string;
  fromSnapshotAt: string;
  toSnapshotAt: string;
  consumed: InventoryItem[];
  added: InventoryItem[];
}

/** DO-04 临期推断项。 */
export interface ExpiryRecord {
  itemId: string;
  firstSeenAt: string;
  defaultShelfLifeDays: number;
  inferredExpiring: boolean;
  overridden: boolean;
}

/** 识别结果的单条品类（不含重量，RQ-01）。 */
export interface RecognizedItem {
  category: string;
  confidence: number;
  /** 模型给出的默认余量档位，取值须落在 REMAINING_LEVELS 内；缺失表示模型没判断出来。 */
  remaining?: string;
}

/** IF-02 多模态识别响应。failed 为真表示真实链路识别失败，items 必为空。 */
export interface RecognitionResult {
  items: RecognizedItem[];
  notes: string;
  failed?: boolean;
  errorMessage?: string;
}

/** 菜谱步骤（FR-15：步骤 ≤8）。 */
export interface RecipeStep {
  index: number;
  text: string;
}

/** 营养估算值（展示级，非精确）。 */
export interface Nutrition {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

/**
 * 缺材项及其策略归属（FR-10 三策略）+ 参考购买信息。
 * 规格 / 价格 / 折扣由生成模型给出（真实链路与模拟链路同字段），客户端只负责展示与入库。
 */
export interface MissingItem {
  category: string;
  strategy: string;
  /** 建议购买规格，如「500g」「1 把」。 */
  amount: string;
  /** 参考价（元）。 */
  price: number;
  /** 原价（元）；无折扣为 0。 */
  originalPrice: number;
  /** 促销文案，如「今日特价」；可为空。 */
  promo: string;
}

/** DO-05 候选食谱。 */
export interface RecipeCandidate {
  id: string;
  title: string;
  summary: string;
  usedItems: string[];
  missingItems: MissingItem[];
  steps: RecipeStep[];
  nutrition: Nutrition;
  isBentoFriendly: boolean;
  expiringUsed: string[];
  qualityTip: string;
}

/** DO-06 生成设置。 */
export interface GenerationSettings {
  schemaVersion: number;
  people: number;
  appetite: string;
  bentoMode: boolean;
  missingStrategy: string;
}

/** DO-07 用户偏好（忌口 / 反常识）。 */
export interface PreferenceProfile {
  schemaVersion: number;
  avoidList: string[];
}

/** DO-08 单次消耗进度（FR-20）。 */
export interface FeedbackProgress {
  schemaVersion: number;
  lastDone: number;
  lastTotal: number;
  updatedAt: string;
}

/** DO-09 周度消耗计数。 */
export interface WeeklyCounter {
  schemaVersion: number;
  weekStart: string;
  count: number;
}

/** DO-10 省钱累计（FR-19）。 */
export interface SavingsRecord {
  schemaVersion: number;
  totalSaved: number;
  lastUpdated: string;
}

/** 匿名会话标识（本地，DO-10 说明中的会话键）。 */
export interface SessionAnon {
  schemaVersion: number;
  sessionId: string;
  createdAt: string;
}

/** DO-11 商业化披露上下文（仅补货分支生命周期，不持久化）。 */
export interface DisclosureContext {
  triggered: boolean;
  disclosureShown: boolean;
  partner: string;
  commission: string;
}

/** 补货判定结果。 */
export interface ReplenishDecision {
  triggered: boolean;
  missingItems: MissingItem[];
  /** 供货来源（披露用）。 */
  sourceLabel: string;
  /** 价格说明（披露用）。 */
  disclosureText: string;
}

/** 路由参数：拍照 → 校对。 */
export interface CaptureParams {
  uri: string;
  source: string;
  presetKey: string;
}

/** 路由参数：候选 → 详情。 */
export interface RecipeParams {
  recipeId: string;
}

/** 路由参数：菜谱详情 → 补货页（只带这道菜自己）。 */
export interface ReplenishParams {
  recipeId: string;
}
