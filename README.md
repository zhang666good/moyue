# 墨阅 MoRead

> 墨落于纸，阅见所想。

用 **Flutter 原生实现**的 Markdown 编辑器与阅读器。写的时候像 Typora（所见即所得，
光标落在哪个块哪个块才露出源码），读的时候像语雀（代码块、公式、图表、表格、
提示卡片、图片灯箱一应俱全）。

## 三种视图

工具栏中间的三段开关切换：

| 视图 | 说明 |
| :--- | :--- |
| **编辑** | 块级所见即所得，语法标记以淡灰显示；中文输入法零特殊处理 |
| **阅读** | 无光标，公式／图表／代码块／灯箱全部生效 |
| **源码** | 兜底模式，复杂结构出问题直接改原文 |

## 快捷键

| 按键 | 作用 |
| :--- | :--- |
| `Ctrl+O` / `Ctrl+S` / `Ctrl+Shift+S` / `Ctrl+N` | 打开／保存／另存为／新建 |
| `Ctrl+\` | 展开／收起大纲 |
| `Ctrl+Shift+/` | 在编辑／阅读／源码之间轮换 |

## 开发

```bash
flutter pub get
flutter analyze
flutter test              # 解析不变式 + 渲染 + 交互
flutter run -d windows
flutter build windows --release
```

## 品牌资源

软件名 **墨阅 MoRead**，图标走「墨滴落纸」——靛蓝→紫罗兰渐变圆角方块，
其上落一张白纸（右下折角），纸面中央一滴墨与几行文字线。

图标绘制逻辑只有一份，在 `lib/ui/brand_mark.dart`：应用内标题栏的 Logo
（`BrandMark` 组件）与 exe 图标共用它，改一处两处同时生效。

改完图标后按两步重新出图（一次生成 Windows 与 iOS 两套）：

```bash
flutter test test/icon_gen.dart      # → assets/icon/icon_<size>.png / .rgba
                                     # → ios/Runner/Assets.xcassets/AppIcon.appiconset/
python tool/make_ico.py              # → windows/runner/resources/app_icon.ico
flutter test test/ico_verify.dart    # 回读 .ico，校验通道顺序与行序没画反
```

如果 flutter 工具链不可用（原因见 `tool/make_ios_icons.py` 顶部说明），iOS 那套
可以走离线派生：从上面同一批 PNG 补齐圆角外的背景再按尺寸缩放。
iOS 图标必须**满幅且不带透明通道**，所以走的是 `paintBrandIcon(..., fullBleed: true)`。

```bash
python tool/make_ios_icons.py        # 顺带用真实渲染像素反查背景公式，抄错会直接中止
```

小尺寸会自动降级：≤24px 只留纸张与墨滴；32–48px 两行文字；≥64px 三行文字加高光。
iOS 各档尺寸按同一套档位取母版（20 用 minimal、29/40 用 compact、其余用 full），
保证缩放不跨档串味。

## iOS 打包

iOS 只能在 macOS 上编译，所以走云端：`.github/workflows/ios-unsigned-ipa.yml`
会在 GitHub 的 macOS runner 上产出一个**未签名** `.ipa`，再在 Windows 上用
Sideloadly 配合免费 Apple ID 签名安装。整条链路零成本，代价是签名 7 天后过期。

完整步骤（建仓、触发、下载、签名、过期后怎么处理）见 **[`docs/ios-build.md`](docs/ios-build.md)**。

代码层面的平台差异都收敛在 `lib/io/file_service.dart`：iOS 没有「另存为」对话框，
`file_selector_ios` 也没实现 `getSaveLocation`（调用会抛 `UnimplementedError`），
所以移动端降级为写进 App 沙盒的 Documents 目录，配合 `Info.plist` 里的
`UIFileSharingEnabled`，文件能在「文件」App 的「我的 iPhone → 墨阅 MoRead」里看到。

## 项目结构

```
lib/
  md/        Markdown 解析（无损往返：parse(src).source == src）
  editor/    块级编辑内核、源码视图
  read/      阅读态渲染：代码高亮、公式、表格、提示卡片、Mermaid、图片灯箱
  ui/        调色板、大纲面板、品牌标识（brand_mark.dart 是图标逻辑唯一来源）
  io/        文件读写（桌面／移动端差异都收在这里）
ios/         iOS 工程（部署目标 15.0，bundle id com.moread.moread，走 Swift Package Manager）
windows/     Windows 工程
test/
  widget_test / reading_test / render_test   三类测试（平台无关，CI 里跑这三个）
  icon_gen / ico_verify / visual_check       图标生成校验与真机截图
tool/
  make_ico.py                                多尺寸 .ico 打包
  make_ios_icons.py                          从同一批 PNG 派生 iOS 满幅图标
  package_win.py                             Windows 绿色版 zip 打包
docs/
  ios-build.md                               iOS 云端打包与 Sideloadly 装机步骤
```

