# 14 英寸 PROLED XDR MacBook Pro · M5 Pro

模型单位为米，Y 向上，铰链朝 −Z，底面在 Y=0。合盖宽 310.8 mm、深 216.3 mm、厚 15.0 mm。[Apple 技术规格](https://support.apple.com/en-us/148301)

内部使用中性黑、灰和银色。发热件保留各自独立的基础材质。芯片表面的 M5 Pro 铭文属于 SoC_Package，三块 die 仍可单独寻址。顶盖外侧的 Logo 使用独立白色自发光材质，随铰链转动。底部 MacBook Pro 字样直接切入 Shell_Bottom 网格，槽底与侧壁仅反射环境光。

[iFixit 同代拆机照片](https://www.ifixit.com/News/120152/we-tore-down-the-macbook-proled-xdr-and-found-the-secret-of-the-glowing-apple)位于 ../reference/。121 号照片同时展示屏幕后盖和机身底面。按四角校正透视后估算，顶盖标志约宽 38 mm、高 47 mm，中心约在外盖中线偏左 1.6 mm、中心偏前 4.5 mm。148 号侧视照片用于校对两侧接口。热管、风扇和主板按照片估算，芯片分区为温度展示示意。

整机 GLB 与 USDZ 均包含 11 秒 Inspection_Loop 展示过程。24 fps 下，第 1 至 265 帧定义一个周期：合盖、打开至 108°、关盖、底盖的不透明度由 100% 降至 3.5%、停留观察双风扇、恢复不透明。左右转子各完成一整圈并加减速；转速为便于观察的示意。首尾姿态相同。inspection-loop.mp4 为 264 帧，省略下一周期重复的起始帧。镜头移至底面的动作只属于视频。模型播放器应启用重复播放，GLB 的透明度播放还需要支持 KHR_animation_pointer。USDZ 使用原生材质 opacity 时间采样。键盘、触控板和屏幕全程保持固定尺寸，屏幕默认无自发光。

比例复核：同代 iFixit 61 号照片校正透视得到 deck-rectified.jpg，按宽 310.8、深 216.3 mm 换算。键盘区由 229 × 88 调至约 278 × 113 mm，触控板由 129 × 76 调至约 135 × 79 mm，中心距前缘 44.2 mm。二者为照片估算。苹果官方规格给出的 3024 × 1986 和 254 ppi 换算为约 302.4 × 198.6 mm 的显示区。按官方正视图 apple-14-proled-spec.png 校正位置后，从显示区直边至外盖边缘，左右各 4.2 mm，顶部约 4.4 mm，铰链侧约 13.4 mm（包含结构下沿）。

透视模型 macbook-pro-14-xray.glb / .usdz 为静态监控视图。preview.png、open.png、closed.png 和 bottom-transparent.png 分别展示合盖透视、打开、外盖及底盖透明状态。两种 GLB 均已重新导入，两种 USDZ 均已核对网格名。整机 33 个节点、26,803 个三角面、25 种材质；每个风扇转子 1,196 个三角面。已核对 GLB 的三条旋转轨道、透明度扩展轨道，USDZ 的三组首尾变换与材质透明度。未进行 App 内播放联调。

从项目根目录运行 blender -b --python-exit-code 1 -P tools/check_island_model.py 可复查导出物。
