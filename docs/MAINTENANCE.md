# Island Menu 维护手册

写给以后要升级或排查问题的人（包括我自己和 AI 助手）。README 讲的是"它能做什么"，这里讲的是"它是怎么做的、怎么改、坏了去哪看"。
日常开发的命令和约定在仓库根目录的 `AGENTS.md`，两份互补：`AGENTS.md` 是速查，这里是背景和流程。

状态：1.0.0 于 2026-11-27 发布。只在 14 寸 M5 Pro（Mac17,13，macOS 27.3）上实际运行过。

## 1. 整体结构

三个可执行文件，装在同一个 App 包里：

| 组件 | 构建方式 | 作用 |
|---|---|---|
| `IslandMenu`（主程序） | SwiftPM | 面板、采样、设置、所有控制逻辑。菜单栏应用，不显示在程序坞 |
| `IslandMenuHelper` | SwiftPM | 以 root 运行的后台组件，只负责往 SMC 写风扇转速 |
| `IslandMenuWidgets.appex` | XcodeGen + xcodebuild | 灵动岛提醒（实时活动）的界面。SwiftPM 做不出应用扩展，所以单独构建 |

`Sources/IslandShared/` 是三者共用的代码：SMC 读写、风扇组件的 XPC 协议、实时活动的数据结构。

### 源码目录

| 目录 | 内容 |
|---|---|
| `App/` | 入口、菜单栏图标、信号和 URL 处理、离屏渲染调试入口 |
| `Island/` | 盖在灵动岛 / 刘海上的面板窗口、开合、几何、点击拦截、提醒 |
| `Metrics/` | 每个子系统一个采样器，`MetricsEngine` 负责调度 |
| `UI/` | 面板的 SwiftUI 界面、3D 机模 |
| `Control/` | 会改变系统状态的东西：风扇、充电上限、logo 灯、防休眠、音频电平 |
| `Settings/` | 偏好设置存储和设置窗口 |
| `Stickers/` | 抠图、贴纸效果、贴纸存储 |
| `Drop/` | 隔空投送投放区 |

### 一次展开面板发生了什么

1. 点击被 `IslandController` 的事件监听捕获（不是 SwiftUI 手势，因为收起时窗口是全透明的）。
2. `setOpen(true)`：窗口放大，`state.isMounted = true` 挂载 `CardView`，`MetricsEngine.retainLive()` 启动每秒一次的快速采样。
3. `MachineSection` 创建 `MachineScene`，加载对应机型的 USDZ，贴贴纸。
4. 收起：动画结束后卸载 `CardView`、停止快速采样、释放模型，并调用 `malloc_zone_pressure_relief` 把内存还给系统。

收起状态下只剩三件事在跑：提醒检测（每 5 秒）、风扇控制循环（策略 / 最大模式下每 3 秒）、活跃时长记录（每 60 秒）。

## 2. 各功能的实现要点

改某个功能前先看这一节，里面是踩过的坑。

### 灵动岛与刘海

- `IslandStyle` 两种版式。系统的屏幕接口对药丸和刘海报告的是同样的数据，所以**用有没有 logo 灯来区分**（只有 PROLED 机型有）。
- 灵动岛的实际宽度没有接口可查，药丸尺寸是"摄像头开孔宽度 + 两侧各 30 pt"估出来的，数值是在 Mac17,13 上量的。
- **系统灵动岛画在所有窗口之上**，我们的面板盖不住它。所以灵动岛版式下面板上移并留黑边；刘海版式下面板直接贴顶。
- 点击拦截（`IslandClickTap`）用事件监听拦截灵动岛区域的点击，不让系统卡片弹出，需要辅助功能权限。

### 提醒（实时活动）

- macOS 27.3 才对 Mac 开放 ActivityKit，需要 27.3 的 SDK。所有相关代码都在 `#available(macOS 27.3, *)` 后面。
- **系统只允许最前台的应用发起实时活动**，所以 `AlertMonitor` 发起前会短暂把自己切到前台再切回去。
- 实时活动最长 8 小时，持续的提醒会在 7.5 小时处重新发起。
- 系统会让旧的小组件进程一直活着。更新应用后旧进程解不开新的数据结构，系统会立刻丢掉提醒。`install.sh` 会杀掉它；**改了 `MonitorActivityAttributes.ContentState` 之后务必重装测试**。

### 3D 机模

- 五个 USDZ 在 `assets/model/`，Blender 源文件同目录。模型由 Codex 通过 Blender 制作，制作说明是 `docs/3d-model-brief.md` 和 `docs/3d-model-brief-lineup.md`。
- **`MachineScene` 按节点名查找部件**，名字不能改。不同机型节点不同（Air 没有 `Fan_*` 和 `Heatpipe`；刘海 Pro 用 `Die_Eff` 代替 `Die_Super`），查找都要按可选处理。
- **按需渲染**：平时不出帧，只在翻面 / 开合动画、风扇转动、logo 闪烁时渲染。两件事会让它悄悄变回持续渲染：场景里挂着粒子系统（哪怕发射率为 0）；每次采样都写材质属性（哪怕值没变）。
- SceneKit 在自己的渲染线程上调用代理方法，不在主线程。渲染线程要用的状态都放在 `Motion` 里，用锁保护。
- 热力图是贴在底壳内侧的一张平面贴图（`HeatMapLayer`），色标范围在 `HeatRamp`。
- 屏幕图片和贴纸都是叠在模型上的平面，因为模型的网格没有贴图坐标。
- 模型验收：`/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 -P tools/check_island_model.py`

### 贴纸

- 抠图用 VisionKit 的主体提取（`ImageAnalysisOverlayView`），和「照片」里长按抠图是同一个。**它需要一个运行中的应用**，命令行路径（`--render-model --sticker`）退回到 Vision 框架。
- 系统抠图会把它认为是背景的文字去掉，这个控制不了。
- 存储：抠好的原图存在 `~/Library/Application Support/IslandMenu/stickers/<UUID>.png`，位置和效果存在偏好设置的 `stickers` 键里。效果是显示时再套上去的，所以换效果不需要原图。
- 苹果没有开放「信息」里的贴纸效果，十种效果都是用 Core Image 自己做的。

### 风扇控制

- 写 SMC 需要 root。后台组件用 `SMAppService.daemon` 注册，用户在「登录项与扩展」里批准。**应用必须在 `/Applications` 下**，组件才有稳定路径。
- 本机的 SMC 键：`FNum` 风扇数；`F{n}Ac` 当前转速、`F{n}Mn` / `F{n}Mx` 最小最大、`F{n}Tg` 目标转速，都是 `flt` 类型；模式键是小写的 `F{n}md`（`ui8`，1 为手动，0 为自动）。
- 安全设计：组件只接受同一团队签名的 Island Menu 连接；转速被钳在最小和最大之间；非有限数值直接拒绝；应用超过 15 秒没有续命，组件自动把风扇交还系统；芯片到 95 °C 强制全速。
- **用别的证书构建时**要改 `FanHelperProtocol.swift` 里的 `teamIdentifier`。
- 替换应用不会重启已经在跑的组件进程，要重启电脑或重新注册。改了 XPC 协议要同时提高 `FanHelper.version`。

### 充电上限

- 用的是 macOS 自带的充电上限（私有类 `PowerUISmartChargeClient`，`setMCLLimit:error:`），不需要 root。只支持 80 / 85 / 90 / 95 / 100。
- AlDente 那一类工具用的旧 SMC 充电键（`CH0B`、`CH0C`、`CHTE`）在这台机器上不存在。

### logo 灯

- 私有框架 CoreBrightness，参考了 logoctl 和 LogoLight。
- **不要逐帧写亮度**：每秒写 30 次会让系统的亮度服务占到约 12% CPU。呼吸和音跃都是让硬件自己渐变（`LEPWMFactorFadeDuration`），每次只发起止两条指令。
- 副作用：变暗时键盘背光可能跟着闪一下，系统把两者绑在同一个状态上，代码里变暗后会立刻恢复键盘。
- 音跃用 Core Audio 进程 tap 读系统声音的响度，需要「系统音频录制」权限。

### 壁纸

- `NSWorkspace.desktopImageURL` 在用户设置了航拍动态壁纸时只返回系统默认图片。`Wallpaper.swift` 改为直接读壁纸服务的记录 `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`。
- 已覆盖：航拍壁纸（取视频第一帧）、普通图片。未覆盖：随时间变化的动态壁纸、纯色、按显示器或桌面空间单独设置的壁纸，这些会退回旧接口。
- 这个文件的格式不是公开接口，**系统升级后最可能坏的就是这里**。

### 温度

- 私有的 IOHID 事件接口。本机有效的传感器：`PMU tdie1`–`14`（芯片）、`NAND CH0 temp`、`gas gauge battery`。`PMU tdev1`–`8` 返回约 −9200，是无效值，已过滤。
- 读一个传感器要 0.5 毫秒以上，而且系统把同一个传感器重复列两三遍，所以做了去重。后台循环用 `dieMax()`：每十次全读一次，其余只读最热的三个。
- 14 个芯片传感器和核心簇的对应关系查不到，所以机模上三块芯片区域用的是同一个平均温度。

### 电池功率

- 来自电池注册表项的 `PowerTelemetryData`（`SystemPowerIn`、`SystemLoad`，单位毫瓦）。系统几十秒才更新一次，不是实时的。

## 3. 本机数据存在哪

| 内容 | 位置 |
|---|---|
| 偏好设置 | `defaults read dev.yan.islandmenu` |
| 活跃时长和储存用量历史 | `~/Library/Application Support/IslandMenu/history.json` |
| 贴纸图片 | `~/Library/Application Support/IslandMenu/stickers/` |
| 自定义屏幕图片 | `~/Library/Application Support/IslandMenu/screen-image` |

偏好设置的键：`fanMode`、`fanCurve`、`chargeLimit`、`logoMode`、`colorful`、`islandStyle`、`machineModel`（隐藏项，预览其他机型用）、`machineFinish`、`screenContent`、`showPublicIP`、`awakeBrightness`、`alertRules`、`stickers`。

## 4. 调试

### 这台机器平时有人在用

- **不要发模拟点击或按键**，会落到前台的其他应用里。
- 用脚本驱动面板：
  - 开合：`pkill -USR1 -x IslandMenu`
  - 启动参数 `--open`（启动即展开）、`--pin`（点外面不收起）、`--settings`、`--settings-tab <general|machine|stickers|alerts|fan|battery>`
  - `open -g -a "<App 路径>" islandmenu://flip`（还有 `lid`、`top`、`bottom`）。**一定要带 `-a`**，否则系统可能启动另一份拷贝。
- 模拟其他硬件：`--notch`、`--island`、`--no-fans`、`--no-logo`；预览其他机型：`defaults write dev.yan.islandmenu machineModel macbook-air-15`。
- 只截面板自己的窗口，别把屏幕上其他内容截进去：`scripts/screenshots.sh <输出目录> [--notch]`。**网络栏会显示公共 IP 和 Tailscale 地址，公开前要裁掉。**

### 不启动界面看机模

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift build
.build/debug/IslandMenu --render-model assets/model/macbook-pro-14.usdz /tmp/out.png 0      # 顶盖面
.build/debug/IslandMenu --render-model assets/model/macbook-pro-14.usdz /tmp/out.png 0.5    # 底面
.build/debug/IslandMenu --render-model assets/model/macbook-air-15.usdz /tmp/out.png --finish skyBlue --lid-open
.build/debug/IslandMenu --render-model <usdz> /tmp/out.png --screen wallpaper --lid-open
.build/debug/IslandMenu --render-model <usdz> /tmp/out.png --no-logo --glint 0.5 0          # 镜面 logo 的高光
.build/debug/IslandMenu --render-model <usdz> /tmp/out.png --sticker <图片> 0               # 十种贴纸效果
```

### 常见问题去哪看

| 现象 | 先查什么 |
|---|---|
| 提醒不出现 | `log stream --predicate 'process == "liveactivitiesd"'`，看有没有 "Requester is not foreground"；确认小组件旧进程已杀；系统设置里实时活动是否开启 |
| 测试提醒 | 把阈值调低：`defaults write dev.yan.islandmenu alertRules -data $(printf '{"cpu":{"enabled":true,"limit":3}}' \| xxd -p \| tr -d '\n')`，重启应用等约 20 秒，测完 `defaults delete dev.yan.islandmenu alertRules` |
| 风扇栏显示"安装组件" | 应用是否从 `/Applications` 运行；「登录项与扩展」里是否批准；`pgrep -lf IslandMenuHelper` |
| 风扇不听指挥 | `log show --last 5m --predicate 'process == "IslandMenuHelper"'`；签名的团队 ID 是否和 `teamIdentifier` 一致 |
| logo 灯没反应 | `refs/logoctl/.build/release/logoctl status --json` 看实际输出 |
| 充电上限设不上 | 面板电池栏会显示系统返回的错误；`ChargeLimiter.isSupported` |
| 开盖屏幕壁纸不对 | `plutil -p ~/Library/Application\ Support/com.apple.wallpaper/Store/Index.plist` 看 `Provider` 是什么 |
| 机模某个部件不动 / 不变色 | 节点名是否和模型里的一致（`check_island_model.py`） |
| 收起后 CPU 偏高 | `sample <pid> 10`，看 `dev.yan.islandmenu.fans` 和 `.alerts` 两个队列各占多少 |
| 收起后内存偏高 | `footprint <pid>`；`heap <pid>` 看是不是面板没有卸载 |
| 崩溃 | `~/Library/Logs/DiagnosticReports/` 里找 IslandMenu |

### 测性能

- 用 CPU 时间差，不要看单次 `top`：`ps -o cputime= -p $(pgrep -x IslandMenu)`，隔 60 秒再读一次。
- **测量时使用者随时可能点开面板，任何一次点击外部也会把面板关掉**。收起状态的数字要确认窗口高度一直是 39；展开状态用 `--open --pin` 重新启动再测。
- 1.0.0 的基准（风扇策略模式开启）：收起约 0.2% CPU，刚启动 20 MB，展开过再收起约 60 MB；展开约 3–6%，约 180 MB。

## 5. 构建与发布

### 环境

- Xcode 27.3（测试版期间在 `/Applications/Xcode-beta.app`，脚本通过 `DEVELOPER_DIR` 选择它）。27.2 的 SDK 里 ActivityKit 标着 macOS 不可用，编不过。
- XcodeGen（`brew install xcodegen`）。
- 钥匙串里的 `Developer ID Application: Yan Yu (8GSUX2RHW8)` 证书。
- notarytool 的钥匙串凭据，名为 `islandmenu-notary`。重建方法：
  `xcrun notarytool store-credentials "islandmenu-notary" --apple-id <Apple ID> --team-id 8GSUX2RHW8`，
  密码填 **App 专用密码**（account.apple.com →「登录与安全」→「App 专用密码」），不是 Apple ID 登录密码。

### 脚本

| 脚本 | 作用 |
|---|---|
| `scripts/bundle.sh` | 构建并生成 `build/Island Menu.app`，有证书就签名 |
| `scripts/install.sh` | 构建并装到 `/Applications`，重启应用 |
| `scripts/package.sh` | 构建、打包、公证、装订，生成 `build/IslandMenu-<版本>.zip` |
| `scripts/make_icns.sh` | 由 `make_icon.swift` 重新生成应用图标 |
| `scripts/screenshots.sh` | 截 README 用的图 |

### 发版步骤

1. 改版本号：`Resources/Info.plist` 和 `Widgets/Info.plist` 里的 `CFBundleShortVersionString`，两处要一致；`CFBundleVersion` 递增。
2. `swift build` 通过，五个模型各离屏渲染一张确认没坏。
3. 更新 README（功能、资源占用数字），需要的话重截图。
4. 提交并推送。
5. `./scripts/package.sh`。时间戳服务偶尔不可用（"The timestamp service is not available"），等几十秒重试即可。
6. 验证安装包（见下）。
7. `git tag -a vX.Y.Z -m "Island Menu X.Y.Z"` 并推送标签。
8. `gh release create vX.Y.Z build/IslandMenu-X.Y.Z.zip --draft --title "Island Menu X.Y.Z" --notes-file <说明>`。
9. 把草稿里的安装包下载回来再验证一遍，确认 SHA-256 一致，然后 `gh release edit vX.Y.Z --draft=false --latest`。

### 验证安装包

```sh
T=$(mktemp -d) && cp build/IslandMenu-X.Y.Z.zip $T && cd $T
xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;$(uuidgen)" IslandMenu-X.Y.Z.zip
ditto -x -k IslandMenu-X.Y.Z.zip .
xattr -r -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;$(uuidgen)" "Island Menu.app"
spctl -a -vv -t exec "Island Menu.app"            # 应为 accepted / Notarized Developer ID
xcrun stapler validate "Island Menu.app"
codesign --verify --deep --strict "Island Menu.app"
syspolicy_check distribution "Island Menu.app"
```

首次启动测试：先 `defaults export dev.yan.islandmenu /tmp/backup.plist` 备份，`defaults delete dev.yan.islandmenu` 清空，启动测试，再 `defaults import dev.yan.islandmenu /tmp/backup.plist` 恢复。

自动化验证不了、需要人来做的两步：首次打开时"来自互联网"的确认框；新用户批准风扇后台组件的流程。

## 6. 仓库与隐私

- 仓库公开，许可是 PolyForm Noncommercial 1.0.0。
- **提交邮箱**用 GitHub 的匿名邮箱 `128406953+YYshen07@users.noreply.github.com`。1.0.0 发布前重写过一次历史，把真实邮箱、第三方拆机照片和带本机路径的渲染日志清掉了。
- 提交时**按路径逐个 `git add`**，不要 `git add -A`：`assets/` 和 `tools/` 里会有其他工具中途生成的文件。
- 不进仓库的东西（已在 `.gitignore`）：`assets/reference/`（拆机参考照片，第三方版权）、`refs/`（参考项目的克隆）、`tools/`（除验收脚本外）、`.blend1`、渲染日志、`build/`。
- 截图公开前检查：网络栏（IP）、进程列表、壁纸、贴纸内容。
- 参考并致谢的 MIT 项目：logoctl、LogoLight、DynamicNotchKit、stats、macmon。SMC 的读写实现来自 stats。

## 7. 已知限制和没验证过的东西

发布时如实写在 README 里了，这里是完整清单。

**没有在真机上跑过：**

- 刘海机型（版式是在灵动岛机器上画了个替身刘海模拟的）。刘海区域的点击能否收到没有确认。
- macOS 27.0–27.2（只确认了能编译，ActivityKit 是弱链接）。
- 无风扇的 MacBook Air、没有 logo 灯的机型（用 `--no-fans`、`--no-logo` 模拟过界面）。
- 另外四款机模的自动选型（按有无风扇和屏幕对角线判断，只走过 PROLED 这一条分支）。
- 外接显示器为主屏、合盖使用的情况。

**功能上的限制：**

- 灵动岛机型上，没给辅助功能权限时点击灵动岛会同时弹出系统卡片。
- 系统灵动岛永远画在面板上面，面板盖不住它。
- 提醒出现的瞬间应用会抢一下焦点，正在打字可能丢一两个按键。
- 充电上限只有 80 / 85 / 90 / 95 四档。
- 电池功率读数几十秒才更新一次；没有 SoC、显示屏等分项功耗。
- 贴纸效果是仿的，不是系统的；不支持动态贴纸；读不到「信息」里已有的贴纸。
- 没有 GPU 帧率与频率、网络延迟（已决定不做）。
- 没有自动更新。
- 没有测试和 lint。

**实现上可能随系统升级失效的地方（都是私有接口）：**

| 功能 | 依赖 |
|---|---|
| 提醒 | macOS 27.3 测试版的 ActivityKit，正式版接口可能有变 |
| 风扇 | SMC 键名和类型 |
| 充电上限 | `PowerUISmartChargeClient` |
| logo 灯 | CoreBrightness 的键 |
| 温度 | IOHID 事件接口和传感器名称 |
| 防休眠调亮度 | `DisplayServices` |
| 壁纸 | 壁纸服务的 `Index.plist` 格式 |
| 灵动岛几何 | 摄像头开孔 + 固定边距的估算 |

系统大版本升级后，按这张表逐项过一遍。

## 8. 以后可以做的

没有承诺，按价值大致排序：

1. 在真正的刘海机型和 Air 上跑一遍，修掉暴露出来的问题。
2. 自动更新（Sparkle），或者至少在菜单里提示有新版本。
3. 展开状态的开销：每秒整张面板重新求值。可以让各栏目只在自己的数据变化时更新。
4. 把 3D 渲染放进随面板关闭而退出的独立进程，让收起后的内存回到 20 MB。
5. 电池功率的分项（SoC、显示屏），需要接 IOReport。
6. 机模上三块芯片区域用各自的温度，需要先搞清传感器和核心簇的对应关系。
7. 贴纸：动态贴纸、更接近系统的"立体""闪亮"效果。
8. 壁纸：覆盖随时间变化的动态壁纸和分显示器设置。
9. 英文界面。
10. 单元测试（采样器的解析、风扇曲线插值、提醒的迟滞逻辑都适合）。
