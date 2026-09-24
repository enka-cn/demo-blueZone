import { promptAction, router } from '@kit.ArkUI';
import { Palette, Radius } from '../view/Theme';
import { AppService } from '../common/AppService';
import { MissingItem, RecipeCandidate, RecipeParams, RecipeStep, ReplenishParams } from '../data/model/Models';
import { GenerationOrchestrator } from '../domain/generation/GenerationOrchestrator';
import { ReplenishmentJudger } from '../domain/replenishment/ReplenishmentJudger';
import { FeedbackCalculator } from '../domain/feedback/FeedbackCalculator';
import { missingStrategyLabel } from '../common/Common';
import { AppBar, EmptyState, PrimaryButton, SectionTitle, Tag } from '../view/Widgets';

/**
 * 菜谱详情页（FR-15 / FR-16 / FR-17 / FR-07）。
 * 步骤 ≤8 + 营养估算值 + 品质建议性提示（不输出确定性变质结论）。
 */
@Entry
@Component
struct RecipeDetailPage {
  @State hasRecipe: boolean = false;
  @State title: string = '';
  @State summary: string = '';
  @State usedItems: string[] = [];
  @State missingItems: MissingItem[] = [];
  @State steps: RecipeStep[] = [];
  @State calories: number = 0;
  @State protein: number = 0;
  @State carbs: number = 0;
  @State fat: number = 0;
  @State bentoFriendly: boolean = false;
  @State expiringUsed: string[] = [];
  @State qualityTip: string = '';
  @State recording: boolean = false;
  @State recipeId: string = '';
  /** 库存变化（补货入库）后重读菜谱：买到的品类会从缺项里消失；键与 AppService.INVENTORY_KEY 一致。 */
  @StorageProp('inventoryVersion') @Watch('onInventoryChanged') inventoryVersion: number = 0;

  aboutToAppear(): void {
    AppService.whenReady().then(() => {
      this.load();
    });
  }

  private onInventoryChanged(): void {
    this.load();
  }

  private load(): void {
    const params = router.getParams() as RecipeParams;
    if (params === undefined || params === null) {
      return;
    }
    this.recipeId = params.recipeId;
    const recipe: RecipeCandidate | null = GenerationOrchestrator.findById(params.recipeId);
    if (recipe === null) {
      return;
    }
    this.hasRecipe = true;
    this.title = recipe.title;
    this.summary = recipe.summary;
    this.usedItems = recipe.usedItems;
    this.missingItems = recipe.missingItems;
    this.steps = recipe.steps;
    this.calories = recipe.nutrition.calories;
    this.protein = recipe.nutrition.protein;
    this.carbs = recipe.nutrition.carbs;
    this.fat = recipe.nutrition.fat;
    this.bentoFriendly = recipe.isBentoFriendly;
    this.expiringUsed = recipe.expiringUsed;
    this.qualityTip = recipe.qualityTip;
  }

  /** 完成这顿：累计省钱（可关闭，NFR-06）并返回首页。 */
  private async finish(): Promise<void> {
    if (this.recording) {
      return;
    }
    this.recording = true;
    await FeedbackCalculator.recordMeal();
    this.recording = false;
    promptAction.showToast({ message: '已记录这一顿' });
    router.back({ url: 'pages/Index' });
  }

  /** 只有补货分支开启、且这道菜缺 1~4 样时才给购买入口（默认路径不产生购买引导）。 */
  private canBuy(): boolean {
    return ReplenishmentJudger.isBranchEnabled() && this.missingItems.length > 0 &&
      this.missingItems.length <= ReplenishmentJudger.MAX_MISSING;
  }

  /** 缺项购买入口：只把这道菜自己的缺项带过去，不再拿库存去比常见搭配。 */
  private goReplenish(): void {
    const params: ReplenishParams = { recipeId: this.recipeId };
    router.pushUrl({ url: 'pages/ReplenishPage', params: params }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  @Builder
  nutritionCell(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.TEXT_1)
      Text(label)
        .fontSize(11)
        .fontColor(Palette.TEXT_3)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      AppBar({
        title: this.title,
        showBack: true,
        onBack: () => {
          router.back();
        }
      })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          if (!this.hasRecipe) {
            EmptyState({
              title: '菜谱不见了',
              desc: '回到上一页重新选一道',
              actionText: '返回上一页',
              onAction: () => {
                router.back();
              }
            })
          } else {
            Column({ space: 10 }) {
              Text(this.title)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Palette.TEXT_1)
                .width('100%')
              Text(this.summary)
                .fontSize(13)
                .fontColor(Palette.TEXT_2)
                .width('100%')
              Row({ space: 8 }) {
                if (this.bentoFriendly) {
                  Tag({ text: '便当友好', bg: Palette.BRAND_SOFT, fg: Palette.BRAND })
                }
                if (this.expiringUsed.length > 0) {
                  Tag({ text: '临期优先', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
                }
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            Column({ space: 10 }) {
              SectionTitle({ title: '用到你冰箱里的', subtitle: `${this.usedItems.length} 样` })
              Text(this.usedItems.join('、'))
                .fontSize(14)
                .fontColor(Palette.TEXT_1)
                .width('100%')
              if (this.missingItems.length > 0) {
                Divider().color(Palette.BG_SUBTLE)
                Text('这道菜还差这些（缺的可以买，也可以不放）')
                  .fontSize(13)
                  .fontColor(Palette.TEXT_3)
                  .width('100%')
                ForEach(this.missingItems, (m: MissingItem) => {
                  Row({ space: 8 }) {
                    Text(m.category)
                      .fontSize(14)
                      .fontColor(Palette.TEXT_1)
                      .layoutWeight(1)
                    if (m.price > 0) {
                      Text(m.amount.length > 0 ? `¥${m.price.toFixed(2)} / ${m.amount}` : `¥${m.price.toFixed(2)}`)
                        .fontSize(12)
                        .fontColor(Palette.DANGER)
                    }
                    Tag({ text: missingStrategyLabel(m.strategy), bg: Palette.WARN_SOFT, fg: Palette.WARN })
                  }
                  .width('100%')
                }, (m: MissingItem) => m.category)
                if (this.canBuy()) {
                  Button('缺的去补货')
                    .fontSize(13)
                    .height(34)
                    .fontColor(Palette.BRAND)
                    .backgroundColor(Palette.BRAND_SOFT)
                    .onClick(() => {
                      this.goReplenish();
                    })
                }
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            Column({ space: 10 }) {
              SectionTitle({ title: '大概的营养' })
              Row() {
                this.nutritionCell('热量 kcal', `${this.calories}`)
                this.nutritionCell('蛋白 g', `${this.protein}`)
                this.nutritionCell('碳水 g', `${this.carbs}`)
                this.nutritionCell('脂肪 g', `${this.fat}`)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            Column({ space: 10 }) {
              SectionTitle({ title: '做法', subtitle: `共 ${this.steps.length} 步` })
              ForEach(this.steps, (step: RecipeStep) => {
                Row({ space: 10 }) {
                  Text(`${step.index}`)
                    .fontSize(13)
                    .fontColor(Color.White)
                    .backgroundColor(Palette.BRAND)
                    .borderRadius(10)
                    .width(20)
                    .height(20)
                    .textAlign(TextAlign.Center)
                  Text(step.text)
                    .fontSize(14)
                    .fontColor(Palette.TEXT_1)
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
              }, (step: RecipeStep) => `${step.index}`)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            Column({ space: 8 }) {
              SectionTitle({ title: '食材状态提醒' })
              Text(this.qualityTip)
                .fontSize(13)
                .fontColor(Palette.TEXT_2)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFDF7')
            .borderRadius(Radius.CARD)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部固定主操作
      Column() {
        PrimaryButton({
          label: this.recording ? '记录中…' : '完成这顿',
          isEnabled: !this.recording,
          onTap: () => {
            this.finish();
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
