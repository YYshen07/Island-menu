# 14 英寸 MacBook Pro · PROLED XDR

深空黑合盖透视模型，按 2026 年 14 英寸 M5 Pro / M5 Max 共用外形制作。官方尺寸为宽 310.8 mm、深 216.3 mm、厚 15.0 mm。模型单位为米，Y 向上，铰链朝 −Z，底面在 Y=0。GLB 导入 Blender 时，Blender 自动换算到自身的 Z 向上坐标。

[Apple 技术规格](https://support.apple.com/en-us/148301) · [iFixit 同代拆机原文](https://www.ifixit.com/News/120152/we-tore-down-the-macbook-proled-xdr-and-found-the-secret-of-the-glowing-apple)

参考照片位于 `../reference/`。iFixit 的 MacBook-proled_102 展示开盖后的内部，113b 展示电池模组，148 展示侧面接口，Apple-lid-cutout_b 展示标志和拆下的部件。照片仅用于建模参考。所有几何均手工定义，模型无照片纹理。外形三维采用官方数值，风扇直径、板形、铜管路径、接口轮廓和标志尺寸为示意估算。芯片表面分区用于显示监控数据，位置和面积不代表实际硅片版图。六块电芯从左到右编号，同列从铰链侧开始。

源文件与两个导出包均只含机模。preview.png 使用临时摄影机和两盏面光源，从用户一侧约 45° 渲染。顶盖为带侧壁的单层透明表皮，Alpha 0.23。每个温控物体独享材质。

验收时读取 USDZ 内的 USD Mesh 名和 GLB 节点名，与要求的 25 个名称完全一致。在独立的 Blender 4.1.1 进程重新导入 GLB 后名称与机身尺寸均通过。GLB 共 18,082 个三角面，每个风扇转子 1,196 个，20 种材质。两个转子的局部中心在 Y 轴上；以三个角度旋转后，中心位移均小于 0.0001 mm。预览中可辨认双风扇、热管与鳍片、三块 die、两颗 SSD、六块电芯及白色标志。未进行 App 运行时联调。

从项目根目录运行 `blender -b --python-exit-code 1 -P tools/check_island_model.py` 可复查导出物。
