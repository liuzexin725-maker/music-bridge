# 来源与外部依赖

本仓库公开 Music Bridge 的 Swift / AppKit 界面、iPod 文件导入逻辑、构建脚本和图标素材，采用根目录的 MIT 许可证。

## 下载器与服务

- [zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)：应用通过独立的 `amdl` 可执行文件调用下载器。本仓库不包含该下载器的源码、二进制、配置、媒体测试文件或运行数据，其原项目许可不受本仓库 MIT 许可证覆盖。请遵循原项目的使用说明和许可要求。原项目 README 注明原始脚本作者为 Sorrow，后续修改来自该项目的贡献者。
- [WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper/tree/lite)：外部 wrapper-lite 服务，由使用者独立配置和登录。本仓库不包含其源码、二进制或认证数据。
- [GoMusic](https://sss.unmeta.cn/)：网易云歌单解析使用其第三方接口。提交网易云歌单时会向 `https://sss.unmeta.cn/songlist` 发送歌单链接。服务可能发生变更或不可用。
- [Apple Music](https://music.apple.com/)：歌曲搜索和匹配访问其公开网页及目录接口，当前使用中国区目录；下载能力由独立安装的外部工具提供。
- [TuneMyMusic](https://www.tunemymusic.com/)：迁移辅助窗口提供外部网页入口，由使用者自行决定是否访问和操作。

## 构建与素材

- Swift、AppKit、Foundation、macOS `iconutil`：来自 Apple 的开发工具及系统框架，遵循各自的许可。
- [ImageMagick](https://imagemagick.org/)：生成各尺寸的 `.icns` 图标；不随仓库重新分发。
- [sharp](https://sharp.pixelplumbing.com/)：仅在修改图标后重新导出 PNG 时使用，不是运行应用或常规构建的依赖；不随仓库重新分发。
- IPC3 机身图标为生成式图像配合 SVG 布局制作的项目素材，不是 Apple 提供的官方图标。Apple、iPod、Apple Music 等名称和产品外观属于各自权利人，本项目与 Apple 无关联，未获得其背书；本仓库许可证不授予第三方商标或产品外观权利。

本项目不分发音乐、歌词、专辑封面、账号凭据、Cookie 或订阅访问权。请仅处理你有权访问的内容，并遵守相关服务条款。
