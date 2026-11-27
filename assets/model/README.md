# Island Menu 的五款 MacBook 模型

每款机型都有 Blender 源文件、用于 SceneKit 的 USDZ、用于网页的 GLB，以及顶盖、底面和开盖三张 1600 × 1000 黑底渲染。底面图把底壳不透明度设为 20%，开盖图把铰链转至 108°。模型文件保存合盖静态姿态。单位为米，Y 向上，铰链朝 −Z，底面位于 Y = 0。L、R 以使用键盘者的视角为准。

| 机型与内部布局 | 合盖宽 × 深 × 厚（mm） | 原生分辨率 / ppi | 显示区宽 × 高（mm） | 电芯 | 风扇 | 三角面 | 材质 |
|---|---|---|---|---:|---:|---:|---:|
| Pro 14 PROLED · M5 Pro | 310.8 × 216.3 × 15.0 | 3024 × 1986 / 254 | 302.4 × 198.6 | 6 | 2 | 42,344 | 27 |
| Pro 14 刘海 · 2021 M1 Pro | 312.6 × 221.2 × 15.5 | 3024 × 1964 / 254 | 302.4 × 196.4 | 6 | 2 | 42,912 | 27 |
| Pro 16 刘海 · 2021 M1 系列 | 355.7 × 248.1 × 16.8 | 3456 × 2234 / 254 | 345.6 × 223.4 | 6 | 2 | 42,464 | 27 |
| Air 13 · 2022 M2 | 304.1 × 215.0 × 11.3 | 2560 × 1664 / 224 | 290.29 × 188.69 | 4 | 0 | 23,406 | 21 |
| Air 15 · 2023 M2 | 340.4 × 237.6 × 11.5 | 2880 × 1864 / 224 | 326.57 × 211.36 | 6 | 0 | 26,154 | 23 |

合盖尺寸、原生分辨率和像素密度取自下列 Apple 规格页。显示区按「像素数 × 25.4 ÷ ppi」计算，为包含圆角与摄像头区域的外接矩形。三角面按 GLB 中实际导出的索引计数，材质按导出材质表计数。

## 14 英寸 MacBook Pro PROLED XDR

沿用现有 M5 Pro 源模型的机壳、键盘、脚垫、底面铣字和白色发光标志。内部按同代拆机的开底全景、双风扇和电池照片重排。六块电芯位于两侧与中央。已把 SoC、三个热区和两颗 SSD 放在主板朝底壳的一侧。弯叶、轮毂、蜗壳、独立鳍片和连接器均为网格。顶盖标志宽约 38 mm、高约 47 mm，键盘区约 278 × 113 mm、触控板约 135 × 79 mm，均为同代照片估算。风管及盖住芯片的结构做了剖开处理。[Apple 技术规格](https://support.apple.com/en-us/148301) · [iFixit PROLED 拆机及发光标志照片](https://www.ifixit.com/News/120152/we-tore-down-the-macbook-proled-xdr-and-found-the-secret-of-the-glowing-apple)

[顶盖](macbook-pro-14-top.png) · [底面](macbook-pro-14-bottom.png) · [开盖](macbook-pro-14-open.png) · [前上方透视](preview.png)

## 14 英寸 MacBook Pro 刘海款

内部取自 2021 年 14 英寸 M1 Pro。按 iFixit 单独标注的 14 英寸俯视照片确定两侧风扇、后缘出风口和六块电芯。中央两块并排，各自沿机身前后方向延伸，两侧各有前后两块。型号对应深空灰外壳、镜面标志和连接上边框的刘海。左侧依次为 MagSafe、两个雷雳口和耳机孔，右侧为 HDMI、雷雳口和 SD 卡槽。风扇中心距约 192 mm、转子外径约 63 mm，均为照片估算。主板双面的存储封装在底视图中归并为两个温度区域。[Apple 技术规格](https://support.apple.com/en-us/111902) · [iFixit 14/16 英寸对照拆机](https://www.ifixit.com/News/54122/macbook-pro-2021-teardown) · [14 英寸主板芯片标识](https://www.ifixit.com/Teardown/MacBook+Pro+14-Inch+2021+Chip+ID/145718)

[顶盖](macbook-pro-14-notch-top.png) · [底面](macbook-pro-14-notch-bottom.png) · [开盖](macbook-pro-14-notch-open.png)

## 16 英寸 MacBook Pro 刘海款

外壳与电池使用 2021 年 16 英寸拆机图。六块电芯中，两侧靠铰链的电芯比同侧靠前缘的电芯宽，中央两块在触控板后方收短。按 16 英寸照片独立定位风扇和排风口，估算风扇中心距约 223 mm、转子外径约 66 mm。键盘保持与 14 英寸刘海款相同的宽度，较宽的两侧区域留给扬声器。芯片采用 M1 Pro 的三个温区，细小元件和 NAND 投影使用同代 14 英寸的芯片标识图作补充。接口种类与左右分布同 14 英寸。[Apple 技术规格](https://support.apple.com/en-us/111901) · [iFixit 同代全景、风扇和两套电池对照](https://www.ifixit.com/News/54122/macbook-pro-2021-teardown) · [16 英寸电池维修照片](https://www.ifixit.com/Guide/MacBook+Pro+16-Inch+2021+Battery+Replacement/150593)

[顶盖](macbook-pro-16-notch-top.png) · [底面](macbook-pro-16-notch-bottom.png) · [开盖](macbook-pro-16-notch-open.png)

## 13 英寸 MacBook Air

取自 2022 年 M2。四块电芯构成两块横向长电芯和靠前缘的左右两块，中间留有触控板控制器的位置。狭长主板和扬声器靠铰链布置。左侧为 MagSafe 和两个雷雳口，右侧为耳机孔。午夜色外壳、镜面标志、无风扇。照片可见被动散热用的薄屏蔽罩，模型用有观察开口的薄件表示，节点名为 Heatsink。M2 和 NAND 的位置按芯片标识图估算；256 GB 拆机样本可见一颗 NAND，模型采用双封装存储示意以对应两个 SSD 节点。[Apple 技术规格](https://support.apple.com/en-us/111867) · [iFixit M2 拆机与 X 光图](https://www.ifixit.com/News/62674/m2-macbook-air-teardown-apple-forgot-the-heatsink) · [M2 芯片标识](https://www.ifixit.com/Teardown/Macbook+Air+(M2+2022)+Logic+Board+and+Chip+Identification/151816)

[顶盖](macbook-air-13-top.png) · [底面](macbook-air-13-bottom.png) · [开盖](macbook-air-13-open.png)

## 15 英寸 MacBook Air

取自 2023 年 M2。按 15 英寸开底照片分别划出后排两块长电芯，以及靠前左右各两块较小电芯。六块总数亦见 TechInsights 的 A2941 拆机。两侧扬声器总成各包含三个单元，分别合并到 Speaker_L 和 Speaker_R。扬声器单元的中心、声腔深度、主板轮廓和遮罩开口为估算。午夜色外壳、被动散热、接口左右分布与 13 英寸相同，触控板与电池布局使用 15 英寸尺寸。[Apple 技术规格](https://support.apple.com/en-gb/111346) · [iFixit 15 英寸拆机、主板及扬声器对照](https://www.ifixit.com/News/76973/15-macbook-air-teardown-bigger-and-better-maybe-not-en) · [TechInsights A2941 电芯数量](https://www.techinsights.com/ko/node/53554)

[顶盖](macbook-air-15-top.png) · [底面](macbook-air-15-bottom.png) · [开盖](macbook-air-15-open.png)

## 估算和展示取舍

以开底照片或 X 光图的机身四角校正透视，再用官方宽深换算平面距离。圆角、侧壁倒角、铰链缺口、接口中心与凹入深度、刘海轮廓、风扇直径、电芯接缝、各部件高度和排线走向均为估算。端口外形保留了磁吸触点、USB-C 舌片、HDMI 斜边和 SD 狭槽。剖开的风道保留弯叶和朝铰链的出口。每个转子的建模叶片数为 PROLED 58、14 英寸刘海款 70、16 英寸刘海款 62，取自照片可见叶缘的估算。叶片使用等间隔重复，实际不等距及左右个体差异未逐片重建。

为了在监控卡片尺寸下读出发热区域，屏蔽罩和风道保留观察开口，SoC 封装和焊在两面的芯片投影到可见一侧。CPU、GPU 分区是温度示意。电源芯片、扬声器孔、固定柱和排线保留主要轮廓，省略厂商丝印、细焊点和声学腔体内部。照片存放在本地忽略目录。旧版带展示动画的视频和带 xray 后缀的文件保留作历史对照。

## 验收

在项目根目录运行以下命令。脚本逐款检查源文件、重新导入的 GLB、USDZ 中的节点与材质、闭合尺寸、铰链层级、转子原点、底视遮挡和三张预览的尺寸。底视检测忽略可调透明的底壳，保留主板和其余实体作为遮挡物。

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 -P tools/check_island_model.py
```
