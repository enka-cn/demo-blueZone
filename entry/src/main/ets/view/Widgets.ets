import { FontSize, Palette, Radius, Size, Space } from './Theme';

/**
 * 可复用界面组件（仅使用系统组件，A-12 / NFR-09）。
 * 所有色值 / 字号 / 间距取自 Theme 令牌，页面不再硬编码。
 */

@Component
export struct Tag {
  @Prop text: string = '';
  @Prop bg: string = Palette.WARN_SOFT;
  @Prop fg: string = Palette.WARN;

  build() {
    Text(this.text)
      .fontSize(FontSize.CHIP)
      .fontColor(this.fg)
      .backgroundColor(this.bg)
      .borderRadius(Radius.CHIP)
      .padding({ left: Space.SM, right: Space.SM, top: 3, bottom: 3 })
  }
}

/** 顶部栏：标题 + 可选副标题 + 可选返回 / 右侧动作。 */
@Component
export struct AppBar {
  title: string = '';
  subtitle: string = '';
  showBack: boolean = false;
  rightText: string = '';
  onBack: () => void = () => {
  };
  onRight: () => void = () => {
  };

  build() {
    Row({ space: Space.SM }) {
      if (this.showBack) {
        Text('‹')
          .fontSize(28)
          .fontColor(Palette.TEXT_1)
          .width(Size.BUTTON_SMALL)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBack();
          })
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.TEXT_1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(FontSize.CAPTION)
            .fontColor(Palette.TEXT_3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.rightText.length > 0) {
        Text(this.rightText)
          .fontSize(FontSize.BODY)
          .fontColor(Palette.BRAND)
          .padding({ left: Space.SM, right: Space.SM, top: Space.SM, bottom: Space.SM })
          .onClick(() => {
            this.onRight();
          })
      }
    }
    .width('100%')
    .height(Size.APP_BAR)
    .alignItems(VerticalAlign.Center)
  }
}

/** 内容卡片容器。 */
@Component
export struct Card {
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(Space.LG)
    .backgroundColor(Palette.BG_CARD)
    .borderRadius(Radius.CARD)
  }
}

/** 主操作按钮。 */
@Component
export struct PrimaryButton {
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  onTap: () => void = () => {
  };

  build() {
    Button(this.label)
      .width('100%')
      .height(Size.BUTTON)
      .fontSize(FontSize.BUTTON)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(Palette.BRAND)
      .fontColor(Palette.TEXT_ON_BRAND)
      .opacity(this.isEnabled ? 1 : 0.4)
      .enabled(this.isEnabled)
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 次级操作按钮。 */
@Component
export struct SecondaryButton {
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  onTap: () => void = () => {
  };

  build() {
    Button(this.label)
      .width('100%')
      .height(Size.BUTTON)
      .fontSize(FontSize.BUTTON)
      .backgroundColor(Palette.BG_SUBTLE)
      .fontColor(Palette.TEXT_1)
      .enabled(this.isEnabled)
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 加载态：用于识别、生成等异步等待。 */
@Component
export struct LoadingView {
  text: string = '加载中…';

  build() {
    Column({ space: Space.MD }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Palette.BRAND)
      Text(this.text)
        .fontSize(FontSize.BODY)
        .fontColor(Palette.TEXT_2)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .alignItems(HorizontalAlign.Center)
  }
}

/** 错误态：给出可执行的下一步。 */
@Component
export struct ErrorView {
  text: string = '出了点问题';
  actionText: string = '重试';
  onRetry: () => void = () => {
  };

  build() {
    Column({ space: Space.MD }) {
      Text('😕')
        .fontSize(40)
      Text(this.text)
        .fontSize(FontSize.BODY)
        .fontColor(Palette.TEXT_2)
        .textAlign(TextAlign.Center)
      Button(this.actionText)
        .height(Size.BUTTON_SMALL)
        .fontSize(FontSize.BODY)
        .backgroundColor(Palette.BG_SUBTLE)
        .fontColor(Palette.TEXT_1)
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }
}

/** 空态：插画位 + 一句说明 + 一个主操作。 */
@Component
export struct EmptyState {
  icon: string = '🧊';
  title: string = '';
  desc: string = '';
  actionText: string = '';
  onAction: () => void = () => {
  };

  build() {
    Column({ space: Space.MD }) {
      Text(this.icon)
        .fontSize(48)
      Text(this.title)
        .fontSize(FontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.TEXT_1)
      if (this.desc.length > 0) {
        Text(this.desc)
          .fontSize(FontSize.BODY)
          .fontColor(Palette.TEXT_3)
          .textAlign(TextAlign.Center)
          .padding({ left: Space.XL, right: Space.XL })
      }
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .fontSize(FontSize.BUTTON)
          .height(40)
          .backgroundColor(Palette.BRAND)
          .fontColor(Palette.TEXT_ON_BRAND)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
    .alignItems(HorizontalAlign.Center)
  }
}

/** 进度条：一行说明 + 进度 + 计数。 */
@Component
export struct ProgressLine {
  done: number = 0;
  total: number = 0;
  label: string = '';

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.label)
          .fontSize(FontSize.CAPTION)
          .fontColor(Palette.TEXT_2)
          .layoutWeight(1)
        Text(`${this.done} / ${this.total}`)
          .fontSize(FontSize.CAPTION)
          .fontColor(Palette.BRAND)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      Row() {
        Row()
          .width(this.total > 0 ? `${Math.min(100, (this.done / this.total) * 100)}%` : '0%')
          .height(6)
          .backgroundColor(Palette.BRAND)
          .borderRadius(3)
      }
      .width('100%')
      .height(6)
      .backgroundColor('#EDEDED')
      .borderRadius(3)
    }
    .width('100%')
  }
}

/** 分组标题。 */
@Component
export struct SectionTitle {
  title: string = '';
  subtitle: string = '';

  build() {
    Column({ space: 2 }) {
      Text(this.title)
        .fontSize(FontSize.SECTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.TEXT_1)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(FontSize.CAPTION)
          .fontColor(Palette.TEXT_3)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 列表行：主文案 + 副文案 + 可选标签 + 可选箭头。 */
@Component
export struct ListRow {
  title: string = '';
  subtitle: string = '';
  tagText: string = '';
  tagBg: string = Palette.WARN_SOFT;
  tagFg: string = Palette.WARN;
  showArrow: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row({ space: Space.SM }) {
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(FontSize.BODY + 2)
          .fontColor(Palette.TEXT_1)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(FontSize.CAPTION)
            .fontColor(Palette.TEXT_3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.tagText.length > 0) {
        Tag({ text: this.tagText, bg: this.tagBg, fg: this.tagFg })
      }
      if (this.showArrow) {
        Text('›')
          .fontSize(20)
          .fontColor(Palette.TEXT_3)
      }
    }
    .width('100%')
    .padding({ top: Space.MD, bottom: Space.MD })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 设置行：文案 + 开关 / 值。 */
@Component
export struct SettingRow {
  @Prop label: string = '';
  @Prop desc: string = '';
  @Prop valueText: string = '';
  @Prop showToggle: boolean = false;
  @Prop toggleOn: boolean = false;
  onToggle: (on: boolean) => void = () => {
  };
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(FontSize.SECTION)
          .fontColor(Palette.TEXT_1)
        if (this.desc.length > 0) {
          Text(this.desc)
            .fontSize(FontSize.CAPTION)
            .fontColor(Palette.TEXT_3)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showToggle) {
        Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
          .selectedColor(Palette.BRAND)
          .onChange((isOn: boolean) => {
            this.onToggle(isOn);
          })
      } else {
        Text(this.valueText)
          .fontSize(FontSize.BODY)
          .fontColor(Palette.TEXT_2)
      }
    }
    .width('100%')
    .padding({ top: Space.MD, bottom: Space.MD })
    .onClick(() => {
      if (!this.showToggle) {
        this.onTap();
      }
    })
  }
}
