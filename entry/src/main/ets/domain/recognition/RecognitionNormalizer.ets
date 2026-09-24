import { DateUtil, IdGen, REMAINING_LEVELS, remainingIndex } from '../../common/Common';
import { InventoryItem, RecognizedItem } from '../../data/model/Models';

/**
 * 识别结果规范化（§4.2）。
 * 统一常用名 + 归一品类键（normalizedKey），服务名称稳定性（NFR-12）与自动差集对齐（FR-25）。
 */
export class RecognitionNormalizer {
  private static aliasMap: Map<string, string> | null = null;

  private static map(): Map<string, string> {
    if (RecognitionNormalizer.aliasMap === null) {
      const m: Map<string, string> = new Map<string, string>();
      m.set('番茄', '西红柿');
      m.set('小番茄', '西红柿');
      m.set('圣女果', '西红柿');
      m.set('土鸡蛋', '鸡蛋');
      m.set('柴鸡蛋', '鸡蛋');
      m.set('青菜', '菠菜');
      m.set('油菜', '菠菜');
      m.set('小白菜', '菠菜');
      m.set('猪肉', '五花肉');
      m.set('里脊', '五花肉');
      m.set('土豆', '马铃薯');
      m.set('红萝卜', '胡萝卜');
      RecognitionNormalizer.aliasMap = m;
    }
    return RecognitionNormalizer.aliasMap;
  }

  /** 归一为统一常用名。 */
  static normalize(category: string): string {
    const key: string = category.trim();
    if (key.length === 0) {
      return '';
    }
    const canonical: string | undefined = RecognitionNormalizer.map().get(key);
    return canonical !== undefined ? canonical : key;
  }

  /** 归一品类键：差集对齐主键。 */
  static normalizedKey(category: string): string {
    return RecognitionNormalizer.normalize(category);
  }

  /**
   * 将识别结果构建为库存项：按归一品类键去重，并尽量沿用既有项（余量 / 首次出现时间）。
   */
  static buildItems(recognized: RecognizedItem[], existing: InventoryItem[]): InventoryItem[] {
    const byKey: Map<string, InventoryItem> = new Map<string, InventoryItem>();
    for (const e of existing) {
      byKey.set(e.normalizedKey, e);
    }
    const seen: Set<string> = new Set<string>();
    const result: InventoryItem[] = [];
    for (const r of recognized) {
      const name: string = RecognitionNormalizer.normalize(r.category);
      if (name.length === 0 || seen.has(name)) {
        continue;
      }
      seen.add(name);
      const prev: InventoryItem | undefined = byKey.get(name);
      result.push({
        id: prev !== undefined ? prev.id : IdGen.next('item'),
        category: name,
        normalizedKey: name,
        remaining: prev !== undefined ? prev.remaining : RecognitionNormalizer.remainingOrDefault(r.remaining),
        isExpiring: prev !== undefined ? prev.isExpiring : false,
        firstSeenAt: prev !== undefined ? prev.firstSeenAt : DateUtil.nowIso()
      });
    }
    return result;
  }

  /** 采用模型给出的余量档位；缺失或不在档位表内时回退到默认档，保证滑动条始终有合法值。 */
  private static remainingOrDefault(level: string | undefined): string {
    if (level !== undefined && remainingIndex(level) >= 0) {
      return level;
    }
    return REMAINING_LEVELS[0];
  }

  /** FR-02：新增自定义品类。 */
  static addItem(items: InventoryItem[], category: string): InventoryItem[] {
    const name: string = RecognitionNormalizer.normalize(category);
    if (name.length === 0) {
      return items;
    }
    const next: InventoryItem[] = items.slice();
    next.push({
      id: IdGen.next('item'),
      category: name,
      normalizedKey: name,
      remaining: REMAINING_LEVELS[0],
      isExpiring: false,
      firstSeenAt: DateUtil.nowIso()
    });
    return next;
  }

  /** FR-02：删除识别项。 */
  static removeItem(items: InventoryItem[], id: string): InventoryItem[] {
    return items.filter((i: InventoryItem): boolean => i.id !== id);
  }

  /** FR-02：改品类。 */
  static renameItem(items: InventoryItem[], id: string, category: string): InventoryItem[] {
    const name: string = RecognitionNormalizer.normalize(category);
    if (name.length === 0) {
      return items;
    }
    return items.map((i: InventoryItem): InventoryItem => {
      if (i.id !== id) {
        return i;
      }
      return {
        id: i.id,
        category: name,
        normalizedKey: name,
        remaining: i.remaining,
        isExpiring: i.isExpiring,
        firstSeenAt: i.firstSeenAt
      };
    });
  }

  /** FR-02：合并重复项（保留 target，删除 source）。 */
  static mergeItems(items: InventoryItem[], targetId: string, sourceId: string): InventoryItem[] {
    const target: InventoryItem | undefined = items.find((i: InventoryItem): boolean => i.id === targetId);
    if (target === undefined) {
      return items;
    }
    const source: InventoryItem | undefined = items.find((i: InventoryItem): boolean => i.id === sourceId);
    if (source === undefined) {
      return items;
    }
    const merged: InventoryItem[] = [];
    for (const i of items) {
      if (i.id === sourceId) {
        continue;
      }
      if (i.id === targetId) {
        const earlier: string =
          DateUtil.parse(source.firstSeenAt).getTime() < DateUtil.parse(target.firstSeenAt).getTime()
            ? source.firstSeenAt : target.firstSeenAt;
        merged.push({
          id: target.id,
          category: target.category,
          normalizedKey: target.normalizedKey,
          remaining: target.remaining,
          isExpiring: target.isExpiring || source.isExpiring,
          firstSeenAt: earlier
        });
        continue;
      }
      merged.push(i);
    }
    return merged;
  }

  /** FR-04：设置余量档位（不出现数字键盘）。 */
  static setRemaining(items: InventoryItem[], id: string, remaining: string): InventoryItem[] {
    return items.map((i: InventoryItem): InventoryItem => {
      if (i.id !== id) {
        return i;
      }
      return {
        id: i.id,
        category: i.category,
        normalizedKey: i.normalizedKey,
        remaining: remaining,
        isExpiring: i.isExpiring,
        firstSeenAt: i.firstSeenAt
      };
    });
  }

  /** 全部品类名（供生成与补货判定）。 */
  static categories(items: InventoryItem[]): string[] {
    return items.map((i: InventoryItem): string => i.category);
  }

  /** 归一品类键集合。 */
  static keySet(items: InventoryItem[]): Set<string> {
    const s: Set<string> = new Set<string>();
    for (const i of items) {
      s.add(i.normalizedKey);
    }
    return s;
  }
}
