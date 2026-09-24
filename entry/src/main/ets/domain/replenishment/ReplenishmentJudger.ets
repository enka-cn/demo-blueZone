import { FeatureFlags } from '../../common/Common';
import { DisclosureContext, MissingItem, ReplenishDecision } from '../../data/model/Models';

/**
 * 补货判定 + 披露控制（§4.7 / FR-26 / FR-27 / NFR-11）。
 * 输入是「当前这道菜谱自己的缺项」：只缺 1~4 样才进入补货分支；
 * 规格 / 价格 / 折扣由生成模型给出，本模块只做边界控制与披露文案。
 * 披露状态仅存活于补货分支生命周期，不持久化。
 */
export class ReplenishmentJudger {
  /** 补货分支的缺项上限：能省则省，超过就不再给购买引导。 */
  static readonly MAX_MISSING: number = 4;

  private static readonly SOURCE_LABEL: string = '本地生鲜';
  private static readonly DISCLOSURE: string = '价格为参考值，实际以门店为准';

  /** DO-11：会话内存中的披露上下文（不写入持久化）。 */
  private static disclosure: DisclosureContext = {
    triggered: false,
    disclosureShown: false,
    partner: '',
    commission: ''
  };

  static judge(recipeMissing: MissingItem[]): ReplenishDecision {
    if (!FeatureFlags.replenishBranchEnabled) {
      ReplenishmentJudger.reset();
      return { triggered: false, missingItems: [], sourceLabel: '', disclosureText: '' };
    }
    const items: MissingItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const m of recipeMissing) {
      if (m.category.length === 0 || seen.has(m.category)) {
        continue;
      }
      seen.add(m.category);
      items.push(m);
    }
    if (items.length === 0 || items.length > ReplenishmentJudger.MAX_MISSING) {
      ReplenishmentJudger.reset();
      return { triggered: false, missingItems: [], sourceLabel: '', disclosureText: '' };
    }
    ReplenishmentJudger.disclosure = {
      triggered: true,
      disclosureShown: true,
      partner: ReplenishmentJudger.SOURCE_LABEL,
      commission: ''
    };
    return {
      triggered: true,
      missingItems: items,
      sourceLabel: ReplenishmentJudger.SOURCE_LABEL,
      disclosureText: ReplenishmentJudger.DISCLOSURE
    };
  }

  static context(): DisclosureContext {
    return ReplenishmentJudger.disclosure;
  }

  static reset(): void {
    ReplenishmentJudger.disclosure = {
      triggered: false,
      disclosureShown: false,
      partner: '',
      commission: ''
    };
  }

  static isBranchEnabled(): boolean {
    return FeatureFlags.replenishBranchEnabled;
  }
}
