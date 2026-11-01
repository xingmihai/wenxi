# Liquid Glass 接入说明

## 为什么没有新增第四种玻璃样式

项目已有完整的外观体系：`GlassStyle`（通透 / 磨砂 / 实色）+ `AppAppearance` ThemeExtension + `navigation_glass.frag` 折射着色器。

设计上本可以新增 `GlassStyle.liquid`，但 `appearance_page.dart`、`app_theme.dart` 里存在对 `GlassStyle` 的**穷尽 switch**——新增枚举值会让这些 switch 变成非穷尽，直接导致 `flutter analyze` 失败。仓库是 fork，GitHub 代码搜索不索引 fork，无法枚举全部分支位置，因此本次**选择纯新增**，不改动任何现有文件，现有 CI 不受影响。

如果后续要把它做成设置里的第四项，需要同步改这几处（已确认）：

- `lib/domain/appearance.dart` — 新增 `GlassStyle.liquid` 枚举值
- `lib/ui/app_theme.dart` — `glassOpacity` 与 `blurSigma` 两个 switch 各补一个分支
- `lib/ui/appearance_page.dart` — 图标 switch 补一个分支
- 其余可能遗漏的 switch 需要本地 `flutter analyze` 全量验证

## 新增文件

| 文件 | 作用 |
| --- | --- |
| `lib/ui/liquid_glass.dart` | 玻璃容器 / 卡片 / 按钮 / 分隔线 |
| `test/liquid_glass_test.dart` | 渲染与交互的单元测试 |
| `.github/workflows/prerelease.yml` | 社区构建的自动预发行流程 |
| `docs/LIQUID-GLASS.md` | 本文档 |

## 用法

组件**复用现有外观配置**，不引入第二套设置。所有数值都从 `AppAppearance.of(context)` 读取，因此设置页里的配色、`GlassStyle`、模糊、透明度照常生效。

在此基础上追加了 Liquid Glass 的渲染语言：

- **连续曲率圆角**：`RoundedSuperellipseBorder`，比普通圆弧更贴合内容
- **折射渐变**：顶部亮边 → 中段透出 `lensColor` 的一丝主色 → 底部反光
- **高光描边**：1px 亮线，让边界在深色背景下依然可辨
- **双层投影**：紧贴的环境光 + 偏下的直接光

```dart
// 容器
LiquidGlass(
  radius: 22,
  padding: const EdgeInsets.all(16),
  child: content,
)

// 卡片
LiquidGlassCard(child: content)

// 按钮
LiquidGlassButton(
  onPressed: () {},
  child: const Text('开始解析'),
)
```

### 渲染顺序

玻璃靠采样**下方**内容产生模糊，顺序必须是「背景层 → 内容层 → 玻璃层」。放在空白父容器里不会有任何效果。

### 性能

每个玻璃块都是一次离屏合成：

- 列表项用 `shadow: false`
- 一屏玻璃块控制在 6 个以内
- 低端机可用 `usesLiquidGlass(context)` 判断，实色样式下退回普通填充卡片

### 参数覆盖

| 参数 | 对应设置项 |
| --- | --- |
| `opacity` | 卡片透明度 |
| `blurSigma` | 模糊 |
| `AppAppearance.palette` | 五套配色 |
| `GlassStyle` | 三种玻璃效果 |

## 预发行构建

`.github/workflows/prerelease.yml`：

- 推送 `v*-*` 标签（如 `v1.8.0-beta.1`）自动触发，也可手动触发
- 使用 `config/build.community.json`，**不依赖官方 applicationId / 控制 URL / 友盟 key**
- Android 出未签名 APK，Windows 出便携 zip
- 自动创建 GitHub 预发行版本并上传产物

与 `release.yml` 完全独立：后者要求官方密钥与签名，本流程任何 fork 都能跑通。

```bash
git tag v1.8.0-beta.1
git push origin v1.8.0-beta.1
```

Windows 产物是便携 zip，不含 Inno Setup 安装包；需要安装包走 `release.yml`。

## 关于 Glasmio

Glasmio 是 Jetpack Compose（原生 Kotlin）的 iOS 27 Liquid Glass 复刻，本项目是 Flutter，两者渲染栈不同，无法直接引用。本文的组件是对同一套视觉语言的 Flutter 侧等效实现。
