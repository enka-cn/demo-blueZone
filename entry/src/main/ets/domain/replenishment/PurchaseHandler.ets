import { IdGen, ImageSource, REMAINING_LEVELS } from '../../common/Common';
import { InventoryItem, MissingItem, RecipeCandidate, Snapshot } from '../../data/model/Models';
import { SnapshotManager } from '../inventory/SnapshotManager';
import { RecognitionNormalizer } from '../recognition/RecognitionNormalizer';
import { GenerationOrchestrator } from '../generation/GenerationOrchestrator';
import { SystemAdapter } from '../../adapter/system/SystemAdapter';

/**
 * 补货入库（FR-26 / FR-27）。
 * 买下的品类并入当前库存（不产生历史快照），随后重算所有候选菜谱的缺项：
 * 买一样可能让好几道菜都不再缺东西，重新生成时也用更新后的库存。
 */
export class PurchaseHandler {
  /** 买下一样：写入库存 → 重算全部候选菜谱缺项，返回更新后的候选列表。 */
  static async buy(item: MissingItem): Promise<RecipeCandidate[]> {
    const snapshot: Snapshot | null = SnapshotManager.current();
    const items: InventoryItem[] = snapshot !== null ? snapshot.items : [];
    const key: string = RecognitionNormalizer.normalize(item.category);

    const next: InventoryItem[] = [];
    let merged: boolean = false;
    for (const i of items) {
      if (i.normalizedKey === key) {
        merged = true;
        next.push({
          id: i.id,
          category: i.category,
          normalizedKey: i.normalizedKey,
          remaining: REMAINING_LEVELS[0],
          isExpiring: false,
          firstSeenAt: i.firstSeenAt
        });
      } else {
        next.push(i);
      }
    }
    if (!merged) {
      next.push({
        id: IdGen.next('item'),
        category: key,
        normalizedKey: key,
        remaining: REMAINING_LEVELS[0],
        isExpiring: false,
        firstSeenAt: SystemAdapter.nowIso()
      });
    }

    await SnapshotManager.updateItems(next);
    return GenerationOrchestrator.refreshMissing(next);
  }

  /** 这条缺项是否已经被买进冰箱。 */
  static isPurchased(category: string): boolean {
    const snapshot: Snapshot | null = SnapshotManager.current();
    if (snapshot === null) {
      return false;
    }
    const key: string = RecognitionNormalizer.normalize(category);
    for (const i of snapshot.items) {
      if (i.normalizedKey === key) {
        return true;
      }
    }
    return false;
  }
}
