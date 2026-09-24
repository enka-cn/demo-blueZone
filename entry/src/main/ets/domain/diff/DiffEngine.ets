import { AppConfig, DateUtil, FeatureFlags } from '../../common/Common';
import { DiffResult, InventoryItem, Snapshot } from '../../data/model/Models';
import { Keys, KvStore } from '../../data/kv/KvStore';
import { SystemAdapter } from '../../adapter/system/SystemAdapter';

/**
 * 自动差集引擎（§4.3 / FR-20 / FR-25）。
 * 以归一品类键为对齐主键：消失项 = 本次消耗；新增项记首次出现时间并单列展示，不计入单次进度分母。
 */
export class DiffEngine {
  static last(): DiffResult | null {
    return KvStore.getObject<DiffResult>(Keys.DIFF_LAST);
  }

  /**
   * 计算差集。仅在两次快照均来自「用户确认」时执行（抗噪，FR-25）。
   * history 为空（首次拍照）时不产生消耗，返回 null。
   */
  static async compute(current: Snapshot, history: Snapshot | null): Promise<DiffResult | null> {
    if (history === null) {
      return null;
    }
    const curKeys: Set<string> = DiffEngine.keySet(current.items);
    const hisKeys: Set<string> = DiffEngine.keySet(history.items);

    const consumed: InventoryItem[] = history.items.filter(
      (i: InventoryItem): boolean => !curKeys.has(i.normalizedKey));
    const added: InventoryItem[] = current.items.filter(
      (i: InventoryItem): boolean => !hisKeys.has(i.normalizedKey));

    const result: DiffResult = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      computedAt: SystemAdapter.nowIso(),
      fromSnapshotAt: history.confirmedAt,
      toSnapshotAt: current.confirmedAt,
      consumed: consumed,
      added: added
    };
    await KvStore.putObject<DiffResult>(Keys.DIFF_LAST, result);
    return result;
  }

  /** 降级路径：名称稳定性不达标时，由用户确认消耗项（NFR-12 / FR-20）。 */
  static async fromUserSelection(current: Snapshot, history: Snapshot | null,
    selectedKeys: string[]): Promise<DiffResult> {
    const selected: Set<string> = new Set<string>();
    for (const k of selectedKeys) {
      selected.add(k);
    }
    const consumed: InventoryItem[] = [];
    if (history !== null) {
      for (const i of history.items) {
        if (selected.has(i.normalizedKey)) {
          consumed.push(i);
        }
      }
    }
    const result: DiffResult = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      computedAt: SystemAdapter.nowIso(),
      fromSnapshotAt: history !== null ? history.confirmedAt : '',
      toSnapshotAt: current.confirmedAt,
      consumed: consumed,
      added: []
    };
    await KvStore.putObject<DiffResult>(Keys.DIFF_LAST, result);
    return result;
  }

  /** 单次进度分母：仅含本次快照库存项（补货买入不计入）。 */
  static progressTotal(current: Snapshot | null): number {
    return current === null ? 0 : current.items.length;
  }

  /** 单次进度分子：本次消耗项数量。 */
  static progressDone(diff: DiffResult | null): number {
    return diff === null ? 0 : diff.consumed.length;
  }

  static isAutoDiffEnabled(): boolean {
    return FeatureFlags.autoDiffEnabled;
  }

  static describe(diff: DiffResult | null): string {
    if (diff === null) {
      return '再拍一张，就能看到用掉了什么';
    }
    return `上次对比：用掉 ${diff.consumed.length} 样，新放进 ${diff.added.length} 样`;
  }

  private static keySet(items: InventoryItem[]): Set<string> {
    const s: Set<string> = new Set<string>();
    for (const i of items) {
      s.add(i.normalizedKey);
    }
    return s;
  }
}
