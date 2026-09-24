import { promptAction, router } from '@kit.ArkUI';
import { Palette, Radius } from '../view/Theme';
import { AppService } from '../common/AppService';
import { ImageSource, Logger, REMAINING_LEVELS, remainingIndex, sourceLabel } from '../common/Common';
import { CaptureParams, InventoryItem, RecognitionResult, Snapshot } from '../data/model/Models';
import { LlmClient } from '../adapter/llm/LlmClient';
import { SystemAdapter, UploadImage } from '../adapter/system/SystemAdapter';
import { RecognitionNormalizer } from '../domain/recognition/RecognitionNormalizer';
import { SnapshotManager } from '../domain/inventory/SnapshotManager';
import { GenerationOrchestrator } from '../domain/generation/GenerationOrchestrator';
import { ExpiryInferrer } from '../domain/expiry/ExpiryInferrer';
import { DiffEngine } from '../domain/diff/DiffEngine';
import { FeedbackCalculator } from '../domain/feedback/FeedbackCalculator';
import { AppBar, LoadingView, PrimaryButton, SecondaryButton, SectionTitle, Tag } from '../view/Widgets';

/**
 * 识别校对页（FR-02 / FR-04 / FR-05）。
 * 支持增、删、改、合并；余量以档位确认，全程不出现数字键盘。
 */
@Entry
@Component
struct ReviewPage {
  @State items: InventoryItem[] = [];
  @State notes: string = '';
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State newCategory: string = '';
  @State editingId: string = '';
  @State editingText: string = '';
  @State sourceText: string = '';
  @State errorMessage: string = '';
  /** 链路模式由 AppStorage 广播：与「我的」页的选择实时一致。 */
  @StorageProp('runModeIsMock') mockMode: boolean = true;
  private uri: string = '';
  private source: string = ImageSource.CAMERA;
  private presetKey: string = '';
  private capturedAt: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as CaptureParams;
    if (params !== undefined && params !== null) {
      this.uri = params.uri ?? '';
      this.source = params.source ?? ImageSource.CAMERA;
      this.presetKey = params.presetKey ?? '';
    }
    this.capturedAt = SystemAdapter.nowIso();
    this.sourceText = sourceLabel(this.source);
    AppService.whenReady().then(() => {
      this.load();
    });
  }

  /** IF-02 识别 → 规范化（FR-01）。失败 / 超时进入手动录入，主链路继续（NFR-02 / UC-20）。 */
  /**
   * IF-02 识别 → 规范化（FR-01）。
   * 模拟链路使用内置示例结果；真实链路失败时展示失败结果，允许重试，绝不用示例数据顶替。
   */
  private async load(): Promise<void> {
    this.loading = true;
    this.failed = false;
    this.errorMessage = '';
    AppService.publishRunMode();
    try {
      const upload: UploadImage = await SystemAdapter.prepareForUpload(this.uri);
      const result: RecognitionResult = await LlmClient.recognize(upload.base64, upload.mime, this.presetKey);
      if (result.failed === true) {
        this.items = [];
        this.notes = '';
        const failureText: string = result.errorMessage ?? '';
        this.errorMessage = failureText.length > 0 ? failureText : '识别失败，请重试';
        this.failed = true;
        return;
      }
      const existing: Snapshot | null = SnapshotManager.current();
      const existingItems: InventoryItem[] = existing !== null ? existing.items : [];
      this.items = RecognitionNormalizer.buildItems(result.items, existingItems);
      this.notes = result.notes.trim();
      this.failed = this.items.length === 0;
      if (this.failed) {
        this.errorMessage = '这张照片没认出来，可以重拍或手动添加食材';
      }
    } catch (e) {
      const err = e as Error;
      Logger.error(`load failed: ${err.message}`);
      this.items = [];
      this.notes = '';
      this.failed = true;
      this.errorMessage = '识别失败，请检查网络后重试';
    } finally {
      // 任何异常都要结束加载态，否则页面会停在加载中、底部主按钮也一直不可用。
      this.loading = false;
    }
  }

  /** 合并重复项：同归一品类键只保留一项（FR-02）。 */
  private mergeDuplicates(): void {
    let merged: InventoryItem[] = this.items.slice();
    let changed: boolean = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < merged.length && !changed; i++) {
        for (let j = i + 1; j < merged.length; j++) {
          if (merged[i].normalizedKey === merged[j].normalizedKey) {
            merged = RecognitionNormalizer.mergeItems(merged, merged[i].id, merged[j].id);
            changed = true;
            break;
          }
        }
      }
    }
    this.items = merged;
    promptAction.showToast({ message: '已合并重复项' });
  }

  private confirmRename(): void {
    this.items = RecognitionNormalizer.renameItem(this.items, this.editingId, this.editingText);
    this.editingId = '';
    this.editingText = '';
  }

  private addItem(): void {
    if (this.newCategory.trim().length === 0) {
      promptAction.showToast({ message: '先写个名字吧' });
      return;
    }
    this.items = RecognitionNormalizer.addItem(this.items, this.newCategory);
    this.newCategory = '';
  }

  /** 确认并写入快照：原当前快照转历史 → 自动差集 → 记录消耗进度。 */
  private async confirm(): Promise<void> {
    if (this.items.length === 0) {
      promptAction.showToast({ message: '至少保留一项食材' });
      return;
    }
    const withExpiry: InventoryItem[] = await ExpiryInferrer.applyToItems(this.items);
    const snap: Snapshot = await SnapshotManager.commit(withExpiry, this.capturedAt, this.source);
    const diff = await DiffEngine.compute(snap, SnapshotManager.history());
    await FeedbackCalculator.recordConsumption(DiffEngine.progressDone(diff), DiffEngine.progressTotal(snap));
    SystemAdapter.cleanup(this.uri);
    // 库存变了：已生成的候选菜谱缺项跟着重算（新拍的食材不再是缺项）。
    await GenerationOrchestrator.refreshMissing(snap.items);
    AppService.publishInventory();
    promptAction.showToast({ message: '已记下现在的库存' });
    router.back();
  }

  /**
   * FR-04：余量用滑动条确认（档位离散，不出现数字键盘）。
   * 仅在松手 / 点击时提交档位，避免拖动过程中重建组件打断手势。
   */
  @Builder
  remainingSlider(item: InventoryItem) {
    Column({ space: 4 }) {
      Row() {
        Text('还剩多少')
          .fontSize(12)
          .fontColor(Palette.TEXT_3)
        Blank()
        Text(item.remaining)
          .fontSize(12)
          .fontColor(Palette.BRAND)
      }
      .width('100%')

      Slider({
        value: remainingIndex(item.remaining),
        min: 0,
        max: REMAINING_LEVELS.length - 1,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(Palette.BRAND)
        .trackColor(Palette.BG_SUBTLE)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) {
            return;
          }
          const level: string = REMAINING_LEVELS[Math.round(value)] ?? item.remaining;
          if (level !== item.remaining) {
            this.items = RecognitionNormalizer.setRemaining(this.items, item.id, level);
          }
        })

      Row() {
        Text(REMAINING_LEVELS[0])
          .fontSize(10)
          .fontColor(Palette.TEXT_3)
        Blank()
        Text(REMAINING_LEVELS[REMAINING_LEVELS.length - 1])
          .fontSize(10)
          .fontColor(Palette.TEXT_3)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  itemCard(item: InventoryItem) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (this.editingId === item.id) {
          TextInput({ text: this.editingText })
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .onChange((v: string) => {
              this.editingText = v;
            })
          Button('确定')
            .fontSize(12)
            .height(30)
            .backgroundColor(Palette.BRAND)
            .onClick(() => {
              this.confirmRename();
            })
          Button('取消')
            .fontSize(12)
            .height(30)
            .backgroundColor(Palette.BG_SUBTLE)
            .fontColor(Palette.TEXT_1)
            .onClick(() => {
              this.editingId = '';
              this.editingText = '';
            })
        } else {
          Text(item.category)
            .fontSize(16)
            .fontColor(Palette.TEXT_1)
            .layoutWeight(1)
          if (item.isExpiring) {
            Tag({ text: '临期', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
          }
          Button('改名')
            .fontSize(12)
            .height(28)
            .backgroundColor(Palette.BG_SUBTLE)
            .fontColor(Palette.TEXT_1)
            .onClick(() => {
              this.editingId = item.id;
              this.editingText = item.category;
            })
          Button('删除')
            .fontSize(12)
            .height(28)
            .backgroundColor('#FDECEA')
            .fontColor(Palette.DANGER)
            .onClick(() => {
              this.items = RecognitionNormalizer.removeItem(this.items, item.id);
            })
        }
      }
      .width('100%')

      this.remainingSlider(item)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }

  build() {
    Column() {
      AppBar({
        title: '确认食材',
        showBack: true,
        onBack: () => {
          router.back();
        }
      })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Column() {
                SectionTitle({ title: '识别到这些食材', subtitle: '拖动滑块改余量，点名字可以改名' })
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

            Text(this.notes.length > 0 ? this.notes : '识别结果可能有遗漏，漏掉的可以手动添加')
              .fontSize(12)
              .fontColor(Palette.TEXT_3)
              .width('100%')
            if (this.loading) {
              LoadingView({ text: '正在认食材…' })
            } else if (this.failed) {
              Text(this.errorMessage.length > 0 ? this.errorMessage : '识别失败，请重试')
                .fontSize(13)
                .fontColor(Palette.WARN)
                .width('100%')
              SecondaryButton({
                label: '重新识别',
                onTap: () => {
                  this.load();
                }
              })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          ForEach(this.items, (item: InventoryItem) => {
            this.itemCard(item)
          }, (item: InventoryItem) => `${item.id}_${item.remaining}_${item.category}`)

          Column({ space: 10 }) {
            SectionTitle({ title: '手动添加' })
            Row({ space: 8 }) {
              TextInput({ text: this.newCategory, placeholder: '输入食材名，如「香菇」' })
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .onChange((v: string) => {
                  this.newCategory = v;
                })
              Button('新增')
                .fontSize(13)
                .height(40)
                .backgroundColor(Palette.BRAND)
                .onClick(() => {
                  this.addItem();
                })
            }
            .width('100%')

            Button('合并重复的食材')
              .width('100%')
              .height(40)
              .backgroundColor(Palette.BG_SUBTLE)
              .fontColor(Palette.TEXT_1)
              .onClick(() => {
                this.mergeDuplicates();
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Palette.BG_CARD)
          .borderRadius(Radius.CARD)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部固定主操作
      Column() {
        PrimaryButton({
          label: '确认入库',
          isEnabled: !this.loading,
          onTap: () => {
            this.confirm();
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
