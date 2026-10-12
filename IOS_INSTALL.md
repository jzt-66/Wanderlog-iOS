# Wanderlog · 独立 iPhone 安装

唯一原生开发入口为本项目根目录 `Wanderlog.xcodeproj`。源码、资源、测试与安装脚本全部随本项目保存；无需旧 `travel` 项目、Node、npm、Expo、CocoaPods 或开发服务器。

## 固定身份与数据

- 实体 iPhone 17 Pro：`00008150-00180C3A0A40401C`。
- 应用标识：`com.wanderlog.travel`；原签名团队：`UD4B2Y45PP`。
- 当前版本：`1.0.0`，构建 `4`。目录拆分不修改手机应用标识或签名账户。
- 同标识原位覆盖，先备份旅程元数据，再确认版本与原照片元数据；不卸载、不清空、不自动发布。
- 原生存储及旧记录兼容导入说明见 [README.md](README.md)。原生记录已有时直接读取，旧文件保持原样。

## 更新流程

连接并解锁指定设备后运行：

```bash
cd /Users/jiangzhongtian/Wanderlog-iOS
bash scripts/install-iphone.sh
```

脚本核对指定实体设备，运行原生规则 / 数据测试，再用全新目录编译真机 Release 包，验证应用标识与原团队签名。安装前只备份旧或当前旅程 JSON 元数据，不复制私人照片内容。随后覆盖安装、核对手机版本和原照片路径 / 大小 / 修改时间，再尝试正常启动。

脚本显示的私有临时目录保存签名、编译、安装、版本和元数据备份证据。设备不可用时停止；锁屏可能允许安装而阻止启动，需要在手机解锁后正常打开。安装、启动与实际界面体验分别报告。签名或系统安全限制不可绕过，模拟器与真机编译不并行。

## 最近已验证记录

2026-10-10，完整 SwiftUI 版本通过 27 项原生测试、4 项隔离原生界面流程和 97 项原项目网页回归。真机 Release 编译与签名校验通过；已同标识原位覆盖指定 iPhone，设备侧确认 `1.0.0` / 构建 `2`，正常启动重试成功。3 条旧旅程的规范 JSON、原始导入备份与覆盖前数据逐字节一致；启动后 11 个原照片文件的路径、大小与修改时间全部一致。证据：`/tmp/wanderlog-native-install.w6efOe`。这记录的是拆分前的已安装原生版本；独立项目拆分后的验证结果追加在此处。

旧 React Native / 混合版本的安装历史只保留在原 `travel/mobile/IOS_INSTALL.md`，不属于本项目当前安装流程。

2026-10-10 独立项目拆分验证：原生工程已移至 `/Users/jiangzhongtian/Wanderlog-iOS`，其余 45 个应用源码、资源、配置与测试文件逐字节保持一致，README 和安装测试缓存路径按独立项目调整。27 项原生测试从全新 scratch 目录通过；独立目录 `build-device-20261010-independent` 完成真机 Release 编译，签名、原应用标识、原团队及内置字体 / 地图资源核对通过，仅链接 Apple / Swift 系统库，版本仍为 `1.0.0` / 构建 `2`。指定 iPhone 在安装前及编译后复查均不可用，因此此次未再次覆盖或启动；手机保留上一条已验证的 SwiftUI 安装与数据。验证日志为 `/tmp/wanderlog-ios-extraction-tests.log`、`/tmp/wanderlog-ios-extraction-build.log`，未安装检查为 `/tmp/wanderlog-native-install.GqtGDT`。


2026-10-10 交互修正（构建 `3`）：详情记录打开来源并原页返回，主动定位才切换地图；照片支持原倍率下拉关闭，放大后仍正常拖动；卡片、照片、地图标签及普通按钮加入按压反馈；个人旅程可编辑地点、标题、回忆、日期与照片，保留未修改照片、旧月份精度和历史元数据；删除提供 8 秒撤销，后台暂停计时，重启恢复待撤销状态；年份与城市可连续组合筛选，示例开关不计入筛选红点；表单错误固定显示顶部并提供辅助功能播报；地图进入 / 预览使用不同图标，包含旧城市记录的预览语义。

34 项原生测试和 7 项隔离界面回归通过；另一次照片手势专项回归验证放大后的下拉不会关闭、恢复原倍率后可以关闭。已核对列表与地图截图。全新目录 `/tmp/wanderlog-interaction-device-final` 的真机 Release 编译通过，严格签名校验通过，确认原标识 `com.wanderlog.travel`、原团队 `UD4B2Y45PP` 及 `1.0.0` / 构建 `3`。模拟器与真机编译依次执行，没有并行。

执行 `bash scripts/install-iphone.sh` 时指定实体 iPhone 不可用，脚本在编译 / 备份 / 安装之前停止。本次未覆盖、未启动、未进行真机界面验收；手机现有旅程与照片未改动。设备检查证据为 `/tmp/wanderlog-native-install.Hl6zIJ`。原生测试日志：`/tmp/wanderlog-interaction-tests-final.log`；界面结果：`/tmp/wanderlog-interaction-ui-final.xcresult`；手势专项结果：`/tmp/wanderlog-interaction-zoom-final.xcresult`；Release 日志：`/tmp/wanderlog-interaction-device-final.log`；签名记录：`/tmp/wanderlog-interaction-signature.log`。


2026-10-11 审美与无障碍修正（构建 `4`）：列表封面和详情 hero 按原图比例完整展示；详情改为按较短列排列的两列瀑布流，横图、竖图和方图均不裁切；地图及表单缩略图使用完整适配。倾斜只保留在旅程列表，详情和地图预览放正。正文、小字与 caption 使用系统语义字体，随 Dynamic Type 缩放；最大辅助功能字号下地图统计收纳到可展开概览，地图投影和标签按顶部控件实测高度避让。地点分隔统一为中点，空态及编辑／删除操作使用同一胶囊组件；地图空态提供添加首段旅程引导。地点搜索使用分隔行，示例标签独立显示；列表搜索遵循减少动态效果偏好进行展开动画。提示按安全区堆叠，移除固定顶部和撤销提示偏移；保存／照片读取过程显示原因，保存、删除、撤销和地图层级进入提供触觉反馈。Atlas 标签中心距 pin 上限 82pt，密集时保留可点且可被 VoiceOver 读取的 pin，放大后重新排布标签；未添加旅程连线。

最终 36 项原生规则／数据测试通过，整套 10 项隔离界面回归通过；最后地图布局和详情安全区修改后的 5 项相关界面专项复测通过。已核对正常字号、最大辅助功能字号、横竖混合瀑布流、地图空态和层级预览截图。界面测试使用独立验收目录，Release 无法进入该数据路径。最终真机 Release 使用全新目录 `/tmp/wanderlog-aesthetic-device-final-20261011`，编译与严格签名验证通过，确认原应用标识 `com.wanderlog.travel`、原团队 `UD4B2Y45PP`、版本 `1.0.0`／构建 `4`。模拟器和真机编译依次执行。

按约定执行安装脚本并在最终构建后复查，指定实体 iPhone 仍不可用，脚本在备份／编译／覆盖之前停止。本次未覆盖、未启动、未进行真机界面或触觉验收，也未操作手机旅程与照片。最新设备检查证据：`/tmp/wanderlog-native-install.DqTm4V`。原生测试：`/tmp/wanderlog-aesthetic-core-final-20261011.log`；整套界面结果：`/tmp/wanderlog-aesthetic-ui-final-20261011.xcresult`；最终相关专项结果及截图：`/tmp/wanderlog-aesthetic-map-adaptive-20261011.xcresult`、`/tmp/wanderlog-aesthetic-map-adaptive-attachments-20261011`；最终真机编译：`/tmp/wanderlog-aesthetic-device-final-20261011.log`；签名：`/tmp/wanderlog-aesthetic-signature-20261011.log`。


2026-10-11 构建 `4` 真机覆盖：用户确认设备恢复可用后，执行 `bash scripts/install-iphone.sh`，重新核对指定实体 iPhone 17 Pro，36 项原生测试通过，使用全新构建目录完成 Release 编译、严格签名及原标识／原团队校验。安装前备份 3 个旅程元数据文件，再同标识原位覆盖；设备侧已确认 `com.wanderlog.travel`、版本 `1.0.0`／构建 `4`。覆盖前后 3 个旅程元数据文件逐字节一致，11 个原照片文件的路径、大小和修改时间一致。未卸载或清空数据，未发布。

首次启动及正常重试均被系统以 `RequestDenied / Locked` 拒绝，设备当时锁屏；未绕过锁屏限制。安装已成功，启动和真机界面／触觉验收待解锁后完成。安装、版本、签名、元数据备份／比较及启动记录均在 `/tmp/wanderlog-native-install.J9Y89G`。
