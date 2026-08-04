/**
 * ImagePreviewDialog.ets
 * 全屏图片预览弹窗：Swiper 左右滑动、双击缩放、单击空白处/右上角按钮关闭
 */
@CustomDialog
export struct ImagePreviewDialog {
  controller?: CustomDialogController
  @Link images: string[]
  @Link currentIndex: number
  @State scale: number = 1

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
              .scale({ x: this.scale, y: this.scale })
              .animation({ duration: 200, curve: Curve.EaseOut })
              .gesture(
                TapGesture({ count: 2 })
                  .onAction(() => {
                    this.scale = this.scale > 1 ? 1 : 2.6;
                  })
              )
          }
          .width('100%')
          .height('100%')
          .clip(true)
        }, (src: string, index: number) => index.toString())
      }
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.currentIndex = index;
        this.scale = 1;
      })

      // 右上角关闭按钮
      Text('✕')
        .fontSize(18)
        .fontColor(Color.White)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .backgroundColor('#66000000')
        .borderRadius(18)
        .margin({ top: 48, right: 20 })
        .align(Alignment.TopEnd)
        .onClick(() => {
          this.controller?.close();
        })

      // 底部页码
      Text(`${this.currentIndex + 1} / ${this.images.length}`)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#66000000')
        .borderRadius(12)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .margin({ bottom: 32 })
        .align(Alignment.Bottom)
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
