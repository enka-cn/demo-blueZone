import { HomeTab } from '../view/tabs/HomeTab';
import { GenerateTab } from '../view/tabs/GenerateTab';
import { ProfileTab } from '../view/tabs/ProfileTab';
import { Palette, Size } from '../view/Theme';

/**
 * 应用主框架：底部 Tabs 承载三个一级页面（今天 / 生成 / 我的）。
 * 拍照、确认、候选、详情、补货等二级页面由各 Tab 内部 push 进入；
 * 返回本页时刷新当前 Tab 数据，避免看到过期状态。
 */
@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  /** 递增即触发子 Tab 重新读取数据 */
  @State refreshTick: number = 0;
  private controller: TabsController = new TabsController();

  onPageShow(): void {
    this.refreshTick++;
  }

  @Builder
  tabItem(icon: string, label: string, index: number) {
    Column({ space: 2 }) {
      Text(icon)
        .fontSize(20)
        .opacity(this.currentIndex === index ? 1 : 0.45)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? Palette.BRAND : Palette.TEXT_3)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height(Size.TAB_BAR)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        HomeTab({
          refreshTick: this.refreshTick,
          onSwitchTab: (index: number) => {
            this.controller.changeIndex(index);
          }
        })
      }
      .tabBar(this.tabItem('🥕', '今天', 0))

      TabContent() {
        GenerateTab({ refreshTick: this.refreshTick })
      }
      .tabBar(this.tabItem('🍳', '生成', 1))

      TabContent() {
        ProfileTab({ refreshTick: this.refreshTick })
      }
      .tabBar(this.tabItem('👤', '我的', 2))
    }
    .barHeight(Size.TAB_BAR)
    .barMode(BarMode.Fixed)
    .barBackgroundColor(Palette.BG_CARD)
    .onChange((index: number) => {
      this.currentIndex = index;
      this.refreshTick++;
    })
    .backgroundColor(Palette.BG_PAGE)
    .width('100%')
    .height('100%')
  }
}
