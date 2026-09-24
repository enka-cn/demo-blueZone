import { promptAction, router } from '@kit.ArkUI';
import { Palette, Radius } from '../view/Theme';
import { AppService } from '../common/AppService';
import { RecipeCandidate, RecipeParams } from '../data/model/Models';
import { GenerationOrchestrator } from '../domain/generation/GenerationOrchestrator';
import { AppBar, EmptyState, SectionTitle, Tag } from '../view/Widgets';

/**
 * 候选卡片流（FR-11：候选 ≤3 张）。
 */
@Entry
@Component
struct CandidatePage {
  @State candidates: RecipeCandidate[] = [];
  /** 库存变化（补货入库）后重读候选：别的菜谱也可能不再缺项；键与 AppService.INVENTORY_KEY 一致。 */
  @StorageProp('inventoryVersion') @Watch('onInventoryChanged') inventoryVersion: number = 0;

  onPageShow(): void {
    AppService.whenReady().then(() => {
      this.refresh();
    });
  }

  private onInventoryChanged(): void {
    this.refresh();
  }

  private refresh(): void {
    this.candidates = GenerationOrchestrator.candidates();
  }

  private openDetail(id: string): void {
    const params: RecipeParams = { recipeId: id };
    router.pushUrl({ url: 'pages/RecipeDetailPage', params: params }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  @Builder
  candidateCard(recipe: RecipeCandidate) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(recipe.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.TEXT_1)
          .layoutWeight(1)
        if (recipe.isBentoFriendly) {
          Tag({ text: '便当友好', bg: Palette.BRAND_SOFT, fg: Palette.BRAND })
        }
      }
      .width('100%')

      Text(recipe.summary)
        .fontSize(13)
        .fontColor(Palette.TEXT_2)
        .width('100%')

      Row({ space: 8 }) {
        if (recipe.expiringUsed.length > 0) {
          Tag({ text: '临期优先', bg: Palette.DANGER_SOFT, fg: Palette.DANGER })
        }
        if (recipe.missingItems.length > 0) {
          Tag({ text: `还差 ${recipe.missingItems.length} 样`, bg: Palette.WARN_SOFT, fg: Palette.WARN })
        }
        Text(`用料 ${recipe.usedItems.length} 项 · ${recipe.steps.length} 步`)
          .fontSize(12)
          .fontColor(Palette.TEXT_3)
          .layoutWeight(1)
      }
      .width('100%')

      Button('看做法')
        .width('100%')
        .height(38)
        .backgroundColor(Palette.BG_SUBTLE)
        .fontColor(Palette.TEXT_1)
        .onClick(() => {
          this.openDetail(recipe.id);
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  build() {
    Column() {
      AppBar({
        title: '今天能做的菜',
        showBack: true,
        onBack: () => {
          router.back();
        }
      })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 14 }) {
          if (this.candidates.length === 0) {
            EmptyState({
              title: '还没有菜谱',
              desc: '先拍一张冰箱照片，再来生成菜谱',
              actionText: '去拍照',
              onAction: () => {
                router.pushUrl({ url: 'pages/CapturePage' }).catch(() => {
                  promptAction.showToast({ message: '打开失败，请重试' });
                });
              }
            })
          } else {
            SectionTitle({ title: `为你挑了 ${this.candidates.length} 道菜`, subtitle: '先用快过期的食材' })
            ForEach(this.candidates, (recipe: RecipeCandidate) => {
              this.candidateCard(recipe)
            }, (recipe: RecipeCandidate) => recipe.id)
          }

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
