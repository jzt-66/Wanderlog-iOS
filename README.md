# Wanderlog · 独立 iPhone 项目

本项目独立位于 `/Users/jiangzhongtian/Wanderlog-iOS`，源码、资源、测试、签名配置和安装工具全部自包含。iPhone / iPad 的正式开发入口为本目录的 `Wanderlog.xcodeproj`，全部界面使用 SwiftUI。世界总览用 SwiftUI Canvas 绘制本地矢量地图；国家与城市详细地图、地点和照片选择使用 Apple 的 MapKit、Core Location 与 PhotosUI。仅照片缩放使用小型 UIKit `UIScrollView`。应用运行时不依赖 React Native、Expo、Metro、CocoaPods 或 JavaScript 包。

## 已迁移的功能

- 国家 → 省份 / 地区 → 城市 → 地点地图分层、缩放切换、面包屑、居中、旅程预览分页和详情定位；只显示标记，没有连线。
- 世界总览支持拖动和缩放，适配实际屏幕宽高及标签避让，跨洲足迹不受 MapKit 的世界缩放上限裁切。矢量数据来自 Natural Earth，来源与许可记录随资源保存；进入国家后使用原生 Apple 详细地图。
- 真实城市 / 国家 / 照片统计、示例显示开关、旅程文字 / 年份 / 城市组合筛选。
- 旅程详情、原照片封面、相纸边缩略图、全屏分页照片、捏合和双击缩放、原始倍率向下滑动关闭。
- 添加旅程、单日 / 日期范围、日期校验、标题 / 手记、最多 8 张照片、系统照片选择、取消后保留草稿。
- Apple 与 Photon 并行搜索、七组地标别名校验、候选去重、900ms 防抖、12 秒搜索超时、取消和重试、20 条 / 2 分钟会话缓存。
- 主动开启 / 关闭附近优先；只取一次大致位置，只对无地区限定的类别查询发送粗化位置。没有后台定位。
- 自定义名称及地图点选，地址查询失败仍可保存；保存成功后再更新界面，失败保留草稿。
- 编辑个人旅程的地点、标题、回忆、日期和照片；未替换的照片直接保留原文件，编辑失败不覆盖原记录。
- 确认删除个人旅程后提供 8 秒撤销提示；撤销期间保留照片副本，进入后台暂停计时，未完成的撤销状态在重启后恢复。超时或再次删除旅程时，只清理应用自己的且未被其他记录引用的照片副本。
- 原生 TabView、sheet、safeAreaBar、系统材质、键盘避让、深色模式与减少动态效果适配。列表的柔和滚动边缘由系统生成；静止地图顶部使用可见的系统材质与渐隐边缘。

标题内置 Noto Serif CJK SC 的宋体风格字体，Georgia 数字保持不变；字体及 SIL OFL 许可证见 `Resources/Fonts`。12 / 14 / 17 / 22 / 30 五档字号、亮色辅助文字对比度、相纸边和轻微倾斜、地图红点与详情缓慢放大均在原生页面实现。

回忆照片本和艺术封面继续暂停，历史元数据和文件保留。不包含生成请求、后台轮询或服务启动操作。

## 数据兼容

应用标识仍为 `com.wanderlog.travel`，签名团队仍为 `UD4B2Y45PP`。覆盖安装不会主动卸载或清空旧数据。

首次启动优先读取新存储；尚无新存储时，只读查找旧 AsyncStorage 的 `wanderlog.custom-trips.v1`。支持 `Application Support/<bundle>/RCTAsyncLocalStorage_V1` 与 Documents 下的历史目录，以及 manifest 内嵌字符串或 MD5 命名的独立文件。

导入前校验全部记录，先保存原始 JSON 备份，然后原子写入新文件。旧 manifest、旧记录文件、原照片、艺术封面文件和密钥均不删除。多份旧数据冲突、文件缺失或 JSON 损坏时停止导入并禁用保存，不把错误解释成空记录。

新存储位置：`Library/Application Support/com.wanderlog.travel/WanderlogNative/trips.json`。同目录的 `legacy-import.json` 是首次导入的原始备份；`trips.previous.json` 是上一次持久化成功的记录快照。未知旧字段继续写回；旧月份保留原始精度。应用复制的照片仍存于 Documents，显示时解析更新后的容器路径。

删除待撤销记录保存在同目录的 `pending-deletion.json`，安装备份也包含该文件。撤销会恢复记录及原照片引用；撤销期结束后才清理照片。记录快照不构成完整照片备份。不要卸载应用。

## 编译与检查

直接用 Xcode 打开 `Wanderlog.xcodeproj`，选择 Wanderlog scheme。部署目标 iOS 17，iOS 26 使用新系统栏与玻璃效果，旧系统使用公开的系统材质回退。无第三方 Swift 包。

```bash
cd /Users/jiangzhongtian/Wanderlog-iOS
swift test
xcodebuild -project Wanderlog.xcodeproj -scheme Wanderlog \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/wanderlog-native-device DEVELOPMENT_TEAM=UD4B2Y45PP build
```

连接并解锁指定 iPhone 后，在本项目根目录执行 `bash scripts/install-iphone.sh`。脚本核对唯一目标设备、运行原生测试、使用新构建目录编译、校验原签名、备份旧记录 JSON、同标识覆盖、核对版本与照片元数据，再尝试启动。没有卸载、清空或发布步骤。备份与证据保存在脚本显示的私有临时目录中。

`Tests` 验证迁移、持久化、照片归属、日期、城市、地图和搜索规则。`UITests` 使用 Debug 专属的隔离数据根目录，验证原生页面流程；Release 不包含测试数据初始化路径。

项目文件随源码保存，无需生成工具。增加文件时可直接在 Xcode 添加；如需重建项目，可使用 `scripts/generate-project.rb`（需要 xcodeproj Ruby gem）。请不要用 Expo prebuild 重建本工程。

安装流程与实际设备证据见本项目的 [IOS_INSTALL.md](IOS_INSTALL.md)。工程构建不读取旧 `travel` 项目；原生源码和资源仅维护这一份。旧网页、Android、暂停功能的历史代码和 React Native 安装历史留在原项目中。两者不会与此 iOS 本地存储自动同步。
