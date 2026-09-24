/**
 * 设计令牌（A-12 / NFR-09：仅使用系统组件与统一视觉常量）。
 * 页面不再硬编码色值 / 字号 / 间距，统一从这里取值。
 */

export class Palette {
  /** 主色：动作、选中、进度 */
  static readonly BRAND: string = '#2E7D32';
  static readonly BRAND_SOFT: string = '#E8F5E9';

  /** 提示语义色 */
  static readonly WARN: string = '#E65100';
  static readonly WARN_SOFT: string = '#FFF3E0';
  static readonly DANGER: string = '#C62828';
  static readonly DANGER_SOFT: string = '#FFEBEE';
  static readonly INFO: string = '#1565C0';
  static readonly INFO_SOFT: string = '#E3F2FD';

  /** 文字三级 */
  static readonly TEXT_1: string = '#1A1A1A';
  static readonly TEXT_2: string = '#5A5A5A';
  static readonly TEXT_3: string = '#8A8A8A';
  static readonly TEXT_ON_BRAND: string = '#FFFFFF';

  /** 背景与分隔 */
  static readonly BG_PAGE: string = '#F6F7F9';
  static readonly BG_CARD: string = '#FFFFFF';
  static readonly BG_SUBTLE: string = '#F0F0F0';
  static readonly DIVIDER: string = '#EEEEEE';
  static readonly DIVIDER_SOFT: string = '#F5F5F5';
}

export class FontSize {
  static readonly TITLE: number = 20;
  static readonly SUBTITLE: number = 17;
  static readonly SECTION: number = 15;
  static readonly BODY: number = 14;
  static readonly BUTTON: number = 15;
  static readonly CAPTION: number = 12;
  static readonly CHIP: number = 12;
}

export class Space {
  static readonly XS: number = 4;
  static readonly SM: number = 8;
  static readonly MD: number = 12;
  static readonly LG: number = 16;
  static readonly XL: number = 24;
}

export class Radius {
  static readonly CHIP: number = 8;
  static readonly CARD: number = 14;
  static readonly PILL: number = 20;
  static readonly BAR: number = 12;
}

export class Size {
  /** 主按钮高度（满足 ≥44vp 可点区域） */
  static readonly BUTTON: number = 46;
  static readonly BUTTON_SMALL: number = 36;
  /** 顶部栏高度 */
  static readonly APP_BAR: number = 52;
  /** 底部导航高度 */
  static readonly TAB_BAR: number = 56;
  static readonly TAB_ICON: number = 22;
}
