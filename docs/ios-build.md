# iOS 云端打包与装机

iOS 的 `.ipa` **只能在 macOS 上用 Xcode 编译**，Windows 本机做不到。这份文档走的是
「云端 macOS 编译 → 本地免费签名」路线，全程不需要买 Mac，也不需要 Apple 开发者账号。

```
你的 Windows 机器                    GitHub（macOS runner）
─────────────────                    ──────────────────────
git push  ──────────────────────▶    flutter build ios --no-codesign
                                     打包 Payload/ → moread-unsigned.ipa
下载 .ipa ◀──────────────────────    上传为构建产物（artifact）
   │
   ▼
Sideloadly + 免费 Apple ID 签名 → 装进 iPhone（7 天有效）
```

代价说在前面：免费签名 **7 天后过期**，要重新签一次。想长期使用就得买
Apple Developer Program（$99/年），见文末「升级到正式签名」。

---

## 一、把代码推到 GitHub

仓库可以私有也可以公开。私有仓库的 Actions 免费额度是 2000 分钟/月，而 macOS
runner **按 10 倍扣**，等于实际约 200 分钟——一次构建约 8～12 分钟，够跑十几次。
公开仓库不受此限。

```bash
cd D:/aiitem/k_md/flutter_app
git init -b main
git add .
git commit -m "墨阅 MoRead 1.0.0：Windows 版 + iOS 云端打包"
git remote add origin https://github.com/<你的用户名>/moread.git
git push -u origin main
```

推送时会自动触发 `.github/workflows/ios-unsigned-ipa.yml`。

> 只改文档（`**.md`、`docs/**`）不会触发构建，这是有意为之——省 macOS 额度。

## 二、等构建跑完

打开仓库的 **Actions** 标签页，点进最新一次 `Build iOS (unsigned IPA)`。
整个过程大约 8～12 分钟，主要时间花在拉取 Flutter SDK、解析 Swift Package 依赖和 Flutter 编译上。

工作流里有两道关卡先跑：`flutter analyze` 和三个平台无关的测试文件。

> `test/visual_check.dart` 被刻意排除在外——它加载的是 `C:\Windows\Fonts` 下的字体
> 并且做 golden 比对，在 macOS runner 上必然失败。`icon_gen.dart`、`ico_verify.dart`
> 是生成器，产物已经提交进仓库，不需要在 CI 里重算。

## 三、下载 .ipa

构建成功的运行页底部有 **Artifacts** 区域，下载 `moread-unsigned-ipa`。

GitHub 会把产物套一层 zip，所以拿到的是 `moread-unsigned-ipa.zip`——
**解压一次**才是真正的 `moread-unsigned.ipa`。

## 四、用 Sideloadly 装进 iPhone

Sideloadly 有 Windows 版，这是这条路能走通的关键。

1. 到 [sideloadly.io](https://sideloadly.io) 下载 Windows 版并安装。
   它会依赖 iTunes 的驱动，没装过 iTunes 的话按提示装上。
2. 用数据线把 iPhone 连到电脑，手机弹出「要信任此电脑吗」时点**信任**。
3. 手机上打开 **设置 → 隐私与安全性 → 开发者模式**，打开后按提示重启手机。
   （iOS 16 及以上必须开，否则装完打不开。）
4. 打开 Sideloadly，把 `moread-unsigned.ipa` 拖进窗口，
   **Apple ID 填你自己的免费 Apple ID**，点 Start。
   会提示输入密码——这是在向苹果申请一张 7 天期的开发证书，密码只经过苹果服务器。
5. 装完后手机上打开 **设置 → 通用 → VPN 与设备管理**，
   在「开发者 App」里找到你的 Apple ID，点**信任**。
6. 回到主屏，**墨阅 MoRead** 就能打开了。

## 五、7 天过期怎么办

免费证书签发的 App 会在 7 天后打不开，图标还在但一点就闪退。两种应对：

- **手动重签**：保持 .ipa 在本地，每 7 天用 Sideloadly 重装一次（同一 Apple ID 即可）。
- **自动重签**：Sideloadly 提供后台守护进程，只要电脑和手机在同一个网络里，
  它会自动帮你续签，不用手点。

另外免费 Apple ID 还有两个限制，属于苹果的规则，绕不过去：
同一台设备上最多同时存在 **3 个**自签 App；7 天内最多注册 **10 个** App ID。

## 六、iOS 上的功能边界

这是**同一个代码库跑在 iOS 上**，不是为触屏重做的移动版，所以有些差异要提前知道：

| 能力 | iOS 上的表现 |
| :--- | :--- |
| 打开 .md | 拉起「文件」App 的选择器，读到的是拷进沙盒的**副本**，不是原文件 |
| 另存为 | iOS 没有「另存为」对话框。降级为写进 App 沙盒的 Documents 目录 |
| 找到保存的文件 | 「文件」App → 我的 iPhone → 墨阅 MoRead（靠 `UIFileSharingEnabled`） |
| 编辑 / 阅读 / 源码三种视图 | 都有，工具栏可点 |
| 代码块、公式、Mermaid、表格、灯箱 | 都正常 |
| `Ctrl+O/S/N` 等快捷键 | 在 iPhone 上没有意义（需要外接键盘） |
| 三栏布局、悬浮大纲、鼠标 hover | 能显示但不为触屏优化 |

也就是说：**阅读体验是完整的，编辑交互是"能用但没为手机设计"**。
真要当手机 App 用，还需要一轮触屏化改造（底部工具栏、手势、单栏导航）。

## 七、升级到正式签名（可选）

想摆脱 7 天限制，或者想装给别人测试，就得加入 Apple Developer Program（$99/年）：

1. 注册 Apple Developer Program，在 App Store Connect 里建好 App 记录。
2. 生成一张 **App Store Connect API Key**（.p8 文件）。
3. 把 key 及 Issuer ID、Key ID 存进仓库 Secrets。
4. 工作流里用 `app-store-connect` 或 `apple-actions/import-codesign-certs`
   导入证书与描述文件，然后**去掉 `--no-codesign`**，
   改用 `flutter build ipa --export-options-plist=...`。
5. 产物直接上传 TestFlight，可以邀请最多 10000 名测试者，签名一年有效。

工作流头部注释里写了这三步要改哪里。

## 八、常见问题

**构建在 `flutter analyze` 就红了**
先在本机跑 `flutter analyze` 复现，改完再推。CI 上跑的和本机是同一套规则。

**报错 `The sandbox is not in sync with the Podfile.lock`**
别照着提示去跑 `pod install`。真正原因是 **`ios/` 下多了一份 `Podfile`**。

Flutter 3.4x 起 iOS 插件默认走 **Swift Package Manager**，本工程的
`file_selector_ios`、`url_launcher_ios` 都是 Swift Package，**官方 ios 模板本身就不含 Podfile**。
凭空加一份 Podfile 会开启 CocoaPods 集成，可实际上没有任何 pod 需要安装，
`pod install` 往 `Runner.xcodeproj` 注入的 Pods 校验阶段就会失败。

**解法：删掉 `ios/Podfile`**。工作流里已加了一道前置检查，它一旦被加回来就立刻报错提醒。

**构建卡在依赖解析**
同上，先确认没有 Podfile。走 SPM 解析插件依赖比 CocoaPods 快得多。

**提示 `Runner.app` 找不到**
说明 `flutter build ios` 没真正产出。日志里往上翻，找第一条 `Error (Xcode)`。

**macOS 额度用完了**
把仓库改成公开，或等下个月额度重置。也可以在 Actions 页面
手动 `Run workflow` 前先把不需要的分支停掉。

**装到手机上一点就闪退**
九成是忘了信任开发者证书，回到第四步的第 5 条。

## 九、推送前先自查

iOS 适配改动集中在 `lib/io/file_service.dart`、`lib/ui/brand_mark.dart`、
`test/icon_gen.dart`、`ios/` 目录。推之前在本机确认一遍全绿：

```bash
flutter pub get
flutter analyze
flutter test test/widget_test.dart test/reading_test.dart test/render_test.dart
```

三条都过了再 push，能省掉一次失败的云端往返（一次就是 10 分钟的 macOS 额度）。
