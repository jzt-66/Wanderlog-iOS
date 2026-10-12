# 独立项目交接

2026-10-10，按用户要求将 `travel/mobile/native-ios` 的完整 SwiftUI 工程移至独立目录 `/Users/jiangzhongtian/Wanderlog-iOS`。移动前后 47 个源码、工程、资源与工具文件逐个 SHA-256 核对一致，然后调整本项目文档与测试构建路径。

当前目录包含 App、Core、Resources（字体及许可证、地图数据及来源、应用图标）、Tests、UITests、Xcode 工程、Swift Package、Info.plist、原签名配置与 scripts。没有依赖旧仓库的相对路径或符号链接，没有第三方 Swift 包。

旧项目保留网页、Android、旧 React Native / 混合实现及暂停功能历史。旧项目不再提供 iPhone 编译或安装 npm 命令，不保留另一份 SwiftUI 源码。本项目只通过手机上的兼容导入读取历史旅程，而不依赖旧电脑项目。

原生 App 继续使用 `com.wanderlog.travel` 与团队 `UD4B2Y45PP`，因此手机更新仍原位覆盖，旅程和照片不另起存储容器。迁移后的旧构建缓存仅为本机历史产物，已被 Git 忽略；后续安装脚本始终重新测试并使用新构建目录。
