# 3D 机模制作说明（交给 Codex / Blender MCP）

## 目标

为 Island Menu（macOS 刘海性能监控卡片）制作一个 **14 寸 MacBook Pro（PROLED 新款，深空黑）合盖状态的"透视"机模**。
它显示在卡片顶部约 400 × 240 pt 的区域里，背景纯黑。App 会在运行时驱动它：风扇转子旋转并变色、各发热部件按温度变色、顶盖 logo 发光。

风格：半写实的 X 光 / 拆机示意，不追求照片级。外壳是深色半透明，能看清内部；内部部件轮廓清晰、层次分明。

## 环境

- Blender 4.1.1 已打开；Blender MCP 插件文件在 `tools/blender_mcp_addon.py`（需在 Blender 里安装并启动服务，端口 9876）。
- MCP 服务端命令：`uvx blender-mcp==2.0.0`（本项目 `.devin/mcp_config.json` 里有同样的配置可参考）。

## 参考资料（需要先找）

1. 这代 14 寸机型的拆机图（iFixit 或同类），确认：风扇位置和直径、热管走向、主板轮廓、SoC 位置、电芯数量和排布、扬声器、接口位置。存到 `assets/reference/`。
2. Apple 官方技术规格里的机身尺寸。下面的数字是上一代 14 寸的，**需要核对**：宽 312.6 mm × 深 221.2 mm × 厚 15.5 mm。
3. 顶盖 logo 的位置和大小（居中，发光）。

找不到这代的拆机图时，用上一代 14 寸 M 系列的内部布局，并在交付说明里写明。

## 坐标与单位

- 单位：米，按真实尺寸建模（宽约 0.3126）。
- Y 轴朝上，转轴（铰链）一侧朝 −Z，用户一侧朝 +Z；机身中心在原点，底面在 Y = 0。
- 所有物体应用缩放和旋转（Apply All Transforms），风扇转子例外：原点必须在转子圆心，旋转轴为本地 Y。

## 物体命名（App 按名字查找，不能改）

| 名称 | 说明 | App 怎么用 |
|---|---|---|
| `Shell_Bottom` | 底壳 | 静态 |
| `Shell_Lid` | 顶盖 + 侧壁，半透明 | 静态 |
| `Logo` | 顶盖上的 Apple logo，独立物体、独立材质 | 改自发光强度（0–1） |
| `Board` | 主板 | 静态 |
| `SoC_Package` | 芯片封装底座 | 静态 |
| `Die_Super` | Super 核心簇区域 | 按温度改颜色 |
| `Die_Perf` | Performance 核心簇区域 | 按温度改颜色 |
| `Die_GPU` | GPU 区域 | 按温度改颜色 |
| `Heatpipe` | 热管 + 散热鳍片 | 静态（铜色） |
| `Fan_L_Housing` / `Fan_R_Housing` | 风扇外壳 | 按转速改边缘发光颜色 |
| `Fan_L_Rotor` / `Fan_R_Rotor` | 风扇转子（含全部扇叶） | 绕本地 Y 轴旋转 |
| `SSD_0` / `SSD_1` | NAND 芯片 | 按温度改颜色 |
| `Battery_Cell_0` … `Battery_Cell_5` | 电芯，从左到右编号 | 按温度改颜色 |
| `Speaker_L` / `Speaker_R` | 扬声器 | 静态 |
| `Ports_L` / `Ports_R` | 两侧接口 | 静态 |

L / R 以用户视角为准（用户坐在 +Z 一侧看向 −Z）。电芯数量以拆机图为准，如果不是 6 块就按实际数量顺延编号。

## 材质要求

- 每个"按温度改颜色"的物体用**各自独立的材质**（不要共享），基础色深灰，Emission 留默认黑色，App 运行时写入。
- `Logo` 独立材质，白色自发光。
- `Shell_Lid` 深空黑、半透明（Alpha 约 0.2–0.3），略带金属感。
- 只用 Principled BSDF 的基础参数（Base Color、Metallic、Roughness、Emission、Alpha），不要程序化节点，不要贴图，保证导出后外观一致。

## 性能预算

- 整个模型 ≤ 30,000 三角面；单个风扇转子 ≤ 3,000。
- 材质数量 ≤ 25。
- 不带骨骼、不带烘焙动画、不带灯光和相机。

## 交付物

放在 `assets/model/`：

1. `macbook-pro-14.blend` — 源文件。
2. `macbook-pro-14.usdz` — 给 macOS App（SceneKit / RealityKit）用。
3. `macbook-pro-14.glb` — 给网页设计稿用。
4. `preview.png` — 从前上方约 45° 俯视的渲染图，黑色背景。
5. `README.md` — 写明实际使用的尺寸、参考图来源、与本说明不一致的地方。

## 验收

- [ ] 上表所有名称在导出的 usdz 和 glb 里都能按名字找到。
- [ ] 两个风扇转子绕本地 Y 轴旋转时不偏心。
- [ ] 从前上方 45° 看，风扇、热管、SoC 三块 die、SSD、全部电芯、logo 都清晰可辨。
- [ ] 三角面数和材质数在预算内。
- [ ] 合盖状态，机身比例与官方尺寸一致。
