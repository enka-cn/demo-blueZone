import {
  GenerationSettings,
  InventoryItem,
  MissingItem,
  Nutrition,
  PreferenceProfile,
  RecipeCandidate,
  RecipeStep,
  RecognitionResult,
  RecognizedItem,
  Snapshot
} from '../model/Models';
import { AppConfig, Appetite, ImageSource, MissingStrategy } from '../../common/Common';

/** 预置样张（A-8：云真机 / 模拟器无实物冰箱时的输入回退）。 */
export interface PresetSample {
  key: string;
  name: string;
  desc: string;
}

/**
 * Demo 固定输入集（§8.1 数据准备）与离线 Mock 数据源。
 * 预置样张为只读资源，不属用户数据（§5.1 隐私最小化）。
 */
export class SeedData {
  static readonly SAMPLE_FULL: string = 'full';
  static readonly SAMPLE_AFTER: string = 'after';

  static samples(): PresetSample[] {
    return [
      {
        key: SeedData.SAMPLE_FULL,
        name: '冰箱全景',
        desc: '有 6 样食材，适合第一次试用'
      },
      {
        key: SeedData.SAMPLE_AFTER,
        name: '做饭后',
        desc: '有 4 样食材，能看出用掉了什么'
      }
    ];
  }

  /** 预置样张对应的 Mock 识别结果（IF-02 回退）。 */
  static recognitionFor(sampleKey: string): RecognitionResult {
    if (sampleKey === SeedData.SAMPLE_AFTER) {
      const after: RecognizedItem[] = [
        { category: '鸡蛋', confidence: 0.93, remaining: '满' },
        { category: '西红柿', confidence: 0.9, remaining: '半盒' },
        { category: '牛奶', confidence: 0.86, remaining: '少量' },
        { category: '胡萝卜', confidence: 0.81, remaining: '满' }
      ];
      return { items: after, notes: '示例照片的识别结果' };
    }
    const full: RecognizedItem[] = [
      { category: '鸡蛋', confidence: 0.94, remaining: '满' },
      { category: '西红柿', confidence: 0.91, remaining: '半盒' },
      { category: '牛奶', confidence: 0.88, remaining: '少量' },
      { category: '胡萝卜', confidence: 0.83, remaining: '满' },
      { category: '菠菜', confidence: 0.79, remaining: '快没了' },
      { category: '五花肉', confidence: 0.76, remaining: '半盒' }
    ];
    return { items: full, notes: '有遮挡，可能漏认了几样' };
  }

  /** 完整库存快照（用于首次进入即见库存的空态之外演示）。 */
  static seedSnapshot(): Snapshot {
    const items: InventoryItem[] = SeedData.recognitionFor(SeedData.SAMPLE_FULL).items.map(
      (r: RecognizedItem, i: number): InventoryItem => {
        return {
          id: `seed_${i}`,
          category: r.category,
          normalizedKey: r.category,
          remaining: r.remaining !== undefined && r.remaining.length > 0 ? r.remaining : '满',
          isExpiring: false,
          firstSeenAt: new Date().toISOString()
        };
      }
    );
    const now: string = new Date().toISOString();
    return {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      capturedAt: now,
      confirmedAt: now,
      source: ImageSource.PRESET,
      items: items
    };
  }

  static defaultSettings(): GenerationSettings {
    return {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      people: 2,
      appetite: Appetite.NORMAL,
      bentoMode: false,
      missingStrategy: MissingStrategy.SUBSTITUTE
    };
  }

  static defaultPreference(): PreferenceProfile {
    return {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      avoidList: []
    };
  }

  /** 常用忌口候选，供「我的」页快速勾选。 */
  static avoidCandidates(): string[] {
    return ['香菜', '葱', '姜', '蒜', '辣椒', '牛肉', '海鲜'];
  }

  /** 离线 / 无密钥时的内置示例菜谱（IF-03 回退）。示例菜谱本身就是清库存菜谱，不做购买引导。 */
  static mockRecipes(usedCategories: string[], settings: GenerationSettings,
    expiring: string[]): RecipeCandidate[] {
    const main: string = usedCategories.length > 0 ? usedCategories[0] : '鸡蛋';
    const second: string = usedCategories.length > 1 ? usedCategories[1] : '西红柿';
    const bentoMissing: MissingItem[] =
      SeedData.demoMissing(usedCategories, settings, '米饭', ['米', '面条', '馒头', '面包', '米粉'],
        '5kg', 25.9, 32.9, '今日特价');
    const quickMissing: MissingItem[] =
      SeedData.demoMissing(usedCategories, settings, '蒜', [], '200g', 3.5, 0, '');
    const bento: RecipeCandidate = {
      id: 'mock_bento',
      title: `${main}${second}便当`,
      summary: `用冰箱里这 ${usedCategories.length} 样做的便当，放凉也好吃。`,
      usedItems: usedCategories,
      missingItems: bentoMissing,
      steps: SeedData.bentoSteps(main, second),
      nutrition: SeedData.nutrition(520, 26, 58, 18),
      isBentoFriendly: true,
      expiringUsed: expiring,
      qualityTip: '叶菜最好当天吃完。'
    };
    const quick: RecipeCandidate = {
      id: 'mock_quick',
      title: `${main}${second}快手炒`,
      summary: '少油快炒，15 分钟内完成，适合周中晚餐。',
      usedItems: usedCategories,
      missingItems: quickMissing,
      steps: SeedData.quickSteps(main, second),
      nutrition: SeedData.nutrition(430, 22, 36, 20),
      isBentoFriendly: false,
      expiringUsed: expiring,
      qualityTip: '食材新不新鲜，看一眼、闻一下更准。'
    };
    const soup: RecipeCandidate = {
      id: 'mock_soup',
      title: `${main}清汤`,
      summary: '清淡不油腻，正好先用掉快过期的食材。',
      usedItems: usedCategories,
      missingItems: [],
      steps: SeedData.soupSteps(main),
      nutrition: SeedData.nutrition(260, 14, 18, 10),
      isBentoFriendly: false,
      expiringUsed: expiring,
      qualityTip: '汤最好当天喝完。'
    };
    let list: RecipeCandidate[] = [bento, quick, soup];
    if (settings.bentoMode) {
      list = [bento, quick, soup];
    }
    return list.slice(0, AppConfig.MAX_CANDIDATES);
  }

  /** 示例菜谱的缺项：冰箱里确实没有时才给，并带上购买参考（与模型链路同字段）。 */
  private static demoMissing(usedCategories: string[], settings: GenerationSettings, category: string,
    alternatives: string[], amount: string, price: number, originalPrice: number,
    promo: string): MissingItem[] {
    const names: string[] = [category];
    for (const a of alternatives) {
      names.push(a);
    }
    for (const c of usedCategories) {
      if (names.indexOf(c) >= 0) {
        return [];
      }
    }
    return [{
      category: category,
      strategy: settings.missingStrategy,
      amount: amount,
      price: price,
      originalPrice: originalPrice,
      promo: promo
    }];
  }

  private static nutrition(calories: number, protein: number, carbs: number, fat: number): Nutrition {
    return { calories: calories, protein: protein, carbs: carbs, fat: fat };
  }

  private static bentoSteps(main: string, second: string): RecipeStep[] {
    return [
      { index: 1, text: `处理食材：${main} 与 ${second} 洗净切配。` },
      { index: 2, text: '主食提前蒸煮，放凉至室温便于装盒。' },
      { index: 3, text: `热锅少油，先下 ${main} 翻炒至断生。` },
      { index: 4, text: `加入 ${second} 继续翻炒，调入少量盐与生抽。` },
      { index: 5, text: '出锅放凉后装盒，避免水汽影响口感。' },
      { index: 6, text: '冷藏保存，次日食用前充分加热。' }
    ];
  }

  private static quickSteps(main: string, second: string): RecipeStep[] {
    return [
      { index: 1, text: '食材洗净切配，调料备齐。' },
      { index: 2, text: '热锅冷油，下蒜末爆香。' },
      { index: 3, text: `下 ${main} 大火快炒。` },
      { index: 4, text: `加入 ${second} 翻炒均匀。` },
      { index: 5, text: '调味后即可出锅。' }
    ];
  }

  private static soupSteps(main: string): RecipeStep[] {
    return [
      { index: 1, text: `${main} 处理干净，切块备用。` },
      { index: 2, text: '冷水下锅，大火煮沸后撇去浮沫。' },
      { index: 3, text: '转小火慢炖 20 分钟。' },
      { index: 4, text: '加盐调味，撒少量葱花出锅。' }
    ];
  }
}
