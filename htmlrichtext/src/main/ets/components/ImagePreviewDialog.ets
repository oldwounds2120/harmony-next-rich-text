/**
 * ImagePreviewDialog.ets
 * 全屏图片预览弹窗：Swiper 左右滑动、捏合缩放、放大后拖动、双击缩放切换、
 * 单击空白处/底部按钮关闭
 *
 * 设计要点：
 *  - images/currentIndex 用普通参数 + @State：@State 可观察（页码随滑动更新），
 *    且可用 builder 参数初始化（@Link 无法用 this.xxx 初始化，编译报错）；
 *  - 底部控制栏用 Column{ Blank + Row } 确定性布局沉底，避免 Stack .align()
 *    在 @CustomDialog 中定位不可靠；hitTestBehavior(Transparent) 不遮挡图片手势；
 *  - 关闭 ✕ 用 Stack 包裹，保证文字在 36×36 圆形按钮正中。
 *  - 手势三件套（Image 上挂载，Swiper 上 parallel 挂载保证共存）：
 *      捏合 PinchGesture：缩放 1~4 倍（baseScale 记录起始值，event.scale 是相对比例）；
 *      拖动 PanGesture：仅缩放 >1 时生效；event.offsetX/Y 是"相对手势起点的累计位移"，
 *        因此 onActionStart 记录 startOffsetX/Y，onActionUpdate 用"起点+累计值"赋值
 *        （严禁 += 累计值，会导致位移超调——"来回跑"根因）；
 *      双击 TapGesture：在 1 与 2.6 之间切换；
 *  - isDisableSwipe 仅在离散时机设置（toggleZoom / 捏合结束 / onChange 切图），
 *    拖动过程中不逐帧翻转，避免 Swiper 与 Pan 抢手势导致回弹抖动；
 *    放大期间（scale>1.01）恒定禁用 Swiper，平移边界由 clampOffset 控制；
 *  - clampOffset 用真实屏幕宽高（vp）计算 X/Y 双向平移边界。
 */
import { display } from '@kit.ArkUI';

@CustomDialog
export struct ImagePreviewDialog {
  controller?: CustomDialogController
  images: string[] = []
  @State currentIndex: number = 0
  @State zoomScale: number = 1
  @State baseScale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State isPinching: boolean = false
  /** 是否禁用 Swiper 滑动切换：放大期间恒定禁用（让 Pan 拖动），缩回 1 倍恢复切图 */
  @State isDisableSwipe: boolean = false
  /** Pan/Pinch 手势起始偏移记录（event.offsetX/Y 是相对手势起点的累计位移） */
  startOffsetX: number = 0
  startOffsetY: number = 0
  /** 弹窗渲染区域尺寸（vp），aboutToAppear 时从 display 获取，用于平移边界计算 */
  screenW: number = 0
  screenH: number = 0

  /**
   * 弹窗挂载前获取真实屏幕尺寸（vp），用于平移边界计算
   * TODO(折叠屏/分屏适配)：display.getDefaultDisplaySync() 只取一次，
   * 分屏/折叠态变化时尺寸不会自动刷新，后续需监听窗口尺寸变化更新。
   */
  aboutToAppear(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      this.screenW = d.width / d.densityPixels;
      this.screenH = d.height / d.densityPixels;
    } catch (e) {
      // 兜底：获取失败时使用常见尺寸，避免空值影响边界计算
      this.screenW = 360;
      this.screenH = 780;
    }
  }

  /**
   * 双击缩放切换（动画平滑）
   */
  private toggleZoom(): void {
    this.getUIContext()?.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      if (this.zoomScale > 1) {
        this.zoomScale = 1;
        this.offsetX = 0; // 缩回 1 倍，清除拖动偏移，避免残影
        this.offsetY = 0;
      } else {
        this.zoomScale = 2.6;
        this.clampOffset(); // 放大后按新边界 clamp（原偏移超出新边界时收进可视区）
      }
    });
    // 离散时机：缩放目标确定后设置一次 Swiper 禁用状态（不做逐帧翻转）
    this.updateSwipeState();
  }

  /**
   * 平移边界 clamp：缩放以组件中心为锚点，可平移范围 = ±渲染尺寸×(scale-1)/2。
   * 使用真实屏幕宽高（vp）计算，X/Y 双向限制；拖动越界即收敛，
   * 不再依赖 Swiper 状态翻转来"放行"（防抢手势/回弹抖动）。
   */
  private clampOffset(): void {
    const scale: number = this.zoomScale;
    if (scale <= 1.01) {
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    const maxX: number = this.screenW * (scale - 1) / 2;
    const maxY: number = this.screenH * (scale - 1) / 2;
    if (this.offsetX > maxX) {
      this.offsetX = maxX;
    } else if (this.offsetX < -maxX) {
      this.offsetX = -maxX;
    }
    if (this.offsetY > maxY) {
      this.offsetY = maxY;
    } else if (this.offsetY < -maxY) {
      this.offsetY = -maxY;
    }
  }

  /**
   * 更新 Swiper 禁用状态（仅在离散时机调用：toggleZoom 完成 / 捏合结束 / onChange 切图）：
   *  - 未放大（scale≈1）→ 允许 Swiper 切换
   *  - 放大期间 → 恒定禁用 Swiper，平移边界由 clampOffset 控制，
   *    避免拖动过程中 disableSwipe 动态翻转导致 Swiper 抢手势/回弹抖动（"来回跑"根因）
   */
  private updateSwipeState(): void {
    this.isDisableSwipe = this.zoomScale > 1.01;
  }

  build() {
    Stack() {
      // 图片区域
      Swiper() {
        ForEach(this.images, (src: string, index: number) => {
          Stack() {
            Image(src)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .scale({ x: this.zoomScale, y: this.zoomScale })
              .translate({ x: this.offsetX, y: this.offsetY })
              // 注意：这里不能挂 .animation()——捏合/拖动是逐帧跟手更新，
              // 若对每次变化播放动画会造成"图片来回跑"的抖动。
          }
          .width('100%')
          .height('100%')
          .clip(true)
        }, (src: string, index: number) => index.toString())
      }
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      // 放大且未到边界时禁用 Swiper 滑动，避免与 Pan 拖动抢手势（官方 Best Practice）
      .disableSwipe(this.isDisableSwipe)
      .onChange((index: number) => {
        this.currentIndex = index; // 页码随滑动更新
        this.zoomScale = 1;        // 切图时重置缩放
        this.offsetX = 0;          // 并清除拖动偏移
        this.offsetY = 0;
        this.isDisableSwipe = false;
      })
      // 手势必须内联在 build() 的属性链里（不能声明为 struct 字段，也不能
      // 在 build() 里先声明变量——build() 只允许一个根节点 + 属性链）。
      .parallelGesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.baseScale = this.zoomScale;
              this.isPinching = true;   // 捏合期间禁用 Pan，防偏移叠加
              // 与 Pan 共用起点：捏合期间若 Pan 仍在活动，
              // 结束后按"起点+累计位移"计算，避免画面跳变
              this.startOffsetX = this.offsetX;
              this.startOffsetY = this.offsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              let next: number = this.baseScale * event.scale;
              if (next < 1) {
                next = 1;
              } else if (next > 4) {
                next = 4;
              }
              this.zoomScale = next;
              // 缩回 1 倍时清除拖动偏移，避免残影
              if (next <= 1.01) {
                this.offsetX = 0;
                this.offsetY = 0;
              } else {
                this.clampOffset(); // 缩放变化后按新边界收敛偏移
              }
            })
            .onActionEnd(() => {
              this.isPinching = false;  // 捏合结束，恢复 Pan
              this.updateSwipeState();  // 离散时机：捏合结束设置一次 Swiper 禁用状态
            }),
          PanGesture({ direction: PanDirection.All })
            .onActionStart(() => {
              // 记录本次拖动起点：event.offsetX/Y 是"相对手势起点的累计位移"，
              // 更新时必须用"起点 + 累计位移"赋值（严禁 += 累计值，否则位移超调，
              // 画面跑得比手指快——"来回跑"根因之一）
              this.startOffsetX = this.offsetX;
              this.startOffsetY = this.offsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              // 仅在放大状态、且非捏合期间允许拖动查看细节
              if (this.zoomScale <= 1.01 || this.isPinching) {
                return;
              }
              this.offsetX = this.startOffsetX + event.offsetX;
              this.offsetY = this.startOffsetY + event.offsetY;
              // 边界 clamp 由 Pan 自身控制，不在此翻转 Swiper 状态（防抢手势/回弹抖动）
              this.clampOffset();
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              this.toggleZoom();
            })
        )
      )

      // 底部控制栏：页码 + 关闭按钮（沉底显示，避开系统导航区；Transparent 不遮挡图片滑动）
      Column() {
        Blank()
        Row() {
          // 页码
          Text(`${this.currentIndex + 1} / ${this.images.length}`)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#66000000')
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          // 关闭按钮（Stack 包裹，保证 ✕ 在圆圈正中）
          Stack() {
            Text('✕')
              .fontSize(18)
              .fontColor(Color.White)
          }
          .width(36)
          .height(36)
          .backgroundColor('#66000000')
          .borderRadius(18)
          .margin({ left: 16 })
          .onClick(() => {
            this.controller?.close();
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ bottom: 36 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .gesture(
      TapGesture()
        .onAction(() => {
          this.controller?.close();
        })
    )
  }
}
