import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConfig, Logger } from '../../common/Common';

/** 键空间（§5.2）。 */
export class Keys {
  static readonly SCHEMA_VERSION: string = 'store.schema.version';
  static readonly SEED_VERSION: string = 'demo.seed.version';
  static readonly SNAPSHOT_CURRENT: string = 'snapshot.current';
  static readonly SNAPSHOT_HISTORY: string = 'snapshot.history';
  static readonly DIFF_LAST: string = 'diff.last';
  static readonly EXPIRY_INFERRED: string = 'expiry.inferred';
  static readonly RECIPE_CANDIDATES: string = 'recipe.candidates';
  static readonly SETTINGS_GENERATION: string = 'settings.generation';
  static readonly PREF_PROFILE: string = 'settings.preference';
  static readonly FEEDBACK_PROGRESS: string = 'feedback.progress';
  static readonly FEEDBACK_WEEKLY: string = 'feedback.weekly';
  static readonly FEEDBACK_SAVINGS: string = 'feedback.savings';
  static readonly SESSION_ANON: string = 'session.anon';
  static readonly FLAGS_RUNTIME: string = 'flags.runtime';
  static readonly CONFIG_API_KEY: string = 'config.apiKey';
  static readonly RUN_MODE: string = 'config.runMode';
  static readonly LLM_PROVIDER_ID: string = 'config.llm.providerId';
  static readonly LLM_ENDPOINT: string = 'config.llm.endpoint';
  static readonly LLM_VISION_MODEL: string = 'config.llm.visionModel';
  static readonly LLM_GENERATION_MODEL: string = 'config.llm.generationModel';
}

/**
 * 单一 KV 访问对象（IF-04）：Preferences + JSON 序列化 + 版本迁移（§6.5）。
 */
export class KvStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    if (KvStore.store !== null) {
      return;
    }
    try {
      KvStore.store = await preferences.getPreferences(context, 'fridge_store');
      await KvStore.migrate();
    } catch (e) {
      Logger.error(`KvStore init failed: ${JSON.stringify(e)}`);
    }
  }

  static isReady(): boolean {
    return KvStore.store !== null;
  }

  private static require(): preferences.Preferences {
    if (KvStore.store === null) {
      throw new Error('KvStore not initialized');
    }
    return KvStore.store;
  }

  static getString(key: string, def: string): string {
    try {
      const v: preferences.ValueType = KvStore.require().getSync(key, def);
      return typeof v === 'string' ? v : def;
    } catch (e) {
      Logger.warn(`KvStore.getString failed: ${key}`);
      return def;
    }
  }

  static getNumber(key: string, def: number): number {
    try {
      const v: preferences.ValueType = KvStore.require().getSync(key, def);
      return typeof v === 'number' ? v : def;
    } catch (e) {
      return def;
    }
  }

  static getBool(key: string, def: boolean): boolean {
    try {
      const v: preferences.ValueType = KvStore.require().getSync(key, def);
      return typeof v === 'boolean' ? v : def;
    } catch (e) {
      return def;
    }
  }

  /** 读取并反序列化对象；对象缺失或损坏时返回 null（不伪造数据，FR-03 / FR-24）。 */
  static getObject<T>(key: string): T | null {
    const raw: string = KvStore.getString(key, '');
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (e) {
      Logger.warn(`KvStore.getObject parse failed: ${key}`);
      return null;
    }
  }

  static async putString(key: string, value: string): Promise<void> {
    const s: preferences.Preferences = KvStore.require();
    s.putSync(key, value);
    await s.flush();
  }

  static async putNumber(key: string, value: number): Promise<void> {
    const s: preferences.Preferences = KvStore.require();
    s.putSync(key, value);
    await s.flush();
  }

  static async putBool(key: string, value: boolean): Promise<void> {
    const s: preferences.Preferences = KvStore.require();
    s.putSync(key, value);
    await s.flush();
  }

  static async putObject<T>(key: string, value: T): Promise<void> {
    await KvStore.putString(key, JSON.stringify(value));
  }

  static async remove(key: string): Promise<void> {
    const s: preferences.Preferences = KvStore.require();
    s.deleteSync(key);
    await s.flush();
  }

  /** 一键删除全部数据（NFR-04）。 */
  static async clearAll(): Promise<void> {
    const s: preferences.Preferences = KvStore.require();
    await s.clear();
    await s.flush();
  }

  /**
   * 版本迁移：读 store.schema.version → 低于当前版本时按迁移链逐级升级 → 回写。
   * 迁移失败时保守处理（清空并回退空态），不阻断主链路。
   */
  private static async migrate(): Promise<void> {
    const current: number = KvStore.getNumber(Keys.SCHEMA_VERSION, 0);
    if (current === AppConfig.SCHEMA_VERSION) {
      return;
    }
    try {
      if (current < 1) {
        await KvStore.putNumber(Keys.SCHEMA_VERSION, 1);
      }
      await KvStore.putNumber(Keys.SCHEMA_VERSION, AppConfig.SCHEMA_VERSION);
      Logger.info(`KvStore migrated ${current} -> ${AppConfig.SCHEMA_VERSION}`);
    } catch (e) {
      Logger.error(`KvStore migrate failed: ${JSON.stringify(e)}`);
      await KvStore.clearAll();
      await KvStore.putNumber(Keys.SCHEMA_VERSION, AppConfig.SCHEMA_VERSION);
    }
  }
}
