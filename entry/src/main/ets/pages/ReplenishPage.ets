import { promptAction, router } from '@kit.ArkUI';
import { Palette, Radius } from '../view/Theme';
import { AppService } from '../common/AppService';
import { Logger } from '../common/Common';
import { MissingItem, RecipeCandidate, ReplenishDecision, ReplenishParams } from '../data/model/Models';
import { ReplenishmentJudger } from '../domain/replenishment/ReplenishmentJudger';
import { PurchaseHandler } from '../domain/replenishment/PurchaseHandler';
import { GenerationOrchestrator } from '../domain/generation/GenerationOrchestrator';
import { AppBar, EmptyState, SectionTitle, Tag } from '../view/Widgets';

/** 折扣标签：原价与现价都在时才给。 */
function discountLabel(price: number, originalPrice: number): string {
  if (price <= 0 || originalPrice <= 0 || price >= originalPrice) {
    return '';
  }
  return `${(price / originalPrice * 10).toFixed(1)} 折`;
}

/** 价格文案：模型没给价格时不留空。 */
function priceText(price: number): string {
  if (price <= 0) {
    return '价格以门店为准';
  }
  return `¥${price.toFixed(2)}`;
}

/**
 * 补货页（FR-26 / FR-27 / NFR-11）。
 * 只展示当前这道菜自己缺的 1~4 样；规格 / 价格 / 折扣来自生成模型。
 * 点「加入库存」把东西买进冰箱 —— 库存变了，缺项与其它菜谱一起更新。
 */
@Entry
@Component
struct ReplenishPage {
  @State recipeId: string = '';
  @State triggered: boolean = false;
  @State items: MissingItem[] = [];
  @State sourceLabel: string = '';
  @State disclosureText: string = '';
  @State bought: number = 0;
  @State buying: string = '';

  aboutToAppear(): void {
    const params: ReplenishParams | undefined = router.getParams() as ReplenishParams | undefined;
    this.recipeId = params !== undefined && params.recipeId !== undefined ? params.recipeId : '';
    AppService.whenReady().then(() => {
      this.load();
    });
  }

  private load(): void {
    const recipe: RecipeCandidate | null = GenerationOrchestrator.findById(this.recipeId);
    const missing: MissingItem[] = recipe !== null ? recipe.missingItems : [];
    const decision: ReplenishDecision = ReplenishmentJudger.judge(missing);
    this.triggered = decision.triggered;
    this.items = decision.missingItems;
    this.sourceLabel = decision.sourceLabel;
    this.disclosureText = decision.disclosureText;
  }

  private async buy(item: MissingItem): Promise<void> {
    if (this.buying.length > 0) {
      return;
    }
    this.buying = item.category;
    try {
      await PurchaseHandler.buy(item);
      this.bought = this.bought + 1;
      AppService.publishInventory();
      promptAction.showToast({ message: `已把${item.category}放进冰箱` });
      this.load();
    } catch (err) {
      Logger.error(`buy failed: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '加入库存失败，请重试' });
    }
    this.buying = '';
  }

  build() {
    Column() {
      AppBar({
        title: '把缺的补上',
        showBack: true,
        onBack: () => {
          router.back();
        }
      })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          if (!this.triggered || this.items.length === 0) {
            EmptyState({
              title: this.bought > 0 ? '缺的都买齐了' : '暂时不用买什么',
              desc: this.bought > 0 ? '回到菜谱看看，现在可以开做了' : '冰箱里的食材够用，先清库存吧',
              actionText: '返回',
              onAction: () => {
                router.back();
              }
            })
          } else {
            Column({ space: 10 }) {
              SectionTitle({ title: '这道菜还差这些', subtitle: `共 ${this.items.length} 样` })
              ForEach(this.items, (m: MissingItem) => {
                this.missingRow(m)
              }, (m: MissingItem) => m.category)

              Row({ space: 6 }) {
                Tag({ text: this.sourceLabel, bg: Palette.BRAND_SOFT, fg: Palette.BRAND })
                Text(this.disclosureText)
                  .fontSize(12)
                  .fontColor(Palette.TEXT_3)
                  .layoutWeight(1)
              }
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BG_PAGE)
  }

  @Builder
  missingRow(m: MissingItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(m.category)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.TEXT_1)
          .layoutWeight(1)
        if (m.promo.length > 0) {
          Tag({ text: m.promo, bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
        }
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(priceText(m.price))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.DANGER)
        if (m.amount.length > 0) {
          Text(`/ ${m.amount}`)
            .fontSize(12)
            .fontColor(Palette.TEXT_3)
        }
        if (m.originalPrice > m.price && m.price > 0) {
          Text(`¥${m.originalPrice.toFixed(2)}`)
            .fontSize(12)
            .fontColor(Palette.TEXT_3)
            .decoration({ type: TextDecorationType.LineThrough })
          Tag({ text: discountLabel(m.price, m.originalPrice), bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
        }
        Blank()
      }
      .width('100%')

      Button(this.buying === m.category ? '加入中…' : '加入库存')
        .fontSize(13)
        .height(34)
        .width('100%')
        .fontColor(Palette.TEXT_ON_BRAND)
        .backgroundColor(Palette.BRAND)
        .enabled(this.buying.length === 0)
        .onClick(() => {
          this.buy(m);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Palette.BG_SUBTLE)
    .borderRadius(Radius.CARD)
  }
}
