import { promptAction, router } from '@kit.ArkUI';
import { Palette, FontSize } from '../view/Theme';
import { AppService } from '../common/AppService';
import { ImageSource } from '../common/Common';
import { CaptureParams } from '../data/model/Models';
import { SystemAdapter } from '../adapter/system/SystemAdapter';
import { SeedData, PresetSample } from '../data/seed/SeedData';
import { AppBar, Card, ListRow, LoadingView, PrimaryButton, SecondaryButton, SectionTitle, Tag } from '../view/Widgets';

/**
 * 拍照 / 图像源页（IF-01 / FR-01）。
 * 相机实拍 + 相册 / 预置样张导入；云真机 / 模拟器无实物冰箱时使用预置样张回退（A-8）。
 */
@Entry
@Component
struct CapturePage {
  @State samples: PresetSample[] = SeedData.samples();
  @State busy: boolean = false;
  /** 链路模式由 AppStorage 广播：在「我的」切换后本页卡片与文案立即跟随。 */
  @StorageProp('runModeIsMock') mockMode: boolean = true;

  aboutToAppear(): void {
    AppService.whenReady().then(() => {
      AppService.publishRunMode();
    });
  }

  private goReview(uri: string, source: string, presetKey: string): void {
    const params: CaptureParams = { uri: uri, source: source, presetKey: presetKey };
    router.pushUrl({ url: 'pages/ReviewPage', params: params }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  private async takePhoto(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const picked = await SystemAdapter.pickFromCamera(AppService.getContext());
    this.busy = false;
    if (picked === null) {
      promptAction.showToast({ message: '已取消，可以改用相册照片' });
      return;
    }
    this.goReview(picked.uri, picked.source, '');
  }

  private async pickAlbum(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const picked = await SystemAdapter.pickFromAlbum(AppService.getContext());
    this.busy = false;
    if (picked === null) {
      promptAction.showToast({ message: '已取消选择' });
      return;
    }
    this.goReview(picked.uri, picked.source, '');
  }

  private usePreset(sample: PresetSample): void {
    const picked = SystemAdapter.preset();
    this.goReview(picked.uri, ImageSource.PRESET, sample.key);
  }

  build() {
    Column() {
      AppBar({
        title: '拍冰箱',
        showBack: true,
        onBack: () => {
          router.back();
        }
      })
        .padding({ left: 16, right: 16, top: 4 })

      Scroll() {
        Column({ space: 16 }) {
          Card() {
            Column({ space: 12 }) {
              SectionTitle({ title: '选一张冰箱照片', subtitle: '照片只用来识别食材，不会保存到相册' })
              if (this.busy) {
                LoadingView({ text: '正在打开相机…' })
              } else {
                PrimaryButton({
                  label: '拍照',
                  onTap: () => {
                    this.takePhoto();
                  }
                })
                SecondaryButton({
                  label: '从相册选',
                  onTap: () => {
                    this.pickAlbum();
                  }
                })
              }
            }
            .width('100%')
          }

          // 预置样张只属于模拟演示链路；真实链路下隐藏，避免用示例结果混淆真实识别
          if (this.mockMode) {
            Card() {
              Column({ space: 10 }) {
                SectionTitle({ title: '没有实物冰箱？用示例照片试试' })
                ForEach(this.samples, (sample: PresetSample) => {
                  ListRow({
                    title: sample.name,
                    subtitle: sample.desc,
                    showArrow: true,
                    onTap: () => {
                      this.usePreset(sample);
                    }
                  })
                }, (sample: PresetSample) => sample.key)
              }
              .width('100%')
            }
          } else {
            Card() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Column() {
                    SectionTitle({ title: '真实识别链路' })
                  }
                  .layoutWeight(1)

                  Tag({ text: '真实识别', bg: Palette.BRAND_SOFT, fg: Palette.BRAND })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                Text('照片会上传到模型进行识别；识别失败会直接提示重试，不会用示例数据顶替。')
                  .fontSize(12)
                  .fontColor(Palette.TEXT_3)
                  .width('100%')
              }
              .width('100%')
            }
          }

          Text(this.mockMode
            ? '模拟演示：照片只在本机，识别结果来自内置示例数据'
            : '真实识别：照片会上传给模型，不保存到相册')
            .fontSize(FontSize.CAPTION)
            .fontColor(Palette.TEXT_3)
            .width('100%')
            .textAlign(TextAlign.Center)
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
