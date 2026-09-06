# Geranium LocSim

这是从 [Geranium](https://github.com/c22dev/Geranium) 1.1.4 精简出的定位模拟版本，只保留 LocSim 和定位收藏。

## 保留的功能

- 轻点地图选择位置，或手动输入经纬度
- 搜索地点或地址，并让地图跳转到搜索结果
- 明确点击“开始模拟”后才启动定位模拟
- 随时点击“结束模拟”恢复真实定位
- 收藏、手动添加、修改和删除常用位置
- 点击收藏位置后，地图会立即跳转并将它载入“已选位置”
- 从 Apple 地图分享位置到 Geranium 收藏
- 中国大陆地图坐标偏移校正

## 已移除

- Cleaner
- Daemon Manager
- ByeTime / Screen Time
- Device Superviser
- 更新检查、遥测、Beta 页面、欢迎页、设置页和备用图标
- RootHelper 与 AlertKit 依赖
- 与定位无关的私有权限

## 安装要求

- 支持 TrollStore 的 iPhone 或 iPad
- iOS / iPadOS 15 或更高版本

普通签名无法获得定位模拟所需的私有权限，因此需要通过 TrollStore 安装。

## 构建

需要 macOS、Xcode 和 ldid。克隆仓库后，在项目根目录运行 ./ipabuild.sh。

生成的安装包位于 build/Geranium.tipa。

### GitHub Actions 在线构建

1. 打开仓库的 Actions 页面，选择 **Build Geranium LocSim**。
2. 点击 **Run workflow** 开始构建；推送到 `main` 分支时也会自动构建。
3. 构建完成后，在该次运行页面的 **Artifacts** 中下载 `Geranium-LocSim-tipa`。
4. 解压下载的压缩包，得到 `Geranium.tipa` 和对应的 SHA-256 校验文件。

工作流使用 GitHub 提供的 macOS 15 runner、Xcode 和 ldid，不需要 Apple 开发者证书。生成的包仅供 TrollStore 安装。

## 致谢

原项目由 [c22dev](https://github.com/c22dev/Geranium) 开发；中国坐标转换由 acg7878 贡献。许可证见 [LICENSE.md](LICENSE.md)。
