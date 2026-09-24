import { promptAction, router } from '@kit.ArkUI';
import { Palette, FontSize, Radius, Size } from '../Theme';
import { AppService } from '../../common/AppService';
import { AppConfig, FeatureFlags, RunMode } from '../../common/Common';
import { LlmConfig, LlmOverrides, LlmProviderConfig } from '../../configs/LlmConfig';
import { FeedbackCalculator } from '../../domain/feedback/FeedbackCalculator';
import { ReplenishmentJudger } from '../../domain/replenishment/ReplenishmentJudger';
import { AppBar, SecondaryButton, SectionTitle, SettingRow, Tag } from '../../view/Widgets';

/**
 * 我的（Tab 3）：功能设置 / 省钱统计 / 保鲜提醒 / 数据管理。
 * 由 pages/Index.ets 的 Tabs 承载。
 */
/** 服务商选项：把选中态并入数据，避免 ForEach 键值不变导致不刷新。 */
interface ProviderChip {
  id: string;
  label: string;
  selected: boolean;
}

@Component
export struct ProfileTab {
  /** 切回本页时递增，用于刷新开关与统计 */
  @Prop @Watch('onTick') refreshTick: number = 0;
  @State replenishOn: boolean = FeatureFlags.replenishBranchEnabled;
  @State savingsOn: boolean = FeatureFlags.savingsFeedbackEnabled;
  @State qualityOn: boolean = FeatureFlags.qualityTipEnabled;
  @State autoDiffOn: boolean = FeatureFlags.autoDiffEnabled;
  @State apiKeyInput: string = '';
  @State runMode: string = RunMode.MOCK;
  /** 模型服务：来自 configs/llm.json 的服务商列表与运行时覆盖项 */
  @State providers: LlmProviderConfig[] = [];
  @State providerChips: ProviderChip[] = [];
  @State providerId: string = '';
  @State configProviderLabel: string = '';
  @State effectiveEndpoint: string = '';
  @State effectiveVisionModel: string = '';
  @State effectiveGenerationModel: string = '';
  @State configHasApiKey: boolean = false;
  @State expiryHours: number = AppConfig.DEFAULT_EXPIRY_HOURS;
  @State savingsText: string = '';
  @State savingsFormula: string = '';
  @State sessionId: string = '';

  aboutToAppear(): void {
    AppService.whenReady().then(() => {
      this.load();
    });
  }

  onTick(): void {
    this.load();
  }

  private load(): void {
    this.replenishOn = FeatureFlags.replenishBranchEnabled;
    this.savingsOn = FeatureFlags.savingsFeedbackEnabled;
    this.qualityOn = FeatureFlags.qualityTipEnabled;
    this.autoDiffOn = FeatureFlags.autoDiffEnabled;
    this.apiKeyInput = AppConfig.userApiKey;
    this.runMode = AppConfig.mode;
    this.expiryHours = AppConfig.expiryHours;
    this.refreshLlm();
    this.refreshFeedback();
    this.sessionId = AppService.sessionId();
  }

  /** 读取 configs/llm.json 与运行时覆盖，刷新「模型服务」卡片。 */
  private refreshLlm(): void {
    this.providers = LlmConfig.providerList();
    this.providerId = LlmConfig.getOverrides().providerId;
    this.configProviderLabel = LlmConfig.labelOf(LlmConfig.configuredProviderId());
    const chips: ProviderChip[] = [];
    for (const p of this.providers) {
      chips.push({ id: p.id, label: p.label, selected: p.id === this.providerId });
    }
    this.providerChips = chips;
    const provider: LlmProviderConfig = LlmConfig.effectiveProvider();
    this.effectiveEndpoint = provider.endpoint;
    this.effectiveVisionModel = provider.visionModel;
    this.effectiveGenerationModel = provider.generationModel;
    this.configHasApiKey = provider.apiKey.trim().length > 0;
  }

  private overridesFollowConfig(): boolean {
    const o: LlmOverrides = LlmConfig.getOverrides();
    return o.providerId.length === 0 && o.endpoint.length === 0
      && o.visionModel.length === 0 && o.generationModel.length === 0;
  }

  private apiKeyHint(): string {
    if (AppConfig.userApiKey.trim().length > 0) {
      return '已使用你填写的 API Key';
    }
    return this.configHasApiKey ? '未填写，当前使用 configs/llm.json 内置的 Key' : '未填写，真实识别不可用';
  }

  private async selectProvider(id: string): Promise<void> {
    if (id === this.providerId) {
      return;
    }
    await AppService.saveLlmProviderId(id);
    this.providerId = LlmConfig.getOverrides().providerId;
    this.refreshLlm();
    promptAction.showToast({ message: id.length === 0 ? '已跟随配置默认服务商' : '已切换服务商' });
  }

  private async resetLlmOverrides(): Promise<void> {
    await AppService.resetLlmOverrides();
    this.providerId = '';
    this.refreshLlm();
    promptAction.showToast({ message: '已恢复为配置默认' });
  }

  @Builder
  configRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor(Palette.TEXT_3)
      Text(value.length > 0 ? value : '未配置')
        .fontSize(12)
        .fontColor(value.length > 0 ? Palette.TEXT_1 : Palette.WARN)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  private refreshFeedback(): void {
    this.savingsText = FeedbackCalculator.savingsText();
    this.savingsFormula = FeedbackCalculator.savingsFormula();
  }

  private async persistFlags(): Promise<void> {
    FeatureFlags.replenishBranchEnabled = this.replenishOn;
    FeatureFlags.savingsFeedbackEnabled = this.savingsOn;
    FeatureFlags.qualityTipEnabled = this.qualityOn;
    FeatureFlags.autoDiffEnabled = this.autoDiffOn;
    await AppService.saveFlags();
  }

  private async saveApiKey(): Promise<void> {
    await AppService.saveApiKey(this.apiKeyInput);
    this.apiKeyInput = AppConfig.userApiKey;
    this.refreshLlm();
    promptAction.showToast({ message: AppConfig.realReady ? '已保存，真实识别可用' : '已保存，切换到真实识别后生效' });
  }

  /** 切换链路：模拟演示 ↔ 真实识别；切到真实识别但缺 Key 时给出提示。 */
  private async switchMode(mode: string): Promise<void> {
    if (mode === this.runMode) {
      return;
    }
    await AppService.saveRunMode(mode);
    this.runMode = AppConfig.mode;
    if (mode === RunMode.REAL && !AppConfig.realReady) {
      promptAction.showToast({ message: '真实识别需要先填写 API Key' });
      return;
    }
    promptAction.showToast({ message: mode === RunMode.REAL ? '已切到真实识别' : '已切到模拟演示' });
  }

  @Builder
  modeOption(mode: string, title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(this.runMode === mode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.runMode === mode ? Palette.BRAND : Palette.TEXT_1)
      Text(desc)
        .fontSize(11)
        .fontColor(Palette.TEXT_3)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.runMode === mode ? Palette.BRAND_SOFT : Palette.BG_SUBTLE)
    .borderRadius(12)
    .borderWidth(1)
    .borderColor(this.runMode === mode ? Palette.BRAND : Palette.BG_SUBTLE)
    .onClick(() => {
      this.switchMode(mode);
    })
  }

  private async seed(): Promise<void> {
    await AppService.seedDemoData();
    promptAction.showToast({ message: '已载入示例数据' });
  }

  private async clearAll(): Promise<void> {
    await AppService.clearAllData();
    this.apiKeyInput = '';
    this.runMode = AppConfig.mode;
    ReplenishmentJudger.reset();
    this.refreshFeedback();
    promptAction.showToast({ message: '已删除全部本地数据' });
  }

  build() {
    Column() {
      AppBar({ title: '我的' })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          // 开关（与业务数据分离，NFR-05）
          Column() {
            SectionTitle({ title: '功能设置', subtitle: '关掉不影响其他功能' })
            SettingRow({
              label: '补货分支',
              desc: '关掉后不再推荐需要买的食材',
              showToggle: true,
              toggleOn: this.replenishOn,
              onToggle: (on: boolean) => {
                this.replenishOn = on;
                this.persistFlags();
              }
            })
            SettingRow({
              label: '省钱反馈',
              desc: '关掉后不显示省钱统计',
              showToggle: true,
              toggleOn: this.savingsOn,
              onToggle: (on: boolean) => {
                this.savingsOn = on;
                this.persistFlags();
                this.refreshFeedback();
              }
            })
            SettingRow({
              label: '品质提示',
              desc: '菜谱里会给出食材新鲜度提示',
              showToggle: true,
              toggleOn: this.qualityOn,
              onToggle: (on: boolean) => {
                this.qualityOn = on;
                this.persistFlags();
              }
            })
            SettingRow({
              label: '自动差集',
              desc: '自动比出用掉的食材，认不准时改由你确认',
              showToggle: true,
              toggleOn: this.autoDiffOn,
              onToggle: (on: boolean) => {
                this.autoDiffOn = on;
                this.persistFlags();
              }
            })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          // 省钱成就（FR-19 / UC-15：不出现在启动弹窗或首页首屏核心位置）
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Column() {
                SectionTitle({ title: '省钱成就' })
              }
              .layoutWeight(1)

              Tag({ text: '只在本机显示', bg: Palette.BG_SUBTLE, fg: Palette.TEXT_2 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            Text(this.savingsText)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.TEXT_1)
              .width('100%')
            Text(this.savingsFormula)
              .fontSize(12)
              .fontColor(Palette.TEXT_3)
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          // 识别与过期阈值
          Column({ space: 10 }) {
            SectionTitle({ title: '保鲜提醒' })
            Row({ space: 10 }) {
              Text('提醒我食材快过期')
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .layoutWeight(1)
              Button('-')
                .width(34)
                .height(34)
                .fontSize(15)
                .backgroundColor(Palette.BG_SUBTLE)
                .fontColor(Palette.TEXT_1)
                .onClick(() => {
                  this.expiryHours = Math.max(1, this.expiryHours - 1);
                  AppService.saveExpiryHours(this.expiryHours);
                })
              Text(`${this.expiryHours} 小时`)
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .width(72)
                .textAlign(TextAlign.Center)
              Button('+')
                .width(34)
                .height(34)
                .fontSize(15)
                .backgroundColor(Palette.BG_SUBTLE)
                .fontColor(Palette.TEXT_1)
                .onClick(() => {
                  this.expiryHours = Math.min(168, this.expiryHours + 1);
                  AppService.saveExpiryHours(this.expiryHours);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          // 运行链路：真实识别与模拟演示严格隔离，切换后立即生效并持久化
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Column() {
                SectionTitle({ title: '运行链路', subtitle: '真实链路失败会直接提示，不会用示例数据顶替' })
              }
              .layoutWeight(1)

              Tag({
                text: RunMode.label(this.runMode),
                bg: this.runMode === RunMode.REAL ? Palette.BRAND_SOFT : Palette.WARN_SOFT,
                fg: this.runMode === RunMode.REAL ? Palette.BRAND : Palette.WARN
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            Row({ space: 10 }) {
              this.modeOption(RunMode.MOCK, '模拟演示', '全程用内置示例数据')
              this.modeOption(RunMode.REAL, '真实识别', '拍照走真实模型识别')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          // 模型服务：接口地址 / 模型名来自 configs/llm.json，应用内只做选择与覆盖
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Column() {
                SectionTitle({ title: '模型服务', subtitle: '地址与模型在 configs/llm.json 中配置' })
              }
              .layoutWeight(1)

              Tag({
                text: this.overridesFollowConfig() ? '跟随配置' : '应用内覆盖',
                bg: this.overridesFollowConfig() ? Palette.BG_SUBTLE : Palette.WARN_SOFT,
                fg: this.overridesFollowConfig() ? Palette.TEXT_2 : Palette.WARN
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            if (this.providers.length > 1) {
              Text('服务商')
                .fontSize(12)
                .fontColor(Palette.TEXT_3)
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                Text(`跟随配置（${this.configProviderLabel}）`)
                  .fontSize(12)
                  .fontColor(this.providerId.length === 0 ? Color.White : Palette.TEXT_2)
                  .backgroundColor(this.providerId.length === 0 ? Palette.BRAND : Palette.BG_SUBTLE)
                  .borderRadius(12)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.selectProvider('');
                  })
                ForEach(this.providerChips, (chip: ProviderChip) => {
                  Text(chip.label)
                    .fontSize(12)
                    .fontColor(chip.selected ? Color.White : Palette.TEXT_2)
                    .backgroundColor(chip.selected ? Palette.BRAND : Palette.BG_SUBTLE)
                    .borderRadius(12)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.selectProvider(chip.id);
                    })
                }, (chip: ProviderChip) => `${chip.id}_${chip.selected}`)
              }
              .width('100%')
            }

            this.configRow('接口地址', this.effectiveEndpoint)
            this.configRow('识别模型', this.effectiveVisionModel)
            this.configRow('生成模型', this.effectiveGenerationModel)

            Text(this.apiKeyHint())
              .fontSize(12)
              .fontColor(Palette.TEXT_3)
              .width('100%')
            TextInput({ text: this.apiKeyInput, placeholder: '粘贴 API Key（留空则用配置内置）' })
              .width('100%')
              .height(42)
              .fontSize(14)
              .type(InputType.Password)
              .onChange((v: string) => {
                this.apiKeyInput = v;
              })
            Button('保存 API Key')
              .width('100%')
              .height(40)
              .backgroundColor(Palette.BG_SUBTLE)
              .fontColor(Palette.TEXT_1)
              .onClick(() => {
                this.saveApiKey();
              })
            if (!this.overridesFollowConfig()) {
              SecondaryButton({
                label: '恢复配置默认',
                onTap: () => {
                  this.resetLlmOverrides();
                }
              })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          // 数据管理
          Column({ space: 10 }) {
            SectionTitle({ title: '数据管理' })
            Text('示例数据只用于模拟演示链路，会覆盖当前库存。')
              .fontSize(12)
              .fontColor(Palette.TEXT_3)
              .width('100%')
            SecondaryButton({
              label: '载入示例数据',
              onTap: () => {
                this.seed();
              }
            })
            Button('一键删除全部数据')
              .width('100%')
              .height(Size.BUTTON)
              .backgroundColor(Palette.DANGER_SOFT)
              .fontColor(Palette.DANGER)
              .onClick(() => {
                this.clearAll();
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Palette.BG_CARD)
          .borderRadius(Radius.CARD)

          // 隐私
          Column({ space: 6 }) {
            SectionTitle({ title: '隐私' })
            Text('库存、菜谱记录只保存在这台设备上，不会上传；照片仅用于本机识别。')
              .fontSize(FontSize.CAPTION)
              .fontColor(Palette.TEXT_3)
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Palette.BG_CARD)
          .borderRadius(Radius.CARD)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BG_PAGE)
  }
}
