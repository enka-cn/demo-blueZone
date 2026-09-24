import { FeatureFlags, MissingStrategy } from '../../common/Common';
import { GenerationSettings, InventoryItem, MissingItem, PreferenceProfile, RecipeCandidate
} from '../../data/model/Models';
import { Keys, KvStore } from '../../data/kv/KvStore';
import { LlmClient } from '../../adapter/llm/LlmClient';
import { RecognitionNormalizer } from '../recognition/RecognitionNormalizer';
import { ExpiryInferrer } from '../expiry/ExpiryInferrer';

/** 缺项上限：能省则省，超过就不再给购买引导。 */
const MAX_MISSING_ITEMS: number = 4;

/**
 * 生成编排器 + 约束策略组（§4.5 / FR-08 ~ FR-17）。
 * 组装约束（临期优先 / 缺材三策略 / 忌口 / 反常识 / 便当三项 / 人数饭量），调用 IF-03，输出校验。
 */
export class GenerationOrchestrator {
  private static readonly FALLBACK_QUALITY_TIP: string = '食材还新不新鲜，结合外观和气味自己判断一下更准。';

  /** 组装生成 Prompt（客户端 user 消息文本）。 */
  static buildPrompt(items: InventoryItem[], settings: GenerationSettings,
    preference: PreferenceProfile, expiring: string[]): string {
    const parts: string[] = [];
    parts.push('你是家常菜谱生成助手，只输出结构化 JSON，不输出解释文字。');
    parts.push(`现有食材：${RecognitionNormalizer.categories(items).join('、')}。`);
    parts.push(`用餐人数：${settings.people} 人；饭量：${settings.appetite}。`);
    if (expiring.length > 0) {
      parts.push(`临期优先：请优先使用 ${expiring.join('、')}（临期食材应排在主要用料中）。`);
    }
    parts.push('清库存优先：主要用料必须来自「现有食材」，尽量一次把同一食材用完；不要为了凑常见搭配而新增购买项。');
    if (settings.missingStrategy === MissingStrategy.OMIT) {
      parts.push('缺项处理（不放也行）：缺的辅料能不放就不放，missingItems 尽量留空数组。');
    } else if (settings.missingStrategy === MissingStrategy.REPLENISH) {
      parts.push(`缺项处理（需要买）：只有这道菜自己必需、又替代不了的食材才列入 missingItems，最多 ${MAX_MISSING_ITEMS} 样，能省则省。`);
    } else {
      parts.push(`缺项处理（换个食材）：缺的辅料优先用现有食材替代，替代不了的才列入 missingItems，最多 ${MAX_MISSING_ITEMS} 样。`);
    }
    if (settings.bentoMode) {
      parts.push('便当场景：需满足三项——① 冷食口感可接受；② 不易出水 / 不易变色；③ 适合提前一晚准备。');
    }
    if (preference.avoidList.length > 0) {
      parts.push(`忌口排除：不得使用 ${preference.avoidList.join('、')}。`);
    }
    parts.push('反常识组合约束：避免明显不搭的食材组合。');
    parts.push('missingItems 每一项要给出购买参考：amount 写常见规格（如「500g」「1 把」「1 袋」），' +
      'price 写参考价（元，保留两位小数），originalPrice 写原价（无折扣填 0），promo 写促销文案（无则空串）。' +
      '价格与规格要像真实生鲜商品一样自然，不要出现「演示 / 示例 / 模拟」这类字样。');
    parts.push(`输出严格 JSON：{"recipes":[{"title":"","summary":"","usedItems":[],` +
      `"missingItems":[{"category":"","strategy":"","amount":"","price":0,"originalPrice":0,"promo":""}],` +
      `"steps":[{"text":""}],"calories":0,"protein":0,"carbs":0,"fat":0,"isBentoFriendly":false,` +
      `"expiringUsed":[],"qualityTip":""}]}；steps 不超过 8 步，步骤里不要写重量 / 克数。`);
    return parts.join('\n');
  }

  /** 生成候选食谱（≤3），并落库 DO-05。 */
  static async generate(items: InventoryItem[], settings: GenerationSettings,
    preference: PreferenceProfile): Promise<RecipeCandidate[]> {
    const expiring: string[] = ExpiryInferrer.expiringCategories(items);
    const prompt: string = GenerationOrchestrator.buildPrompt(items, settings, preference, expiring);
    const used: string[] = RecognitionNormalizer.categories(items);
    const raw: RecipeCandidate[] = await LlmClient.generate(prompt, used, settings, expiring);
    const recipes: RecipeCandidate[] = GenerationOrchestrator.sanitize(raw);
    await KvStore.putObject<RecipeCandidate[]>(Keys.RECIPE_CANDIDATES, recipes);
    return recipes;
  }

  static candidates(): RecipeCandidate[] {
    return KvStore.getObject<RecipeCandidate[]>(Keys.RECIPE_CANDIDATES) ?? [];
  }

  static findById(id: string): RecipeCandidate | null {
    for (const r of GenerationOrchestrator.candidates()) {
      if (r.id === id) {
        return r;
      }
    }
    return null;
  }

  /** 输出校验：步骤 ≤8、缺项 ≤4、品质提示降级、营养估算值兜底。 */
  private static sanitize(raw: RecipeCandidate[]): RecipeCandidate[] {
    const result: RecipeCandidate[] = [];
    for (const r of raw) {
      const steps = r.steps.slice(0, 8);
      let tip: string = r.qualityTip;
      if (!FeatureFlags.qualityTipEnabled || tip.length === 0) {
        tip = GenerationOrchestrator.FALLBACK_QUALITY_TIP;
      }
      result.push({
        id: r.id,
        title: r.title,
        summary: r.summary,
        usedItems: r.usedItems,
        missingItems: GenerationOrchestrator.trimMissing(r.missingItems),
        steps: steps,
        nutrition: r.nutrition,
        isBentoFriendly: r.isBentoFriendly,
        expiringUsed: r.expiringUsed,
        qualityTip: tip
      });
    }
    return result;
  }

  /** 缺项去重 + 截断到上限：购买引导越少越好。 */
  private static trimMissing(items: MissingItem[]): MissingItem[] {
    const result: MissingItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const m of items) {
      const name: string = RecognitionNormalizer.normalize(m.category);
      if (name.length === 0 || seen.has(name)) {
        continue;
      }
      seen.add(name);
      result.push({
        category: name,
        strategy: m.strategy.length > 0 ? m.strategy : MissingStrategy.SUBSTITUTE,
        amount: m.amount,
        price: m.price,
        originalPrice: m.originalPrice,
        promo: m.promo
      });
      if (result.length >= MAX_MISSING_ITEMS) {
        break;
      }
    }
    return result;
  }

  /**
   * 库存变化（补货入库）后重算所有候选菜谱的缺项：
   * 已经买到的品类不再是缺项 —— 买一样可能让好几道菜都不再缺东西。
   */
  static async refreshMissing(items: InventoryItem[]): Promise<RecipeCandidate[]> {
    const have: Set<string> = new Set<string>();
    for (const i of items) {
      have.add(i.normalizedKey);
    }
    const updated: RecipeCandidate[] = [];
    for (const c of GenerationOrchestrator.candidates()) {
      const kept: MissingItem[] = [];
      const usedItems: string[] = [];
      for (const u of c.usedItems) {
        usedItems.push(u);
      }
      for (const m of c.missingItems) {
        const key: string = RecognitionNormalizer.normalize(m.category);
        if (have.has(key)) {
          // 已经买到了：从缺项移出，并补进「用到的食材」。
          if (usedItems.indexOf(key) < 0) {
            usedItems.push(key);
          }
        } else {
          kept.push(m);
        }
      }
      updated.push({
        id: c.id,
        title: c.title,
        summary: c.summary,
        usedItems: usedItems,
        missingItems: kept,
        steps: c.steps,
        nutrition: c.nutrition,
        isBentoFriendly: c.isBentoFriendly,
        expiringUsed: c.expiringUsed,
        qualityTip: c.qualityTip
      });
    }
    await KvStore.putObject<RecipeCandidate[]>(Keys.RECIPE_CANDIDATES, updated);
    return updated;
  }

  static defaultStrategy(): string {
    return MissingStrategy.SUBSTITUTE;
  }
}
