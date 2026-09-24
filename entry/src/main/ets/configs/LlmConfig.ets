import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Common';

/** 额外请求头（用数组表达，避免 ArkTS 动态索引）。 */
export interface LlmHeaderConfig {
  name: string;
  value: string;
}

/**
 * 单个模型服务商：对应 configs/llm.json 中 `providers` 的一项。
 * 只描述「怎么调用」，不描述业务；模型既可以是 DeepSeek 官方，也可以是内部网关或其他兼容服务。
 */
export interface LlmProviderConfig {
  id: string;
  label: string;
  description: string;
  /** 完整 Chat Completions 地址（含路径）。 */
  endpoint: string;
  /** 配置内置 Key（内部部署可用；留空则由用户在应用内填写）。 */
  apiKey: string;
  /** 鉴权头名称，如 Authorization。 */
  authHeader: string;
  /** 鉴权头前缀，如 `Bearer `。 */
  authPrefix: string;
  visionModel: string;
  generationModel: string;
  visionTemperature: number;
  generationTemperature: number;
  /** 服务端是否支持 `response_format: json_object`；不支持时自动省略该字段。 */
  supportsJsonResponseFormat: boolean;
  connectTimeoutMs: number;
  /** 识别等短请求的读超时（毫秒）。 */
  readTimeoutMs: number;
  /** 生成菜谱等长输出的读超时（毫秒）：非流式请求要等整份 JSON 生成完才会返回。 */
  generationReadTimeoutMs: number;
  extraHeaders: LlmHeaderConfig[];
}

/** 运行时覆盖项（持久化在 KV；空串表示跟随配置文件）。 */
export interface LlmOverrides {
  providerId: string;
  endpoint: string;
  visionModel: string;
  generationModel: string;
}

interface RawAuth {
  header?: string;
  prefix?: string;
}

interface RawProvider {
  id?: string;
  label?: string;
  description?: string;
  endpoint?: string;
  apiKey?: string;
  auth?: RawAuth;
  visionModel?: string;
  generationModel?: string;
  visionTemperature?: number;
  generationTemperature?: number;
  supportsJsonResponseFormat?: boolean;
  connectTimeoutMs?: number;
  readTimeoutMs?: number;
  generationReadTimeoutMs?: number;
  extraHeaders?: LlmHeaderConfig[];
}

interface RawLlmConfig {
  schemaVersion?: number;
  activeProviderId?: string;
  providers?: RawProvider[];
}

/**
 * 模型服务配置（§8.3）：接口地址与模型由 `resources/rawfile/configs/llm.json` 决定，
 * 换供应商 / 换内部网关只需改配置，不需要改代码。
 * 读取失败时回退到内置默认值，保证应用仍可启动。
 */
export class LlmConfig {
  static readonly RAW_FILE: string = 'configs/llm.json';
  static readonly DEFAULT_PROVIDER_ID: string = 'deepseek';

  private static providers: LlmProviderConfig[] = [];
  private static configuredActiveId: string = LlmConfig.DEFAULT_PROVIDER_ID;
  private static overrides: LlmOverrides = LlmConfig.emptyOverrides();
  private static loaded: boolean = false;

  private static emptyOverrides(): LlmOverrides {
    return { providerId: '', endpoint: '', visionModel: '', generationModel: '' };
  }

  /** 读取并归一化配置文件；幂等，应用启动时调用一次。 */
  static init(context: common.Context): void {
    if (LlmConfig.loaded) {
      return;
    }
    const parsed: RawLlmConfig | null = LlmConfig.readRawFile(context);
    if (parsed !== null) {
      const list: LlmProviderConfig[] = [];
      const rawList: RawProvider[] = parsed.providers ?? [];
      for (const item of rawList) {
        const provider: LlmProviderConfig | null = LlmConfig.normalizeProvider(item);
        if (provider !== null) {
          list.push(provider);
        }
      }
      if (list.length > 0) {
        LlmConfig.providers = list;
        const activeId: string = parsed.activeProviderId ?? list[0].id;
        LlmConfig.configuredActiveId = LlmConfig.pickId(list, activeId);
        LlmConfig.loaded = true;
        Logger.info(`llm config loaded: ${list.length} provider(s), active=${LlmConfig.configuredActiveId}`);
        return;
      }
    }
    LlmConfig.providers = LlmConfig.builtinDefaults();
    LlmConfig.configuredActiveId = LlmConfig.providers[0].id;
    LlmConfig.loaded = true;
    Logger.warn('llm config fallback to builtin defaults');
  }

  static isLoaded(): boolean {
    return LlmConfig.loaded;
  }

  /** 配置文件里声明的全部服务商（用于设置页展示可选列表）。 */
  static providerList(): LlmProviderConfig[] {
    return LlmConfig.providers;
  }

  /** 配置文件里的默认服务商 id。 */
  static configuredProviderId(): string {
    return LlmConfig.configuredActiveId;
  }

  /** 按 id 取展示名（用于设置页文案）。 */
  static labelOf(id: string): string {
    if (LlmConfig.providers.length === 0) {
      return id;
    }
    return LlmConfig.resolveProvider(id).label;
  }

  /** 配置里是否存在该服务商（配置变更后用于丢弃失效的覆盖项）。 */
  static hasProvider(id: string): boolean {
    for (const provider of LlmConfig.providers) {
      if (provider.id === id) {
        return true;
      }
    }
    return false;
  }

  static getOverrides(): LlmOverrides {
    return LlmConfig.overrides;
  }

  static setOverrides(overrides: LlmOverrides): void {
    LlmConfig.overrides = overrides;
  }

  /** 当前生效的服务商（配置默认 + 运行时覆盖）。 */
  static effectiveProvider(): LlmProviderConfig {
    const base: LlmProviderConfig = LlmConfig.resolveProvider(
      LlmConfig.overrides.providerId.length > 0 ? LlmConfig.overrides.providerId : LlmConfig.configuredActiveId);
    const endpoint: string = LlmConfig.overrides.endpoint.trim();
    const visionModel: string = LlmConfig.overrides.visionModel.trim();
    const generationModel: string = LlmConfig.overrides.generationModel.trim();
    if (endpoint.length === 0 && visionModel.length === 0 && generationModel.length === 0) {
      return base;
    }
    return {
      id: base.id,
      label: base.label,
      description: base.description,
      endpoint: endpoint.length > 0 ? endpoint : base.endpoint,
      apiKey: base.apiKey,
      authHeader: base.authHeader,
      authPrefix: base.authPrefix,
      visionModel: visionModel.length > 0 ? visionModel : base.visionModel,
      generationModel: generationModel.length > 0 ? generationModel : base.generationModel,
      visionTemperature: base.visionTemperature,
      generationTemperature: base.generationTemperature,
      supportsJsonResponseFormat: base.supportsJsonResponseFormat,
      connectTimeoutMs: base.connectTimeoutMs,
      readTimeoutMs: base.readTimeoutMs,
      generationReadTimeoutMs: base.generationReadTimeoutMs,
      extraHeaders: base.extraHeaders
    };
  }

  /** 实际使用的 Key：用户填写的优先，其次用配置文件内置的。 */
  static effectiveApiKey(userKey: string): string {
    const trimmed: string = userKey.trim();
    return trimmed.length > 0 ? trimmed : LlmConfig.effectiveProvider().apiKey.trim();
  }

  /** 调用条件是否齐备（有地址、有模型、有 Key）。 */
  static ready(apiKey: string): boolean {
    const provider: LlmProviderConfig = LlmConfig.effectiveProvider();
    return provider.endpoint.length > 0
      && provider.visionModel.length > 0
      && provider.generationModel.length > 0
      && apiKey.trim().length > 0;
  }

  private static resolveProvider(id: string): LlmProviderConfig {
    for (const provider of LlmConfig.providers) {
      if (provider.id === id) {
        return provider;
      }
    }
    return LlmConfig.providers[0];
  }

  private static pickId(list: LlmProviderConfig[], id: string): string {
    for (const provider of list) {
      if (provider.id === id) {
        return id;
      }
    }
    return list[0].id;
  }

  private static readRawFile(context: common.Context): RawLlmConfig | null {
    try {
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(LlmConfig.RAW_FILE);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      return JSON.parse(text) as RawLlmConfig;
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(`read ${LlmConfig.RAW_FILE} failed: ${err.code} ${err.message}`);
      return null;
    }
  }

  private static normalizeProvider(raw: RawProvider): LlmProviderConfig | null {
    const id: string = (raw.id ?? '').trim();
    const endpoint: string = (raw.endpoint ?? '').trim();
    if (id.length === 0 || endpoint.length === 0) {
      Logger.warn('skip llm provider without id/endpoint');
      return null;
    }
    const headers: LlmHeaderConfig[] = [];
    const rawHeaders: LlmHeaderConfig[] = raw.extraHeaders ?? [];
    for (const header of rawHeaders) {
      const name: string = (header.name ?? '').trim();
      if (name.length > 0) {
        headers.push({ name: name, value: header.value ?? '' });
      }
    }
    return {
      id: id,
      label: (raw.label ?? id).trim(),
      description: (raw.description ?? '').trim(),
      endpoint: endpoint,
      apiKey: (raw.apiKey ?? '').trim(),
      authHeader: (raw.auth?.header ?? 'Authorization').trim(),
      authPrefix: raw.auth?.prefix ?? 'Bearer ',
      visionModel: (raw.visionModel ?? '').trim(),
      generationModel: (raw.generationModel ?? '').trim(),
      visionTemperature: raw.visionTemperature ?? 0.2,
      generationTemperature: raw.generationTemperature ?? 0.7,
      supportsJsonResponseFormat: raw.supportsJsonResponseFormat ?? true,
      connectTimeoutMs: raw.connectTimeoutMs ?? 5000,
      readTimeoutMs: raw.readTimeoutMs ?? 60000,
      generationReadTimeoutMs: raw.generationReadTimeoutMs ?? 180000,
      extraHeaders: headers
    };
  }

  /** 内置兜底：与配置文件默认值保持一致，仅在配置缺失时使用。 */
  private static builtinDefaults(): LlmProviderConfig[] {
    return [
      {
        id: LlmConfig.DEFAULT_PROVIDER_ID,
        label: 'DeepSeek 开放平台',
        description: '官方多模态识别 + 食谱生成',
        endpoint: 'https://api.deepseek.com/chat/completions',
        apiKey: '',
        authHeader: 'Authorization',
        authPrefix: 'Bearer ',
        visionModel: 'deepseek-flash',
        generationModel: 'deepseek-chat',
        visionTemperature: 0.2,
        generationTemperature: 0.7,
        supportsJsonResponseFormat: true,
        connectTimeoutMs: 5000,
        readTimeoutMs: 60000,
        generationReadTimeoutMs: 180000,
        extraHeaders: []
      }
    ];
  }
}
