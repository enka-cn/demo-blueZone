import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig, Logger, REMAINING_LEVELS, remainingIndex } from '../../common/Common';
import { LlmConfig, LlmProviderConfig } from '../../configs/LlmConfig';
import { GenerationSettings, MissingItem, RecipeCandidate, RecipeStep, RecognitionResult,
  RecognizedItem } from '../../data/model/Models';
import { SeedData } from '../../data/seed/SeedData';

interface ChatTextPart {
  type: string;
  text: string;
}

interface ChatImageUrl {
  url: string;
}

interface ChatImagePart {
  type: string;
  image_url: ChatImageUrl;
}

interface VisionMessage {
  role: string;
  content: Array<ChatTextPart | ChatImagePart>;
}

interface ResponseFormat {
  type: string;
}

interface VisionRequest {
  model: string;
  messages: VisionMessage[];
  temperature: number;
  stream: boolean;
  /** 部分自建网关不支持，按配置决定是否携带。 */
  response_format?: ResponseFormat;
}

interface TextMessage {
  role: string;
  content: string;
}

interface TextRequest {
  model: string;
  messages: TextMessage[];
  temperature: number;
  stream: boolean;
  response_format?: ResponseFormat;
}

interface ServerErrorMessage {
  message?: string;
}

interface ServerErrorEnvelope {
  error?: ServerErrorMessage;
}

/** 单次请求的结果：失败时带上「是否值得重试」与用户可读原因。 */
interface SendOutcome {
  ok: boolean;
  retryable: boolean;
  content: string;
  message: string;
}

interface ChatChoiceMessage {
  content: string;
}

interface ChatChoice {
  message: ChatChoiceMessage;
}

interface ChatResponse {
  choices: ChatChoice[];
}

/** 生成模型输出的原始菜谱结构（服务端 JSON）。 */
interface RawStep {
  text: string;
}

interface RawMissing {
  category: string;
  strategy: string;
  amount?: string;
  price?: number;
  originalPrice?: number;
  promo?: string;
}

interface RawRecipe {
  title: string;
  summary: string;
  usedItems: string[];
  missingItems: RawMissing[];
  steps: RawStep[];
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  isBentoFriendly: boolean;
  expiringUsed: string[];
  qualityTip: string;
}

interface RawRecipeEnvelope {
  recipes: RawRecipe[];
}

/**
 * 适配层：多模态识别（IF-02）+ 食谱生成（IF-03）。
 *
 * 供应商无关：接口地址、模型名、鉴权头、超时与请求体能力全部来自 `configs/llm.json`
 * （见 `configs/LlmConfig`），既可以是 DeepSeek 官方，也可以是内部网关或其他
 * OpenAI Chat Completions 兼容服务。真实链路失败即返回失败，绝不用示例数据顶替。
 */
export class LlmClient {
  /** 2300055（服务端在接收请求体途中断开连接）最多尝试次数。 */
  private static readonly MAX_SEND_ATTEMPTS: number = 2;

  private static readonly VISION_PROMPT: string =
    '你是冰箱食材识别助手，只输出结构化 JSON，不输出解释文字。\n' +
    '输入：一张冰箱内部照片，可能存在遮挡、堆叠、包装。\n' +
    '任务：输出食材品类清单；禁止输出任何重量 / 克数 / 份量数字。\n' +
    '归一：同一食材使用统一常用名，避免同物多名。\n' +
    `余量：按画面中该食材可见的存量，从「${REMAINING_LEVELS.join('」「')}」里挑最接近的一档写入 remaining；` +
    '判断不了就省略 remaining，不要编造。\n' +
    '输出：严格 JSON，形如 {"items":[{"category":"西红柿","confidence":0.9,' +
    `"remaining":"${REMAINING_LEVELS[2]}"}],"notes":""}；无法确认的项可省略。`;

  /**
   * IF-02 多模态识别。
   * 模拟链路 → 返回内置示例结果；真实链路 → 调用真实模型，失败即返回失败，绝不用示例数据顶替。
   */
  static async recognize(imageBase64: string, mime: string, presetKey: string): Promise<RecognitionResult> {
    if (AppConfig.mockMode) {
      Logger.info('recognize: mock mode, use sample result');
      return SeedData.recognitionFor(presetKey);
    }
    if (!AppConfig.realReady) {
      Logger.warn('recognize: real mode without api key');
      return LlmClient.failure('真实识别需要在「我的」页填写 API Key');
    }
    const provider: LlmProviderConfig = LlmConfig.effectiveProvider();
    if (provider.visionModel.length === 0) {
      Logger.error(`recognize: vision model missing for provider ${provider.id}`);
      return LlmClient.failure(`服务商「${provider.label}」未配置识别模型，请检查 configs/llm.json`);
    }
    if (imageBase64.length === 0) {
      Logger.warn('recognize: empty image payload');
      return LlmClient.failure('没有读取到照片内容，请重新拍摄');
    }
    try {
      const parts: Array<ChatTextPart | ChatImagePart> = [
        { type: 'text', text: LlmClient.VISION_PROMPT },
        { type: 'image_url', image_url: { url: `data:${mime};base64,${imageBase64}` } }
      ];
      const message: VisionMessage = { role: 'user', content: parts };
      const body: VisionRequest = {
        model: provider.visionModel,
        messages: [message],
        temperature: provider.visionTemperature,
        stream: false
      };
      if (provider.supportsJsonResponseFormat) {
        body.response_format = { type: 'json_object' };
      }
      const payload: string = JSON.stringify(body);
      Logger.info(`recognize: model=${provider.visionModel}, mime=${mime}, ` +
        `base64=${imageBase64.length}, body=${payload.length} bytes`);
      const content: string = await LlmClient.post(payload, provider.readTimeoutMs);
      const parsed: RecognitionResult = JSON.parse(content) as RecognitionResult;
      const items: RecognizedItem[] = LlmClient.sanitizeItems(parsed.items ?? []);
      if (items.length === 0) {
        return LlmClient.failure('这张照片没识别出食材，请换个角度重拍');
      }
      const notes: string = (parsed.notes ?? '').trim();
      return { items: items, notes: notes };
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(`recognize failed (real link, no fallback): ${err.code} ${err.message}`);
      const reason: string = (err.message ?? '').trim();
      return LlmClient.failure(reason.length > 0 ? reason : '识别失败，请检查网络后重试');
    }
  }

  /** 余量档位只认 REMAINING_LEVELS 里的值，模型给出别的写法一律视为「没判断出来」。 */
  private static sanitizeItems(items: RecognizedItem[]): RecognizedItem[] {
    const result: RecognizedItem[] = [];
    for (const item of items) {
      const level: string = item.remaining ?? '';
      result.push({
        category: item.category,
        confidence: item.confidence,
        remaining: remainingIndex(level) >= 0 ? level : ''
      });
    }
    return result;
  }

  /** 真实链路的失败结果：明确失败，不携带任何示例数据。 */
  private static failure(message: string): RecognitionResult {
    return { items: [], notes: '', failed: true, errorMessage: message };
  }

  /** 模型可能把价格写成字符串或省略，统一兜底成数字。 */
  private static numOrZero(value: number | undefined): number {
    if (value === undefined || typeof value !== 'number' || Number.isNaN(value)) {
      return 0;
    }
    return value;
  }

  private static textOrEmpty(value: string | undefined): string {
    if (value === undefined || typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  /**
   * IF-03 食谱生成（含缺材 / 便当 / 忌口 / 反常识 / 临期约束）。
   * 模拟链路 → 返回内置示例菜谱；真实链路 → 调用真实模型，失败时抛出错误由调用方展示失败结果。
   */
  static async generate(prompt: string, usedCategories: string[], settings: GenerationSettings,
    expiring: string[]): Promise<RecipeCandidate[]> {
    if (AppConfig.mockMode) {
      Logger.info('generate: mock mode, use sample recipes');
      return SeedData.mockRecipes(usedCategories, settings, expiring);
    }
    if (!AppConfig.realReady) {
      throw new Error('真实链路需要在「我的」页填写 API Key');
    }
    const provider: LlmProviderConfig = LlmConfig.effectiveProvider();
    if (provider.generationModel.length === 0) {
      throw new Error(`服务商「${provider.label}」未配置生成模型，请检查 configs/llm.json`);
    }
    const message: TextMessage = { role: 'user', content: prompt };
    const body: TextRequest = {
      model: provider.generationModel,
      messages: [message],
      temperature: provider.generationTemperature,
      stream: false
    };
    if (provider.supportsJsonResponseFormat) {
      body.response_format = { type: 'json_object' };
    }
    const startedAt: number = Date.now();
    Logger.info(`generate: model=${provider.generationModel}, readTimeout=${provider.generationReadTimeoutMs}ms`);
    const content: string = await LlmClient.post(JSON.stringify(body), provider.generationReadTimeoutMs);
    Logger.info(`generate done in ${Date.now() - startedAt}ms`);
    const envelope: RawRecipeEnvelope = JSON.parse(content) as RawRecipeEnvelope;
    const recipes: RecipeCandidate[] = LlmClient.toCandidates(envelope.recipes ?? []);
    if (recipes.length === 0) {
      throw new Error('这次没生成出菜谱，请稍后重试');
    }
    return recipes;
  }

  private static toCandidates(raw: RawRecipe[]): RecipeCandidate[] {
    const result: RecipeCandidate[] = [];
    for (let i = 0; i < raw.length && i < AppConfig.MAX_CANDIDATES; i++) {
      const r: RawRecipe = raw[i];
      const steps: RecipeStep[] = [];
      const rawSteps: RawStep[] = r.steps ?? [];
      for (let s = 0; s < rawSteps.length && s < AppConfig.MAX_STEPS; s++) {
        steps.push({ index: s + 1, text: rawSteps[s].text });
      }
      const missing: MissingItem[] = [];
      const rawMissing: RawMissing[] = r.missingItems ?? [];
      for (const m of rawMissing) {
        missing.push({
          category: m.category,
          strategy: m.strategy,
          amount: LlmClient.textOrEmpty(m.amount),
          price: LlmClient.numOrZero(m.price),
          originalPrice: LlmClient.numOrZero(m.originalPrice),
          promo: LlmClient.textOrEmpty(m.promo)
        });
      }
      result.push({
        id: `gen_${Date.now()}_${i}`,
        title: r.title,
        summary: r.summary,
        usedItems: r.usedItems ?? [],
        missingItems: missing,
        steps: steps,
        nutrition: {
          calories: r.calories,
          protein: r.protein,
          carbs: r.carbs,
          fat: r.fat
        },
        isBentoFriendly: r.isBentoFriendly === true,
        expiringUsed: r.expiringUsed ?? [],
        qualityTip: r.qualityTip ?? ''
      });
    }
    return result;
  }

  /** 统一 POST：地址、鉴权、超时、额外头均取自当前生效的服务商配置。 */
  private static async post(jsonBody: string, timeoutMs: number): Promise<string> {
    const provider: LlmProviderConfig = LlmConfig.effectiveProvider();
    if (provider.endpoint.length === 0) {
      throw new Error(`服务商「${provider.label}」未配置接口地址，请检查 configs/llm.json`);
    }
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    if (AppConfig.apiKey.length > 0) {
      header[provider.authHeader] = `${provider.authPrefix}${AppConfig.apiKey}`;
    }
    for (const extra of provider.extraHeaders) {
      header[extra.name] = extra.value;
    }
    Logger.info(`llm post: ${provider.endpoint}, body=${jsonBody.length} bytes, readTimeout=${timeoutMs}ms`);
    let attempt: number = 0;
    while (attempt < LlmClient.MAX_SEND_ATTEMPTS) {
      const outcome: SendOutcome = await LlmClient.send(provider, header, jsonBody, timeoutMs);
      if (outcome.ok) {
        return outcome.content;
      }
      attempt++;
      if (outcome.retryable && attempt < LlmClient.MAX_SEND_ATTEMPTS) {
        Logger.warn(`llm post retry ${attempt}: ${outcome.message}`);
        continue;
      }
      throw new Error(outcome.message);
    }
    throw new Error('请求失败，请检查网络后重试');
  }

  /** 单次发送：HTTP 层错误在文案里带上服务端返回的原因。 */
  private static async send(provider: LlmProviderConfig, header: Record<string, string>,
    jsonBody: string, timeoutMs: number): Promise<SendOutcome> {
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(
        provider.endpoint,
        {
          method: http.RequestMethod.POST,
          header: header,
          extraData: jsonBody,
          connectTimeout: provider.connectTimeoutMs,
          readTimeout: timeoutMs
        } as http.HttpRequestOptions
      );
      if (response.responseCode !== 200) {
        return { ok: false, retryable: false, content: '', message: LlmClient.describeHttpError(response) };
      }
      const envelope: ChatResponse | null = LlmClient.parseChat(response.result as string);
      if (envelope === null || envelope.choices.length === 0) {
        return { ok: false, retryable: false, content: '', message: '模型没有返回可用内容，请稍后重试' };
      }
      return { ok: true, retryable: false, content: envelope.choices[0].message.content, message: '' };
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(`llm send failed: ${err.code} ${err.message}`);
      // 2300055 = 向对端发送数据失败：服务端在接收请求体途中关闭连接，多为瞬时问题。
      return {
        ok: false,
        retryable: err.code === 2300055,
        content: '',
        message: LlmClient.describeFailure(err)
      };
    } finally {
      httpRequest.destroy();
    }
  }

  private static parseChat(raw: string): ChatResponse | null {
    try {
      return JSON.parse(raw) as ChatResponse;
    } catch (e) {
      Logger.warn('llm response is not valid json');
      return null;
    }
  }

  /** 网络层错误 → 用户可读原因（2300055 表示服务端在上传途中关闭了连接）。 */
  private static describeFailure(err: BusinessError): string {
    const code: number = err.code;
    if (code === 2300055) {
      return '照片上传中断：服务端提前关闭了连接。请确认当前模型支持图片识别，或换一张更小的照片后重试';
    }
    if (code === 2300028) {
      return '模型服务响应超时，请检查网络后重试';
    }
    if (code === 2300005 || code === 2300006) {
      return '无法解析模型服务地址，请检查网络与接口配置';
    }
    if (code === 2300003) {
      return '模型服务地址不正确，请检查 configs/llm.json';
    }
    if (code === 2300060) {
      return '安全连接建立失败，请检查网络环境后重试';
    }
    return '请求失败，请检查网络后重试';
  }

  /** 非 200 响应：优先把服务端返回的 error.message 透出，便于定位问题。 */
  private static describeHttpError(response: http.HttpResponse): string {
    const raw: string = typeof response.result === 'string' ? response.result : '';
    Logger.error(`llm http ${response.responseCode}: ${raw}`);
    const envelope: ServerErrorEnvelope | null = LlmClient.parseErrorEnvelope(raw);
    if (envelope !== null && envelope.error !== undefined) {
      const message: string = envelope.error.message ?? '';
      if (message.length > 0) {
        return `模型服务返回错误：${message}`;
      }
    }
    if (response.responseCode === 400) {
      return '模型服务不接受这次请求，请确认当前模型支持图片识别';
    }
    if (response.responseCode === 401 || response.responseCode === 403) {
      return '鉴权失败，请在「我的」页检查 API Key';
    }
    if (response.responseCode === 413) {
      return '照片太大被服务端拒绝，请换一张更小的照片';
    }
    if (response.responseCode === 429) {
      return '请求过于频繁或额度不足，请稍后再试';
    }
    return `模型服务暂时不可用（HTTP ${response.responseCode}），请稍后重试`;
  }

  private static parseErrorEnvelope(raw: string): ServerErrorEnvelope | null {
    try {
      return JSON.parse(raw) as ServerErrorEnvelope;
    } catch (e) {
      return null;
    }
  }
}
