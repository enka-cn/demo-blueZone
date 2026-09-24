import { common } from '@kit.AbilityKit';
import { AppConfig, DateUtil, FeatureFlags, IdGen, ImageSource, Logger, RunMode } from './Common';
import { LlmConfig, LlmOverrides } from '../configs/LlmConfig';
import { GenerationSettings, InventoryItem, PreferenceProfile, SessionAnon, Snapshot
} from '../data/model/Models';
import { Keys, KvStore } from '../data/kv/KvStore';
import { SeedData } from '../data/seed/SeedData';
import { SnapshotManager } from '../domain/inventory/SnapshotManager';
import { DiffEngine } from '../domain/diff/DiffEngine';
import { ExpiryInferrer } from '../domain/expiry/ExpiryInferrer';
import { FeedbackCalculator } from '../domain/feedback/FeedbackCalculator';

/** 运行期开关的持久化结构（与业务数据分离，NFR-05）。 */
interface RuntimeFlags {
  replenish: boolean;
  savings: boolean;
  quality: boolean;
  autoDiff: boolean;
}

/**
 * 应用门面：统一初始化持久化、开关、会话与演示数据准备。
 */
export class AppService {
  private static context: common.Context | null = null;
  private static initialized: boolean = false;
  private static readyPromise: Promise<void> | null = null;

  /** 幂等初始化；返回同一个 Promise，供页面等待数据层就绪。 */
  static init(context: common.Context): Promise<void> {
    if (AppService.readyPromise !== null) {
      return AppService.readyPromise;
    }
    AppService.context = context;
    AppService.readyPromise = AppService.doInit(context).then(() => {
      AppService.publishRunMode();
    });
    return AppService.readyPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    await KvStore.init(context);
    // 模型服务配置先于 Key 恢复：Key 的有效值依赖配置里的内置 Key。
    LlmConfig.init(context);
    AppService.restoreFlags();
    AppService.restoreLlmConfig();
    AppService.restoreRunMode();
    await AppService.ensureSession();
    AppService.initialized = true;
    Logger.info('AppService initialized');
  }

  /** 数据层就绪后回调（页面首帧避免读到未初始化状态）。 */
  static whenReady(): Promise<void> {
    if (AppService.readyPromise === null) {
      return Promise.resolve();
    }
    return AppService.readyPromise;
  }

  static isReady(): boolean {
    return AppService.initialized && KvStore.isReady();
  }

  static getContext(): common.Context {
    if (AppService.context === null) {
      throw new Error('AppService not initialized');
    }
    return AppService.context;
  }

  // ---------- 生成设置 DO-06 ----------

  static settings(): GenerationSettings {
    const s: GenerationSettings | null = KvStore.getObject<GenerationSettings>(Keys.SETTINGS_GENERATION);
    return s !== null ? s : SeedData.defaultSettings();
  }

  static async saveSettings(settings: GenerationSettings): Promise<void> {
    await KvStore.putObject<GenerationSettings>(Keys.SETTINGS_GENERATION, settings);
  }

  // ---------- 偏好 DO-07 ----------

  static preference(): PreferenceProfile {
    const p: PreferenceProfile | null = KvStore.getObject<PreferenceProfile>(Keys.PREF_PROFILE);
    return p !== null ? p : SeedData.defaultPreference();
  }

  static async savePreference(profile: PreferenceProfile): Promise<void> {
    await KvStore.putObject<PreferenceProfile>(Keys.PREF_PROFILE, profile);
  }

  // ---------- 开关 ----------

  static restoreFlags(): void {
    const flags: RuntimeFlags | null = KvStore.getObject<RuntimeFlags>(Keys.FLAGS_RUNTIME);
    if (flags === null) {
      return;
    }
    FeatureFlags.replenishBranchEnabled = flags.replenish;
    FeatureFlags.savingsFeedbackEnabled = flags.savings;
    FeatureFlags.qualityTipEnabled = flags.quality;
    FeatureFlags.autoDiffEnabled = flags.autoDiff;
  }

  static async saveFlags(): Promise<void> {
    const flags: RuntimeFlags = {
      replenish: FeatureFlags.replenishBranchEnabled,
      savings: FeatureFlags.savingsFeedbackEnabled,
      quality: FeatureFlags.qualityTipEnabled,
      autoDiff: FeatureFlags.autoDiffEnabled
    };
    await KvStore.putObject<RuntimeFlags>(Keys.FLAGS_RUNTIME, flags);
  }

  // ---------- 模型服务（configs/llm.json）+ API Key / 过期阈值 ----------

  /**
   * 恢复模型服务：配置文件已在启动时加载，这里只恢复运行时的覆盖项与 Key。
   * 覆盖项留空即「跟随配置文件」，便于内部部署直接改配置生效。
   */
  static restoreLlmConfig(): void {
    const savedProviderId: string = KvStore.getString(Keys.LLM_PROVIDER_ID, '');
    const overrides: LlmOverrides = {
      // 配置文件改动后，失效的服务商 id 直接丢弃，回到配置默认。
      providerId: LlmConfig.hasProvider(savedProviderId) ? savedProviderId : '',
      endpoint: KvStore.getString(Keys.LLM_ENDPOINT, ''),
      visionModel: KvStore.getString(Keys.LLM_VISION_MODEL, ''),
      generationModel: KvStore.getString(Keys.LLM_GENERATION_MODEL, '')
    };
    LlmConfig.setOverrides(overrides);
    AppConfig.userApiKey = KvStore.getString(Keys.CONFIG_API_KEY, '');
    AppConfig.apiKey = LlmConfig.effectiveApiKey(AppConfig.userApiKey);
    AppConfig.expiryHours = KvStore.getNumber('config.expiryHours', AppConfig.DEFAULT_EXPIRY_HOURS);
  }

  /** 保存用户填写的 Key；留空则回落到配置文件内置的 Key。 */
  static async saveApiKey(key: string): Promise<void> {
    AppConfig.userApiKey = key.trim();
    AppConfig.apiKey = LlmConfig.effectiveApiKey(AppConfig.userApiKey);
    await KvStore.putString(Keys.CONFIG_API_KEY, AppConfig.userApiKey);
  }

  /** 切换服务商（覆盖配置默认值）；传空串表示跟随配置文件。 */
  static async saveLlmProviderId(providerId: string): Promise<void> {
    const overrides: LlmOverrides = LlmConfig.getOverrides();
    LlmConfig.setOverrides({
      providerId: providerId,
      endpoint: overrides.endpoint,
      visionModel: overrides.visionModel,
      generationModel: overrides.generationModel
    });
    await KvStore.putString(Keys.LLM_PROVIDER_ID, providerId);
    AppConfig.apiKey = LlmConfig.effectiveApiKey(AppConfig.userApiKey);
    await AppService.clearGeneratedCandidates();
    Logger.info(`llm provider override: ${providerId.length > 0 ? providerId : '(follow config)'}`);
  }

  /** 清空全部覆盖项，完全回到 configs/llm.json 的配置。 */
  static async resetLlmOverrides(): Promise<void> {
    LlmConfig.setOverrides({ providerId: '', endpoint: '', visionModel: '', generationModel: '' });
    await KvStore.remove(Keys.LLM_PROVIDER_ID);
    await KvStore.remove(Keys.LLM_ENDPOINT);
    await KvStore.remove(Keys.LLM_VISION_MODEL);
    await KvStore.remove(Keys.LLM_GENERATION_MODEL);
    AppConfig.apiKey = LlmConfig.effectiveApiKey(AppConfig.userApiKey);
    await AppService.clearGeneratedCandidates();
    Logger.info('llm overrides cleared, follow config file');
  }

  /** 换服务商 / 换模型后旧候选菜谱不再可信，直接清掉。 */
  private static async clearGeneratedCandidates(): Promise<void> {
    await KvStore.remove(Keys.RECIPE_CANDIDATES);
  }

  // ---------- 链路模式（真实 / 模拟，显式选择） ----------

  /** 链路模式在 AppStorage 中的键：页面用 @StorageProp 订阅，切换后立即刷新。 */
  static readonly RUN_MODE_KEY: string = 'runModeIsMock';

  /** 把当前链路模式广播给订阅了 RUN_MODE_KEY 的页面。 */
  static publishRunMode(): void {
    AppStorage.setOrCreate<boolean>(AppService.RUN_MODE_KEY, AppConfig.mockMode);
  }

  /** 恢复链路模式；首次使用按是否已配置 Key 推断，之后完全以用户选择为准。 */
  static restoreRunMode(): void {
    const saved: string = KvStore.getString(Keys.RUN_MODE, '');
    if (saved.length === 0) {
      AppConfig.mode = AppConfig.apiKey.trim().length > 0 ? RunMode.REAL : RunMode.MOCK;
      return;
    }
    AppConfig.mode = RunMode.normalize(saved);
    AppService.publishRunMode();
  }

  static async saveRunMode(mode: string): Promise<void> {
    const next: string = RunMode.normalize(mode);
    const changed: boolean = next !== AppConfig.mode;
    AppConfig.mode = next;
    await KvStore.putString(Keys.RUN_MODE, AppConfig.mode);
    if (changed) {
      // 切换链路后清掉上一次的候选菜谱，避免把模拟链路的结果带进真实链路。
      await KvStore.remove(Keys.RECIPE_CANDIDATES);
    }
    AppService.publishRunMode();
    Logger.info(`run mode switched to ${AppConfig.mode}`);
  }

  static async saveExpiryHours(hours: number): Promise<void> {
    AppConfig.expiryHours = hours;
    await KvStore.putNumber('config.expiryHours', hours);
  }

  // ---------- 库存变化广播 ----------

  /** 库存版本号在 AppStorage 中的键：页面用 @StorageProp 订阅，库存一变立即刷新。 */
  static readonly INVENTORY_KEY: string = 'inventoryVersion';

  /** 拍照入库 / 补货入库后调用：让首页、生成页、候选页、详情页同步最新库存与缺项。 */
  static publishInventory(): void {
    const current: number = AppStorage.get<number>(AppService.INVENTORY_KEY) ?? 0;
    AppStorage.setOrCreate<number>(AppService.INVENTORY_KEY, current + 1);
  }

  // ---------- 会话 DO-10 ----------

  private static async ensureSession(): Promise<void> {
    const s: SessionAnon | null = KvStore.getObject<SessionAnon>(Keys.SESSION_ANON);
    if (s !== null) {
      return;
    }
    const session: SessionAnon = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      sessionId: IdGen.next('anon'),
      createdAt: DateUtil.nowIso()
    };
    await KvStore.putObject<SessionAnon>(Keys.SESSION_ANON, session);
  }

  static sessionId(): string {
    const s: SessionAnon | null = KvStore.getObject<SessionAnon>(Keys.SESSION_ANON);
    return s !== null ? s.sessionId : 'anonymous';
  }

  // ---------- 演示数据准备 / 重置 ----------

  /** 预置 §8.1 固定输入集：完整库存（含 1 项临期）+ 差集前历史快照。 */
  static async seedDemoData(): Promise<void> {
    const current: Snapshot = SeedData.seedSnapshot();
    // 构造 1 项临期（首次出现时间早于保鲜天数）用于演示临期标记与临期优先。
    const items: InventoryItem[] = current.items.map((i: InventoryItem): InventoryItem => {
      if (i.category === '菠菜') {
        const past: Date = new Date(Date.now() - 4 * 24 * 3600000);
        return {
          id: i.id,
          category: i.category,
          normalizedKey: i.normalizedKey,
          remaining: '少量',
          isExpiring: true,
          firstSeenAt: past.toISOString()
        };
      }
      return i;
    });
    current.items = items;
    const withExpiry: InventoryItem[] = await ExpiryInferrer.applyToItems(items);
    current.items = withExpiry;
    await SnapshotManager.replace(current);

    // 历史快照：含 2 项已消耗食材（马铃薯、生菜），用于演示自动差集。
    const historyItems: InventoryItem[] = withExpiry.slice();
    const pastIso: string = new Date(Date.now() - 26 * 3600000).toISOString();
    historyItems.push({
      id: 'seed_hist_1',
      category: '马铃薯',
      normalizedKey: '马铃薯',
      remaining: '满',
      isExpiring: false,
      firstSeenAt: pastIso
    });
    historyItems.push({
      id: 'seed_hist_2',
      category: '生菜',
      normalizedKey: '生菜',
      remaining: '半盒',
      isExpiring: false,
      firstSeenAt: pastIso
    });
    const history: Snapshot = {
      schemaVersion: AppConfig.SCHEMA_VERSION,
      capturedAt: pastIso,
      confirmedAt: pastIso,
      source: ImageSource.PRESET,
      items: historyItems
    };
    await SnapshotManager.replaceHistory(history);
    // 预置数据同样走一次自动差集与反馈计算，保证演示时进度条与周度计数可用。
    const diff = await DiffEngine.compute(current, history);
    await FeedbackCalculator.recordConsumption(DiffEngine.progressDone(diff), DiffEngine.progressTotal(current));
    Logger.info('seedDemoData done');
  }

  /** 一键删除全部数据（NFR-04）。 */
  static async clearAllData(): Promise<void> {
    await KvStore.clearAll();
    await AppService.saveFlags();
    await AppService.saveSettings(AppService.settings());
    // 数据清空后回到模拟演示链路，避免停留在无 Key 的真实链路上。
    AppConfig.userApiKey = '';
    await AppService.resetLlmOverrides();
    await AppService.saveRunMode(RunMode.MOCK);
    await FeedbackCalculator.reset();
    Logger.info('clearAllData done');
  }
}
