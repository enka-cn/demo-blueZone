import { camera, cameraPicker } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DateUtil, ImageSource, Logger } from '../../common/Common';

/** 上传前长边上限：远低于服务端 8192px 单边限制，同时压住请求体体积。 */
const MAX_UPLOAD_EDGE: number = 1568;
/** JPEG 压缩质量：识别食材清单够用，又能明显缩小 base64 体积。 */
const UPLOAD_JPEG_QUALITY: number = 80;

/** 采集到的图像（uri 为空表示预置样张回退）。 */
export interface PickedImage {
  uri: string;
  source: string;
}

/** 上传给模型服务的图片载荷：统一为受支持格式，并带实际尺寸便于排查。 */
export interface UploadImage {
  base64: string;
  mime: string;
  width: number;
  height: number;
  bytes: number;
}

/**
 * 系统能力适配（IF-01 相机图像采集、IF-08 时钟）。
 * 统一走系统 Picker，用户主动拍摄 / 选择，返回只读 URI。
 */
export class SystemAdapter {
  /** IF-08 时钟：提供当前时间，用于时间戳与过期判断（FR-24）。 */
  static nowIso(): string {
    return DateUtil.nowIso();
  }

  /** IF-01：相机实拍（系统相机托管）。 */
  static async pickFromCamera(context: common.Context): Promise<PickedImage | null> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result: cameraPicker.PickerResult =
        await cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        return { uri: result.resultUri, source: ImageSource.CAMERA };
      }
      return null;
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(`pickFromCamera failed: ${err.code}`);
      return null;
    }
  }

  /** IF-01：相册导入（系统图库托管，只读 URI）。 */
  static async pickFromAlbum(context: common.Context): Promise<PickedImage | null> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length > 0) {
        return { uri: result.photoUris[0], source: ImageSource.ALBUM };
      }
      return null;
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(`pickFromAlbum failed: ${err.code}`);
      return null;
    }
  }

  /** 预置样张回退（A-8）。 */
  static preset(): PickedImage {
    return { uri: '', source: ImageSource.PRESET };
  }

  /** 读取图像为 base64（IF-02 传输格式；识别后由调用方清理临时文件）。 */
  static readAsBase64(uri: string): string {
    if (uri.length === 0) {
      return '';
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = fs.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const bytes: Uint8Array = new Uint8Array(buffer);
      return new util.Base64Helper().encodeToStringSync(bytes);
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(`readAsBase64 failed: ${err.code}`);
      return '';
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  /**
   * 上传前统一转码：长边压到 MAX_UPLOAD_EDGE 以内并输出 JPEG。
   * 模型服务只接受 JPEG / PNG / GIF / WebP，且单边不得超过 8192px、单图不得超过 32MiB；
   * 相机与相册都可能给出 HEIC 或超大原图，因此一律先转码再上传。
   */
  static async prepareForUpload(uri: string): Promise<UploadImage> {
    if (uri.length === 0) {
      return SystemAdapter.emptyUpload();
    }
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const decoder: image.ImageSource = image.createImageSource(file.fd);
      source = decoder;
      const info: image.ImageInfo = await decoder.getImageInfo();
      const longEdge: number = Math.max(info.size.width, info.size.height);
      const scale: number = longEdge > MAX_UPLOAD_EDGE ? MAX_UPLOAD_EDGE / longEdge : 1;
      const targetWidth: number = Math.max(1, Math.round(info.size.width * scale));
      const targetHeight: number = Math.max(1, Math.round(info.size.height * scale));
      const decodeOptions: image.DecodingOptions = {
        desiredSize: { width: targetWidth, height: targetHeight },
        editable: false
      };
      const decoded: image.PixelMap = await decoder.createPixelMap(decodeOptions);
      pixelMap = decoded;
      const encoder: image.ImagePacker = image.createImagePacker();
      packer = encoder;
      const packingOptions: image.PackingOption = {
        format: 'image/jpeg',
        quality: UPLOAD_JPEG_QUALITY
      };
      const buffer: ArrayBuffer = await encoder.packing(decoded, packingOptions);
      const bytes: Uint8Array = new Uint8Array(buffer);
      Logger.info(`upload image prepared: ${targetWidth}x${targetHeight}, ${bytes.length} bytes`);
      return {
        base64: new util.Base64Helper().encodeToStringSync(bytes),
        mime: 'image/jpeg',
        width: targetWidth,
        height: targetHeight,
        bytes: bytes.length
      };
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(`prepareForUpload failed: ${err.code}, fallback to raw bytes`);
      return SystemAdapter.rawUpload(uri);
    } finally {
      if (packer !== null) {
        packer.release();
      }
      if (pixelMap !== null) {
        pixelMap.release();
      }
      if (source !== null) {
        source.release();
      }
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  /** 转码失败时的兜底：按 base64 前缀判断真实格式，避免声明与实际内容不符。 */
  private static rawUpload(uri: string): UploadImage {
    const base64: string = SystemAdapter.readAsBase64(uri);
    if (base64.length === 0) {
      return SystemAdapter.emptyUpload();
    }
    return {
      base64: base64,
      mime: SystemAdapter.sniffMime(base64),
      width: 0,
      height: 0,
      bytes: 0
    };
  }

  private static emptyUpload(): UploadImage {
    return { base64: '', mime: '', width: 0, height: 0, bytes: 0 };
  }

  /** base64 前缀即文件头，足以区分模型服务支持的四种格式。 */
  private static sniffMime(base64: string): string {
    if (base64.startsWith('iVBOR')) {
      return 'image/png';
    }
    if (base64.startsWith('R0lGO')) {
      return 'image/gif';
    }
    if (base64.startsWith('UklGR')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /** 识别完成后清理临时文件（照片不落盘，§5.1 隐私最小化）。 */
  static cleanup(uri: string): void {
    if (uri.length === 0) {
      return;
    }
    try {
      fs.unlinkSync(uri);
    } catch (e) {
      Logger.warn('cleanup temp file skipped');
    }
  }
}
