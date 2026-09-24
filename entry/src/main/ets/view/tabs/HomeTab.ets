import { promptAction, router } from '@kit.ArkUI';
import { Palette, FontSize, Radius } from '../Theme';
import { AppService } from '../../common/AppService';
import { sourceLabel } from '../../common/Common';
import { DiffResult, InventoryItem, Snapshot } from '../../data/model/Models';
import { SnapshotManager } from '../../domain/inventory/SnapshotManager';
import { DiffEngine } from '../../domain/diff/DiffEngine';
import { FeedbackCalculator } from '../../domain/feedback/FeedbackCalculator';
import { AppBar, EmptyState, PrimaryButton, ProgressLine, SectionTitle, Tag } from '../../view/Widgets';

/**
 * 今天（Tab 1）：现在的库存 + 本周小结 + 消耗进度。
 * 由 pages/Index.ets 的 Tabs 承载；从二级页返回或切回本页时按 refreshTick 刷新。
 */
@Component
export struct HomeTab {
  /** 父级切换 Tab / 返回本页时递增，用于刷新数据 */
  @Prop @Watch('onTick') refreshTick: number = 0;
  /** 请求父级切换到指定 Tab（1=生成，2=我的） */
  onSwitchTab: (index: number) => void = () => {
  };
  @State items: InventoryItem[] = [];
  @State hasSnapshot: boolean = false;
  @State freshness: string = '';
  @State sourceText: string = '';
  @State expired: boolean = false;
  @State progressDone: number = 0;
  @State progressTotal: number = 0;
  @State weeklyText: string = '';
  @State diffText: string = '';
  @State addedItems: InventoryItem[] = [];
  /** 库存变化（拍照 / 补货入库）后立即刷新；键与 AppService.INVENTORY_KEY 一致。 */
  @StorageProp('inventoryVersion') @Watch('onInventoryChanged') inventoryVersion: number = 0;

  aboutToAppear(): void {
    // 等待数据层就绪后再读取，避免首帧读到未初始化状态
    AppService.whenReady().then(() => {
      this.refresh();
    });
  }

  private onInventoryChanged(): void {
    this.refresh();
  }

  onTick(): void {
    this.refresh();
  }

  private refresh(): void {
    const snap: Snapshot | null = SnapshotManager.current();
    if (snap === null) {
      this.hasSnapshot = false;
      this.items = [];
      this.freshness = '';
      this.sourceText = '';
      this.expired = false;
    } else {
      this.hasSnapshot = true;
      this.items = snap.items;
      this.freshness = SnapshotManager.freshnessLabel(snap);
      this.sourceText = sourceLabel(snap.source);
      this.expired = SnapshotManager.isExpired(snap);
    }
    const diff: DiffResult | null = DiffEngine.last();
    this.progressTotal = DiffEngine.progressTotal(snap);
    this.progressDone = DiffEngine.progressDone(diff);
    this.diffText = DiffEngine.describe(diff);
    this.addedItems = diff !== null ? diff.added : [];
    this.weeklyText = FeedbackCalculator.weeklyText();
  }

  private goCapture(): void {
    router.pushUrl({ url: 'pages/CapturePage' }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  private goGenerate(): void {
    if (this.items.length === 0) {
      promptAction.showToast({ message: '先拍一张冰箱照片，才能看到库存' });
      return;
    }
    this.onSwitchTab(1);
  }

  @Builder
  itemRow(item: InventoryItem) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(item.category)
          .fontSize(16)
          .fontColor(Palette.TEXT_1)
        Text(`余量：${item.remaining}`)
          .fontSize(12)
          .fontColor(Palette.TEXT_3)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.isExpiring) {
        Tag({ text: '临期优先', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
      }
      Tag({ text: item.remaining, bg: Palette.BRAND_SOFT, fg: Palette.BRAND })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  snapshotHeader() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('现在的库存')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.TEXT_1)
        if (this.expired) {
          Tag({ text: '可能不新鲜了', bg: Palette.WARN_SOFT, fg: Palette.WARN })
        }
      }
      .width('100%')

      Text(this.freshness)
        .fontSize(12)
        .fontColor(Palette.TEXT_3)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      // 顶部栏
      AppBar({ title: '冰箱清库存' })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 16 }) {
          if (!this.hasSnapshot) {
            // 空态：引导拍照，不使用历史快照冒充当前状态（FR-03）
            Column() {
              EmptyState({
                title: '还不知道冰箱里有什么',
                desc: '拍一张冰箱照片，看看现在有什么菜',
                actionText: '拍冰箱',
                onAction: () => {
                  this.goCapture();
                }
              })
              Button('试用示例数据')
                .fontSize(14)
                .height(38)
                .backgroundColor(Palette.BG_SUBTLE)
                .fontColor(Palette.TEXT_1)
                .margin({ bottom: 24 })
                .onClick(() => {
                  AppService.whenReady().then(() => {
                    return AppService.seedDemoData();
                  }).then(() => {
                    this.refresh();
                    promptAction.showToast({ message: '已载入示例数据' });
                  });
                })
            }
            .width('100%')
          } else {
            // 库存清单
            Column({ space: 10 }) {
              this.snapshotHeader()
              Divider().color(Palette.DIVIDER)
              ForEach(this.items, (item: InventoryItem) => {
                this.itemRow(item)
                Divider().color(Palette.DIVIDER_SOFT)
              }, (item: InventoryItem) => item.id)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            // 消耗反馈（FR-20）
            Column({ space: 10 }) {
              SectionTitle({ title: '这周用掉了多少', subtitle: this.diffText })
              ProgressLine({
                done: this.progressDone,
                total: this.progressTotal,
                label: '已用掉'
              })
              if (this.addedItems.length > 0) {
                Text(`新放进：${this.addedItems.map((i: InventoryItem): string => i.category).join('、')}`)
                  .fontSize(12)
                  .fontColor(Palette.TEXT_3)
                  .width('100%')
              }
              Text(this.weeklyText)
                .fontSize(FontSize.CAPTION)
                .fontColor(Palette.TEXT_2)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Palette.BG_CARD)
            .borderRadius(Radius.CARD)


          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部固定主操作：一次拍照完成「更新库存 + 算消耗」
      Column() {
        PrimaryButton({
          label: '拍照更新库存',
          onTap: () => {
            this.goCapture();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(Palette.BG_CARD)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BG_PAGE)
  }
}
