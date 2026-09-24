import { AppConfig, DateUtil, FeatureFlags, Logger } from '../../common/Common';
import { FeedbackProgress, SavingsRecord, WeeklyCounter } from '../../data/model/Models';
import { Keys, KvStore } from '../../data/kv/KvStore';
import { SystemAdapter } from '../../adapter/system/SystemAdapter';

/**
 * 反馈与成就（§4.8 / FR-19 / FR-20）。
 * 单次进度分母仅含本次快照库存项；周度计数为纯事件累计；省钱以「相比点外卖省下的钱」口径累计。
 */
export class FeedbackCalculator {
  /** 每顿自炊相比外卖的估算节省（元），用于省钱累计。 */
  private static readonly SAVING_PER_MEAL: number = 25;

  static progress(): FeedbackProgress {
    const p: FeedbackProgress | null = KvStore.getObject<FeedbackProgress>(Keys.FEEDBACK_PROGRESS);
    if (p !== null) {
      return p;
    }
    return {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      lastDone: 0,
      lastTotal: 0,
      updatedAt: ''
    };
  }

  /** 记录单次消耗进度：分母仅含本次快照库存项（FR-20）。 */
  static async recordConsumption(consumed: number, total: number): Promise<void> {
    const record: FeedbackProgress = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      lastDone: consumed,
      lastTotal: total,
      updatedAt: SystemAdapter.nowIso()
    };
    await KvStore.putObject<FeedbackProgress>(Keys.FEEDBACK_PROGRESS, record);
    await FeedbackCalculator.bumpWeekly(consumed);
  }

  static weekly(): WeeklyCounter {
    const w: WeeklyCounter | null = KvStore.getObject<WeeklyCounter>(Keys.FEEDBACK_WEEKLY);
    const weekStart: string = DateUtil.weekStartIso(new Date());
    if (w === null || w.weekStart !== weekStart) {
      return {
        schemaVersion: AppConfig.SCHEMA_VERSION,
        weekStart: weekStart,
        count: 0
      };
    }
    return w;
  }

  /** 周度计数：纯事件累计，按周滚动，不依赖库存连续性（FR-20）。 */
  static async bumpWeekly(consumed: number): Promise<void> {
    if (consumed <= 0) {
      return;
    }
    const current: WeeklyCounter = FeedbackCalculator.weekly();
    const next: WeeklyCounter = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      weekStart: current.weekStart,
      count: current.count + consumed
    };
    await KvStore.putObject<WeeklyCounter>(Keys.FEEDBACK_WEEKLY, next);
  }

  static savings(): SavingsRecord {
    const s: SavingsRecord | null = KvStore.getObject<SavingsRecord>(Keys.FEEDBACK_SAVINGS);
    if (s !== null) {
      return s;
    }
    return {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      totalSaved: 0,
      lastUpdated: ''
    };
  }

  /** 省钱累计：可整体关闭而不影响主链路（NFR-06 / UC-23）。 */
  static async recordMeal(): Promise<void> {
    if (!FeatureFlags.savingsFeedbackEnabled) {
      Logger.info('savings feedback disabled, skip');
      return;
    }
    const current: SavingsRecord = FeedbackCalculator.savings();
    const next: SavingsRecord = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      totalSaved: current.totalSaved + FeedbackCalculator.SAVING_PER_MEAL,
      lastUpdated: SystemAdapter.nowIso()
    };
    await KvStore.putObject<SavingsRecord>(Keys.FEEDBACK_SAVINGS, next);
  }

  /** 省钱统计说明（用户可读口径，FR-19）。 */
  static savingsFormula(): string {
    return `按每次做菜比点外卖省下 ${FeedbackCalculator.SAVING_PER_MEAL} 元估算，仅供参考。`;
  }

  static progressText(): string {
    const p: FeedbackProgress = FeedbackCalculator.progress();
    if (p.lastTotal === 0) {
      return '还没有记录';
    }
    return `上次用掉 ${p.lastDone} 样，共 ${p.lastTotal} 样`;
  }

  static weeklyText(): string {
    const w: WeeklyCounter = FeedbackCalculator.weekly();
    return `这周用掉 ${w.count} 样`;
  }

  static savingsText(): string {
    if (!FeatureFlags.savingsFeedbackEnabled) {
      return '省钱统计已关闭';
    }
    const s: SavingsRecord = FeedbackCalculator.savings();
    return `估算省下 ¥${s.totalSaved}`;
  }

  /** 一键删除全部数据时重置反馈（NFR-04）。 */
  static async reset(): Promise<void> {
    await KvStore.remove(Keys.FEEDBACK_PROGRESS);
    await KvStore.remove(Keys.FEEDBACK_WEEKLY);
    await KvStore.remove(Keys.FEEDBACK_SAVINGS);
  }
}
