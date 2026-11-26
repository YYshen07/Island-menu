# Island Menu

常驻后台的 macOS 性能监控。点击 MacBook Pro（PROLED 机型）的灵动岛，会从药丸位置展开一张卡片，显示 CPU、内存、GPU、储存、电池、网络、进程和温度。

项目处于早期开发阶段，目前只在 14 寸 M5 Pro（Mac17,13）上跑过。

## 现状

已有：

- 灵动岛点击展开 / 收起（授予「辅助功能」权限后，点击不再触发系统原生灵动岛）
- CPU 每核占用、内存、储存、GPU 占用与显存、电池、网络速率与接口、公共 IP、进程排行
- 芯片、SSD、电池温度，风扇转速
- 3D 机模：顶盖一面是发光 logo，转到底面能看到按温度变色的部件和转动的风扇
- 顶盖 logo 灯：自动 / 呼吸 / 音跃（随系统声音律动）
- 充电上限：自动 / 养护 / 满充，使用 macOS 自带的充电上限
- 拖动文件时在灵动岛下方出现隔空投送投放区
- 设置窗口（菜单栏图标或卡片右上角的齿轮）
- 每日活跃时长记录与热力图

还没有：

- 风扇控制（设置里的曲线目前只保存，不生效）
- GPU 帧率与频率、网络延迟

采集只在卡片展开时运行；收起后只剩每分钟一次的活跃时长记录。

## 构建

需要 macOS 15 或更新版本，以及 Xcode 16 或更新版本的工具链（Swift 6）。

```sh
./scripts/bundle.sh                 # 生成 build/Island Menu.app
open "build/Island Menu.app"
./scripts/package.sh                # 生成 build/IslandMenu-<version>.zip
```

钥匙串里有 Developer ID Application 证书时，`bundle.sh` 会用它签名，否则用临时签名。`package.sh` 在找到名为 `islandmenu-notary` 的 notarytool 钥匙串凭据时会提交公证并装订票据；没有公证的包首次打开会被 Gatekeeper 拦截，需要在「系统设置 → 隐私与安全性」里放行。

## 隐私

- 「音跃」模式会读取系统正在播放的声音的响度，需要「系统音频录制」权限；只计算响度，不录制、不保存。
- 公共 IP 通过 `api.ipify.org` 查询，只在卡片展开时触发，最多每 10 分钟一次。
- 活跃时长和储存用量历史保存在本机 `~/Library/Application Support/IslandMenu/history.json`，不上传。

## 目录

- `Sources/IslandMenu/` — App 源码
- `mockup/` — 网页设计稿（数据为模拟）
- `docs/3d-model-brief.md` — 3D 机模制作说明
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
