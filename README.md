<p align="center"><img src="docs/images/icon.png" width="128" alt="Island Menu"></p>

# Island Menu

常驻后台的 macOS 性能监控。点击 MacBook 的灵动岛或刘海，会从那里展开一张卡片，显示 CPU、内存、GPU、储存、电池、网络、进程和温度。

![展开的卡片：顶盖面、底面热力图、开盖姿态](docs/images/card.png)

机模平时是静帧，单击翻面，双击开合屏幕：

![机模翻面与开盖](docs/images/model.gif)

| 卡片下半部分 | 刘海机型的版式 |
|---|---|
| ![进程、信仰灯与活跃热力图](docs/images/card-bottom.png) | ![从刘海展开的卡片](docs/images/notch.png) |

项目处于早期开发阶段，目前只在 14 寸 M5 Pro（Mac17,13，macOS 27.3）上实际运行过。刘海版式是在这台机器上模拟出来的，
还没有在真正的刘海机型或 macOS 27.2 上运行过。

## 现状

已有：

- 原生灵动岛提醒：CPU、GPU、温度、储存或电量越过设置里的阈值时，系统灵动岛右侧出现一个提醒，恢复后自动消失；点开有简短说明和「展开面板」
- 完整面板：从灵动岛位置展开的卡片；刘海机型上从刘海展开，顶边与边框相连（设置里可手动切换版式）
- CPU 每核占用、内存、储存、GPU 占用与显存、电池、网络速率与接口、公共 IP、进程排行
- 芯片、SSD、电池温度，风扇转速
- 3D 机模：展开时随机显示顶盖（发光 logo）或底面（温度热力图、风扇与气流），单击翻面，双击开合屏幕
- 五款机模（PROLED Pro 14、刘海 Pro 14 / 16、Air 13 / 15），按本机硬件自动选择；机身颜色可在设置的「机模」页按 Pro / Air / Neo 系列任选，开盖时屏幕可显示当前壁纸或自己上传的图片
- 彩色 / 纯白两种配色
- 顶盖 logo 灯：自动 / 呼吸 / 音跃（随系统声音律动）
- 风扇控制：自动 / 最大 / 策略（自定义温度曲线），通过一个需要你批准的后台组件写入转速
- 充电上限：自动 / 养护 / 满充，使用 macOS 自带的充电上限
- 拖动文件时在灵动岛下方出现隔空投送投放区
- 设置窗口（菜单栏图标或卡片右上角的齿轮）
- 每日活跃时长记录与热力图

### 防休眠

点卡片左上角的苹果标开启，再点一次关闭：

- 开启后 Mac 不会进入睡眠，屏幕调到你设定的亮度（设置 →「通用」→ 防休眠，默认 20%），适合挂着下载、跑任务时用。
- 关闭或退出 App 时恢复原来的亮度。
- 开启期间苹果标变成彩色；机模上的 logo 在有信仰灯的机型上像夜店灯一样跳色闪烁，在其他机型上是一道扫过镜面 logo 的高光。

采集只在卡片展开时运行；收起后只剩每分钟一次的活跃时长记录。

## 构建

构建需要 Xcode 27.3（测试版期间装在 `/Applications/Xcode-beta.app`）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

构建出的 App 最低可在 macOS 27.0 上启动；灵动岛提醒依赖 macOS 27.3 的实时活动，更早的系统上没有提醒，其余功能不变。

```sh
./scripts/bundle.sh                 # 生成 build/Island Menu.app
open "build/Island Menu.app"
./scripts/install.sh                # 构建并安装到 /Applications（风扇控制需要从这里运行）
./scripts/package.sh                # 生成 build/IslandMenu-<version>.zip
```

钥匙串里有 Developer ID Application 证书时，`bundle.sh` 会用它签名，否则用临时签名。`package.sh` 在找到名为 `islandmenu-notary` 的 notarytool 钥匙串凭据时会提交公证并装订票据；没有公证的包首次打开会被 Gatekeeper 拦截，需要在「系统设置 → 隐私与安全性」里放行。

风扇控制组件只接受由同一开发者团队签名的 Island Menu 的连接。用自己的证书构建时，需要把 `Sources/IslandShared/FanHelperProtocol.swift` 里的 `teamIdentifier` 改成你的团队 ID。

## 隐私

- 「音跃」模式会读取系统正在播放的声音的响度，需要「系统音频录制」权限；只计算响度，不录制、不保存。
- 公共 IP 通过 `api.ipify.org` 查询，只在卡片展开时触发，最多每 10 分钟一次。
- 活跃时长和储存用量历史保存在本机 `~/Library/Application Support/IslandMenu/history.json`，不上传。

## 目录

- `Sources/IslandMenu/` — App 源码
- `mockup/` — 网页设计稿（数据为模拟）
- `docs/3d-model-brief.md`、`docs/3d-model-brief-lineup.md` — 3D 机模制作说明（现有机型、刘海机型全系）
- `docs/images/` — 本页的截图，由 `scripts/screenshots.sh` 生成
- `assets/icon/` — App 图标，由 `scripts/make_icns.sh` 生成
- `assets/model/` — 3D 机模（Blender 源文件与导出的 USDZ / GLB）

## 许可

源码公开，仅限非商业使用，见 [LICENSE.md](LICENSE.md)（PolyForm Noncommercial 1.0.0）。可以自行构建、修改和自用，不可用于商业目的。

## 致谢

实现时参考了这些 MIT 许可的项目：
[logoctl](https://github.com/XZCendence/logoctl)、
[LogoLight](https://github.com/Ark0N/LogoLight)、
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)、
[stats](https://github.com/exelban/stats)、
[macmon](https://github.com/vladkens/macmon)。
