import { promptAction, router } from '@kit.ArkUI';
import { Palette } from '../Theme';
import { AppService } from '../../common/AppService';
import { APPETITE_LEVELS, Appetite, MissingStrategy, missingStrategyLabel } from '../../common/Common';
import { GenerationSettings, InventoryItem, PreferenceProfile, Snapshot
} from '../../data/model/Models';
import { SnapshotManager } from '../../domain/inventory/SnapshotManager';
import { GenerationOrchestrator } from '../../domain/generation/GenerationOrchestrator';
import { SeedData } from '../../data/seed/SeedData';
import { AppBar, PrimaryButton, SectionTitle, Tag } from '../../view/Widgets';

/**
 * 生成设置页（FR-12 / FR-13 / FR-14）。
 * 人数 / 饭量 + 便当单开关 + 缺材三策略 + 忌口；无必填文字表单（FR-22）。
 */
/**
 * 生成（Tab 2）：几个人吃 / 饭量 / 便当 / 缺的食材怎么办 / 不吃什么。
 * 由 pages/Index.ets 的 Tabs 承载。
 */
@Component
export struct GenerateTab {
  /** 切回本页时递增，用于重新读取库存与设置 */
  @Prop @Watch('onTick') refreshTick: number = 0;
  @State people: number = 2;
  @State appetite: string = Appetite.NORMAL;
  @State bentoMode: boolean = false;
  @State strategy: string = MissingStrategy.SUBSTITUTE;
  @State avoidList: string[] = [];
  @State avoidCandidates: string[] = SeedData.avoidCandidates();
  @State generating: boolean = false;
  @State itemCount: number = 0;
  @State expiring: string[] = [];
  @State errorText: string = '';
  /** 链路模式由 AppStorage 广播：与「我的」页的选择实时一致。 */
  @StorageProp('runModeIsMock') mockMode: boolean = true;
  /** 库存变化（拍照 / 补货入库）后立即刷新；键与 AppService.INVENTORY_KEY 一致。 */
  @StorageProp('inventoryVersion') @Watch('onInventoryChanged') inventoryVersion: number = 0;

  aboutToAppear(): void {
    AppService.whenReady().then(() => {
      this.load();
    });
  }

  private onInventoryChanged(): void {
    this.load();
  }

  onTick(): void {
    this.load();
  }

  private load(): void {
    const s: GenerationSettings = AppService.settings();
    this.people = s.people;
    this.appetite = s.appetite;
    this.bentoMode = s.bentoMode;
    this.strategy = s.missingStrategy;
    const pref: PreferenceProfile = AppService.preference();
    this.avoidList = pref.avoidList;
    const snap: Snapshot | null = SnapshotManager.current();
    const items: InventoryItem[] = snap !== null ? snap.items : [];
    this.itemCount = items.length;
    this.expiring = [];
    for (const i of items) {
      if (i.isExpiring) {
        this.expiring.push(i.category);
      }
    }
    AppService.publishRunMode();
  }

  private strategies(): string[] {
    return [MissingStrategy.OMIT, MissingStrategy.SUBSTITUTE, MissingStrategy.REPLENISH];
  }

  private isAvoided(name: string): boolean {
    return this.avoidList.indexOf(name) >= 0;
  }

  private toggleAvoid(name: string): void {
    const next: string[] = [];
    let removed: boolean = false;
    for (const a of this.avoidList) {
      if (a === name) {
        removed = true;
      } else {
        next.push(a);
      }
    }
    if (!removed) {
      next.push(name);
    }
    this.avoidList = next;
  }

  private async generate(): Promise<void> {
    if (this.itemCount === 0) {
      promptAction.showToast({ message: '先拍一张冰箱照片，才能生成菜谱' });
      return;
    }
    if (this.generating) {
      return;
    }
    this.generating = true;
    this.errorText = '';
    const settings: GenerationSettings = {
      schemaVersion: AppService.settings().schemaVersion,
      people: this.people,
      appetite: this.appetite,
      bentoMode: this.bentoMode,
      missingStrategy: this.strategy
    };
    const pref: PreferenceProfile = { schemaVersion: AppService.preference().schemaVersion, avoidList: this.avoidList };
    await AppService.saveSettings(settings);
    await AppService.savePreference(pref);
    const snap: Snapshot | null = SnapshotManager.current();
    const items: InventoryItem[] = snap !== null ? snap.items : [];
    try {
      await GenerationOrchestrator.generate(items, settings, pref);
    } catch (e) {
      // 真实链路失败：留在本页展示失败结果，不跳转、不用示例菜谱顶替。
      const err = e as Error;
      const reason: string = (err.message ?? '').trim();
      this.generating = false;
      this.errorText = reason.length > 0 ? reason : '生成失败，请稍后重试';
      promptAction.showToast({ message: '生成失败，请重试' });
      return;
    }
    this.generating = false;
    router.pushUrl({ url: 'pages/CandidatePage' }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  build() {
    Column() {
      AppBar({ title: '今天想吃什么' })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Column() {
                SectionTitle({ title: '冰箱里现有', subtitle: `共 ${this.itemCount} 样` })
              }
              .layoutWeight(1)

              Tag({
                text: this.mockMode ? '模拟演示' : '真实识别',
                bg: this.mockMode ? Palette.WARN_SOFT : Palette.BRAND_SOFT,
                fg: this.mockMode ? Palette.WARN : Palette.BRAND
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            if (this.expiring.length > 0) {
              Row({ space: 6 }) {
                Tag({ text: '临期优先', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
                Text(this.expiring.join('、'))
                  .fontSize(12)
                  .fontColor(Palette.TEXT_3)
                  .layoutWeight(1)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          Column({ space: 14 }) {
            SectionTitle({ title: '几个人吃' })
            Row({ space: 12 }) {
              Text('人数')
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .layoutWeight(1)
              Button('-')
                .width(36)
                .height(36)
                .fontSize(16)
                .backgroundColor(Palette.BG_SUBTLE)
                .fontColor(Palette.TEXT_1)
                .onClick(() => {
                  this.people = Math.max(1, this.people - 1);
                })
              Text(`${this.people}`)
                .fontSize(16)
                .fontColor(Palette.TEXT_1)
                .width(28)
                .textAlign(TextAlign.Center)
              Button('+')
                .width(36)
                .height(36)
                .fontSize(16)
                .backgroundColor(Palette.BG_SUBTLE)
                .fontColor(Palette.TEXT_1)
                .onClick(() => {
                  this.people = Math.min(8, this.people + 1);
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              Text('饭量')
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .layoutWeight(1)
              ForEach(APPETITE_LEVELS, (level: string) => {
                Text(level)
                  .fontSize(13)
                  .fontColor(this.appetite === level ? Color.White : Palette.TEXT_2)
                  .backgroundColor(this.appetite === level ? Palette.BRAND : Palette.BG_SUBTLE)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.appetite = level;
                  })
              }, (level: string) => level)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          Column({ space: 14 }) {
            SectionTitle({ title: '缺的食材怎么办', subtitle: '缺一两样也能做' })
            Row({ space: 8 }) {
              ForEach(this.strategies(), (s: string) => {
                Text(missingStrategyLabel(s))
                  .fontSize(13)
                  .fontColor(this.strategy === s ? Color.White : Palette.TEXT_2)
                  .backgroundColor(this.strategy === s ? Palette.BRAND : Palette.BG_SUBTLE)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.strategy = s;
                  })
              }, (s: string) => s)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          Column({ space: 12 }) {
            SectionTitle({ title: '要做便当吗', subtitle: '会挑适合放凉、能提前一晚做的菜' })
            Row() {
              Text(this.bentoMode ? '已开启便当适配' : '未开启')
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.bentoMode })
                .selectedColor(Palette.BRAND)
                .onChange((isOn: boolean) => {
                  this.bentoMode = isOn;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          Column({ space: 12 }) {
            SectionTitle({ title: '不吃什么', subtitle: '点一下就排除' })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.avoidCandidates, (name: string) => {
                Text(name)
                  .fontSize(13)
                  .fontColor(this.isAvoided(name) ? Color.White : Palette.TEXT_2)
                  .backgroundColor(this.isAvoided(name) ? Palette.DANGER : Palette.BG_SUBTLE)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.toggleAvoid(name);
                  })
              }, (name: string) => name)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          if (this.errorText.length > 0) {
            Row({ space: 8 }) {
              Tag({ text: '生成失败', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
              Text(this.errorText)
                .fontSize(12)
                .fontColor(Palette.DANGER)
                .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Palette.DANGER_SOFT)
            .borderRadius(12)
            .alignItems(VerticalAlign.Center)
          }

          PrimaryButton({
            label: this.generating ? '生成中…' : '生成菜谱',
            isEnabled: !this.generating,
            onTap: () => {
              this.generate();
            }
          })
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
