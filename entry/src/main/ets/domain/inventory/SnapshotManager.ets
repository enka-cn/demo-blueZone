import { AppConfig, DateUtil, ImageSource } from '../../common/Common';
import { InventoryItem, Snapshot } from '../../data/model/Models';
import { Keys, KvStore } from '../../data/kv/KvStore';
import { SystemAdapter } from '../../adapter/system/SystemAdapter';

/**
 * 快照管理器（§4.3）。
 * 用户确认后写为当前快照 DO-01，原当前快照转存为历史快照 DO-02（只读，仅保留上一张）。
 */
export class SnapshotManager {
  static current(): Snapshot | null {
    return KvStore.getObject<Snapshot>(Keys.SNAPSHOT_CURRENT);
  }

  static history(): Snapshot | null {
    return KvStore.getObject<Snapshot>(Keys.SNAPSHOT_HISTORY);
  }

  /** 是否超过过期阈值（FR-24，默认 24h 可配置）。 */
  static isExpired(snapshot: Snapshot): boolean {
    const hours: number = DateUtil.hoursBetween(snapshot.confirmedAt, SystemAdapter.nowIso());
    return hours > AppConfig.expiryHours;
  }

  /** 快照时间文案（用户视角：拍摄时间 / 距今多久）。 */
  static freshnessLabel(snapshot: Snapshot): string {
    if (SnapshotManager.isExpired(snapshot)) {
      return `拍于 ${DateUtil.format(snapshot.confirmedAt)}`;
    }
    return `${DateUtil.relative(snapshot.confirmedAt)}拍的`;
  }

  /** 提交本次快照：原当前快照转历史（仅保留上一张）。 */
  static async commit(items: InventoryItem[], capturedAt: string, source: string): Promise<Snapshot> {
    const prev: Snapshot | null = SnapshotManager.current();
    if (prev !== null) {
      await KvStore.putObject<Snapshot>(Keys.SNAPSHOT_HISTORY, prev);
    }
    const snapshot: Snapshot = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      capturedAt: capturedAt,
      confirmedAt: SystemAdapter.nowIso(),
      source: source,
      items: items
    };
    await KvStore.putObject<Snapshot>(Keys.SNAPSHOT_CURRENT, snapshot);
    return snapshot;
  }

  /** 直接写入快照（种子 / 演示数据准备）。 */
  static async replace(snapshot: Snapshot): Promise<void> {
    await KvStore.putObject<Snapshot>(Keys.SNAPSHOT_CURRENT, snapshot);
  }

  /**
   * 补货入库：就地更新当前库存（不产生历史快照，也不刷新拍摄时间，避免掩盖「该重新拍照了」）。
   */
  static async updateItems(items: InventoryItem[]): Promise<Snapshot> {
    const current: Snapshot | null = SnapshotManager.current();
    const snapshot: Snapshot = {
      schemaVersion: current !== null ? current.schemaVersion : AppConfig.SCHEMA_VERSION,
      capturedAt: current !== null ? current.capturedAt : SystemAdapter.nowIso(),
      confirmedAt: current !== null ? current.confirmedAt : SystemAdapter.nowIso(),
      source: current !== null ? current.source : ImageSource.PURCHASE,
      items: items
    };
    await SnapshotManager.replace(snapshot);
    return snapshot;
  }

  static async replaceHistory(snapshot: Snapshot): Promise<void> {
    await KvStore.putObject<Snapshot>(Keys.SNAPSHOT_HISTORY, snapshot);
  }

  static isEmpty(): boolean {
    return SnapshotManager.current() === null;
  }

  static defaultSource(): string {
    return ImageSource.PRESET;
  }
}
