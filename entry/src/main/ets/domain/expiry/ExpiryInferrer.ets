import { AppConfig, DateUtil } from '../../common/Common';
import { ExpiryRecord, InventoryItem } from '../../data/model/Models';
import { Keys, KvStore } from '../../data/kv/KvStore';
import { SystemAdapter } from '../../adapter/system/SystemAdapter';

/**
 * 临期推断（§4.4 / FR-05）。
 * 按新增项首次出现时间 + 品类默认保鲜天数推断临期；允许一键覆盖。
 * 不做 350+ 食材保质期模板库，不做精确天数倒计时。
 */
export class ExpiryInferrer {
  private static readonly LEAFY: string[] = ['菠菜', '生菜', '青菜', '白菜', '油菜', '香菜'];
  private static readonly MEAT: string[] = ['五花肉', '猪肉', '牛肉', '鸡肉', '羊肉', '鱼', '虾'];
  private static readonly ROOT: string[] = ['胡萝卜', '马铃薯', '洋葱', '南瓜', '红薯', '山药'];
  private static readonly DAIRY: string[] = ['牛奶', '酸奶', '豆腐'];

  /** 品类默认保鲜天数（小表，非精确模板库）。 */
  static defaultShelfLifeDays(category: string): number {
    if (ExpiryInferrer.contains(ExpiryInferrer.LEAFY, category)) {
      return 3;
    }
    if (ExpiryInferrer.contains(ExpiryInferrer.MEAT, category)) {
      return 3;
    }
    if (category === '鸡蛋') {
      return 21;
    }
    if (ExpiryInferrer.contains(ExpiryInferrer.DAIRY, category)) {
      return 7;
    }
    if (ExpiryInferrer.contains(ExpiryInferrer.ROOT, category)) {
      return 14;
    }
    return 5;
  }

  /** 依据首次出现时间推断是否临期。 */
  static inferExpiring(category: string, firstSeenAt: string): boolean {
    const days: number = ExpiryInferrer.defaultShelfLifeDays(category);
    const elapsed: number = DateUtil.daysBetween(firstSeenAt, SystemAdapter.nowIso());
    return elapsed >= days;
  }

  /** 重建全部推断记录（随快照更新）。 */
  static infer(items: InventoryItem[]): ExpiryRecord[] {
    const existing: Map<string, ExpiryRecord> = ExpiryInferrer.recordMap();
    const records: ExpiryRecord[] = [];
    for (const item of items) {
      const prev: ExpiryRecord | undefined = existing.get(item.id);
      const inferred: boolean = ExpiryInferrer.inferExpiring(item.category, item.firstSeenAt);
      records.push({
        itemId: item.id,
        firstSeenAt: item.firstSeenAt,
        defaultShelfLifeDays: ExpiryInferrer.defaultShelfLifeDays(item.category),
        inferredExpiring: prev !== undefined && prev.overridden ? prev.inferredExpiring : inferred,
        overridden: prev !== undefined ? prev.overridden : false
      });
    }
    return records;
  }

  static async persist(records: ExpiryRecord[]): Promise<void> {
    await KvStore.putObject<ExpiryRecord[]>(Keys.EXPIRY_INFERRED, records);
  }

  static all(): ExpiryRecord[] {
    return KvStore.getObject<ExpiryRecord[]>(Keys.EXPIRY_INFERRED) ?? [];
  }

  /** 一键覆盖：标记 / 取消临期（FR-05）。 */
  static async override(itemId: string, expiring: boolean): Promise<void> {
    const records: ExpiryRecord[] = ExpiryInferrer.all();
    const next: ExpiryRecord[] = records.map((r: ExpiryRecord): ExpiryRecord => {
      if (r.itemId !== itemId) {
        return r;
      }
      return {
        itemId: r.itemId,
        firstSeenAt: r.firstSeenAt,
        defaultShelfLifeDays: r.defaultShelfLifeDays,
        inferredExpiring: expiring,
        overridden: true
      };
    });
    await ExpiryInferrer.persist(next);
  }

  /** 将推断结果落到库存项（供列表展示与临期优先使用）。 */
  static async applyToItems(items: InventoryItem[]): Promise<InventoryItem[]> {
    const records: ExpiryRecord[] = ExpiryInferrer.infer(items);
    await ExpiryInferrer.persist(records);
    const expiringSet: Set<string> = new Set<string>();
    for (const r of records) {
      if (r.inferredExpiring) {
        expiringSet.add(r.itemId);
      }
    }
    return items.map((i: InventoryItem): InventoryItem => {
      return {
        id: i.id,
        category: i.category,
        normalizedKey: i.normalizedKey,
        remaining: i.remaining,
        isExpiring: expiringSet.has(i.id),
        firstSeenAt: i.firstSeenAt
      };
    });
  }

  /** 临期品类名（供生成 Prompt 临期优先约束）。 */
  static expiringCategories(items: InventoryItem[]): string[] {
    const result: string[] = [];
    for (const i of items) {
      if (i.isExpiring) {
        result.push(i.category);
      }
    }
    return result;
  }

  static schemaVersion(): number {
    return AppConfig.SCHEMA_VERSION;
  }

  private static recordMap(): Map<string, ExpiryRecord> {
    const m: Map<string, ExpiryRecord> = new Map<string, ExpiryRecord>();
    for (const r of ExpiryInferrer.all()) {
      m.set(r.itemId, r);
    }
    return m;
  }

  private static contains(list: string[], value: string): boolean {
    for (const v of list) {
      if (value.includes(v) || v.includes(value)) {
        return true;
      }
    }
    return false;
  }
}
