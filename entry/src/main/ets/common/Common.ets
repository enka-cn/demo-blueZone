import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'FridgeApp';

/**
 * 统一日志出口（NFR-05：便于回归对比与排障）。
 */
export class Logger {
  static info(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', msg);
  }
}

/**
 * 运行链路模式：真实链路与模拟演示链路严格隔离。
 * - REAL：真实拍照 / 真实模型调用，失败就展示失败结果，绝不用示例数据顶替。
 * - MOCK：全程使用内置示例数据，纯演示。
 */
export class RunMode {
  static readonly REAL: string = 'real';
  static readonly MOCK: string = 'mock';

  static label(mode: string): string {
    return mode === RunMode.REAL ? '真实识别' : '模拟演示';
  }

  static normalize(mode: string): string {
    return mode === RunMode.REAL ? RunMode.REAL : RunMode.MOCK;
  }
}

/**
 * Demo 基准下的集中配置（§8.3 配置与密钥管理）。
 * 链路模式由用户显式选择并持久化；模拟链路保证无网络 / 无密钥也能完整演示主链路。
 */
export class AppConfig {
  static readonly SCHEMA_VERSION: number = 1;
  static readonly SEED_VERSION: number = 1;
  static readonly DEFAULT_EXPIRY_HOURS: number = 24;
  static readonly MAX_CANDIDATES: number = 3;
  static readonly MAX_STEPS: number = 8;

  /**
   * 模型服务（接口地址 / 模型名 / 鉴权 / 超时）统一由 configs/llm.json 决定，
   * 见 `configs/LlmConfig`；此处不再保留任何硬编码的 endpoint 与模型名。
   */

  /** 实际用于请求的 API Key（用户填写优先，其次取配置内置）。 */
  static apiKey: string = '';
  /** 用户在「我的」页填写的 API Key（空串表示未填写）。 */
  static userApiKey: string = '';
  /** 链路模式（由「我的」页显式切换并持久化）。 */
  static mode: string = RunMode.MOCK;
  /** 过期阈值（小时，可配置，FR-24）。 */
  static expiryHours: number = AppConfig.DEFAULT_EXPIRY_HOURS;

  /** 模拟演示链路：全程使用内置示例数据。 */
  static get mockMode(): boolean {
    return AppConfig.mode === RunMode.MOCK;
  }

  /** 真实链路：真实拍照 + 真实模型调用。 */
  static get realMode(): boolean {
    return AppConfig.mode === RunMode.REAL;
  }

  /**
   * 真实链路是否具备调用条件（已选真实链路且已拿到 Key）。
   * apiKey 为「用户填写 或 配置内置」后的实际值；地址与模型由 configs 决定。
   */
  static get realReady(): boolean {
    return AppConfig.realMode && AppConfig.apiKey.trim().length > 0;
  }
}

/**
 * 横切开关（§4.10 降级与开关），集中管理，与业务数据分离（NFR-05 / NFR-06 / NFR-11）。
 */
export class FeatureFlags {
  /** 补货分支开关：关闭后补货判定与披露整体停用（NFR-11 / UC-29）。 */
  static replenishBranchEnabled: boolean = true;
  /** 省钱反馈开关：关闭后主链路完整可用（NFR-06 / UC-23）。 */
  static savingsFeedbackEnabled: boolean = true;
  /** 品质提示开关：算法不可用时降级为固定规则文案（FR-07 / NFR-08）。 */
  static qualityTipEnabled: boolean = true;
  /** 自动差集开关：名称稳定性不达标时降级为「用户确认消耗项」（NFR-12 / FR-20）。 */
  static autoDiffEnabled: boolean = true;
}

/** 余量档位（FR-04：≤5 档，不出现数字键盘）。 */
export const REMAINING_LEVELS: string[] = ['满', '半盒', '少量', '快没了'];

export function remainingIndex(level: string): number {
  const idx: number = REMAINING_LEVELS.indexOf(level);
  return idx < 0 ? 1 : idx;
}

/** 图像来源（DO-01.source）。 */
export class ImageSource {
  static readonly CAMERA: string = 'camera';
  static readonly ALBUM: string = 'album';
  static readonly PRESET: string = 'preset';
  /** 补货入库（库存就地更新，不产生历史快照）。 */
  static readonly PURCHASE: string = 'purchase';
}

export function sourceLabel(source: string): string {
  if (source === ImageSource.CAMERA) {
    return '拍照';
  }
  if (source === ImageSource.ALBUM) {
    return '相册';
  }
  if (source === ImageSource.PURCHASE) {
    return '补货';
  }
  return '示例照片';
}

/** 缺材宽容三策略（FR-10）。 */
export class MissingStrategy {
  static readonly OMIT: string = 'omit';
  static readonly SUBSTITUTE: string = 'substitute';
  static readonly REPLENISH: string = 'replenish';
}

export function missingStrategyLabel(strategy: string): string {
  if (strategy === MissingStrategy.OMIT) {
    return '不放也行';
  }
  if (strategy === MissingStrategy.SUBSTITUTE) {
    return '换个食材';
  }
  return '需要买';
}

/** 饭量档位（FR-13）。 */
export class Appetite {
  static readonly LIGHT: string = '少';
  static readonly NORMAL: string = '正常';
  static readonly HEAVY: string = '多';
}

export const APPETITE_LEVELS: string[] = [Appetite.LIGHT, Appetite.NORMAL, Appetite.HEAVY];

/** 时间与格式化工具（IF-08 系统时钟适配的纯函数部分）。 */
export class DateUtil {
  static nowIso(): string {
    return new Date().toISOString();
  }

  static toIso(date: Date): string {
    return date.toISOString();
  }

  static parse(iso: string): Date {
    const t: number = Date.parse(iso);
    return new Date(Number.isNaN(t) ? Date.now() : t);
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** 展示口径：MM-DD HH:mm（本地时区）。 */
  static format(iso: string): string {
    if (!iso) {
      return '—';
    }
    const d: Date = DateUtil.parse(iso);
    return `${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())} ` +
      `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}`;
  }

  /** 相对时长描述，用于「截至 X 时刻」文案。 */
  static relative(iso: string): string {
    const hours: number = DateUtil.hoursBetween(iso, DateUtil.nowIso());
    if (hours < 1) {
      const mins: number = Math.max(1, Math.round(hours * 60));
      return `${mins} 分钟前`;
    }
    if (hours < 24) {
      return `${Math.floor(hours)} 小时前`;
    }
    return `${Math.floor(hours / 24)} 天前`;
  }

  static hoursBetween(fromIso: string, toIso: string): number {
    const from: number = DateUtil.parse(fromIso).getTime();
    const to: number = DateUtil.parse(toIso).getTime();
    return (to - from) / 3600000;
  }

  static daysBetween(fromIso: string, toIso: string): number {
    return DateUtil.hoursBetween(fromIso, toIso) / 24;
  }

  /** 以周一为一周起点的周键（周度计数用）。 */
  static weekStartIso(date: Date): string {
    const d: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const day: number = d.getDay();
    const offset: number = day === 0 ? 6 : day - 1;
    d.setDate(d.getDate() - offset);
    return d.toISOString();
  }
}

/** 简单 ID 生成（本地匿名，无服务端）。 */
export class IdGen {
  private static seq: number = 0;

  static next(prefix: string): string {
    IdGen.seq += 1;
    return `${prefix}_${Date.now()}_${IdGen.seq}`;
  }
}
