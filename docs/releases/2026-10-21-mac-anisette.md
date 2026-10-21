# AltServer-mac / AltStore-mac-anisette（非官方构建）

[English](https://github.com/liuzhe1117/AltStore/releases/tag/v1.8-mac-anisette-unofficial-20261021) | [简体中文](https://github.com/liuzhe1117/AltStore/blob/fix/macos15-remote-anisette/docs/releases/2026-10-21-mac-anisette.md)

这是用于排查、缓解 `-80045` 和 Apple GrandSlam HTTP 503 的社区构建，不是 AltStore 官方发布。包含 macOS 的 AltServer，以及支持手机远程刷新的 AltStore IPA。

## 下载

- **[AltServer-mac.zip](https://github.com/liuzhe1117/AltStore/releases/download/v1.8-mac-anisette-unofficial-20261021/AltServer-mac.zip)**：解压得到 `AltServer-mac.app`。AltServer 1.8（98），Universal：Apple Silicon / Intel，ad-hoc 签名，未公证，无个人开发者证书签名。
- **[AltStore-mac-anisette.ipa](https://github.com/liuzhe1117/AltStore/releases/download/v1.8-mac-anisette-unofficial-20261021/AltStore-mac-anisette.ipa)**：AltStore 2.3（73），Release 构建，无个人证书或 provisioning profile，安装时由 AltServer 使用你的 Apple ID 重新签名。
- **[SHA256SUMS.txt](https://github.com/liuzhe1117/AltStore/releases/download/v1.8-mac-anisette-unofficial-20261021/SHA256SUMS.txt)**：两个安装包的 SHA-256 校验值。

应用声明的最低版本为 macOS 12.0、iOS 17.4。本轮实测环境是 macOS 15.7.2、iPhone 15 / iOS 26.6.1；Intel Mac、其他系统版本及 macOS 27 路径未在本轮真机测试。

## 基于哪些 PR，以及额外修改

基础是 AltStore 官方 `classic` 分支 `fafd76ee1a8a19c723146de278660aacce9ded5d`。

- [AltStore #1835](https://github.com/altstoreio/AltStore/pull/1835)：同步其手机端 Windows Anisette、认证及同步处理逻辑。
- [AltSign #61](https://github.com/rileytestut/AltSign/pull/61)：同步服务端提供的客户端身份、User-Agent、HTTP 错误处理及 Anisette resync；其基础包含 [AltSign #59](https://github.com/rileytestut/AltSign/pull/59) 的主动推送 2FA 处理。
- [AltStore #1838](https://github.com/altstoreio/AltStore/pull/1838)：清理 AltServer / AltJIT 遗留的 AltSign-Dynamic 产品依赖，修复相关 OpenSSL 链接问题。
- macOS 27+ 的远程 Anisette 客户端参考 [AltStore #1834](https://github.com/altstoreio/AltStore/pull/1834) 的方案，并作本仓库适配；不是原样合入该 PR。macOS 27 以下保留官方原生 AOSKit/Mail 获取路径。

在上述基础上，本构建增加：

1. 参考 [iLoader 2.3.9](https://github.com/nab138/iloader/releases/tag/v2.3.9) 和其[服务目录](https://github.com/nab138/iloader/blob/main/src/pages/Settings.tsx)，把 `https://new.ani.sidestore.io`、`https://mac-ani.jkcoxson.com` 放在此前添加的两个 Windows 服务之前。手机 Anisette 目录、自动候选顺序及 macOS 27+ 的远程默认列表均同步。
2. 修改服务器选择 UI：展示当前选中服务；设备连接状态为 Connected 时，可查看该服务返回的设备和平台字段（例如 MacBookPro / Mac OS X、PC / Windows）。这些字段是服务声明的身份，不是对服务器底层实现的审计结果。
3. 将 provisioning 状态绑定到服务 URL、client_info 和 user_agent；同一次 SRP 认证固定客户端身份，防止刷新数据时切换设备身份。
4. 无可用共享容器时跳过 App Group 数据迁移，避免相关启动崩溃；认证失败保留阶段、响应类型和长度等少量错误信息。

这些 PR 在本 fork 中的集成不代表已经被上游合并。没有额外加入通用 503 自动重试或 HTML 错误查看界面。

## 503 的实际情况

**只同步此前的 Windows 方案时，仍存在概率性的 HTTP 503。加入并切换到上述 iLoader Mac 服务后，本机本轮测试中的 503 阻塞得到解除，已成功完成手机远程刷新。**

这只是当前环境的实测结果，不代表永久或普遍解决了 503。Apple 认证及第三方 Anisette 服务仍可能失败；不同账号、网络和服务状态下仍可能复现。不要把 Anisette 服务自己的 502/503 与 `gsa.apple.com` 的认证 503 混为一谈。

手机远程刷新与电脑安装是两条路径：**macOS 15 的 AltServer 仍走原生 Anisette；手机设置中的 Mac 服务选择不会改变这条电脑路径。** 新列表优先级也不会强制覆盖用户已经保存的服务选择。

## 安装步骤

### 1. 安装 AltServer-mac

1. 从上方下载链接或[本次 Release](https://github.com/liuzhe1117/AltStore/releases/tag/v1.8-mac-anisette-unofficial-20261021) 下载 ZIP、IPA 和校验文件。退出正在运行的其他 AltServer，避免同时运行多个实例。
2. 解压 `AltServer-mac.zip`，将 `AltServer-mac.app` 移到 `/Applications`。
3. 如果 macOS 因下载隔离阻止打开，确认下载来源后执行：

   ```sh
   xattr -dr com.apple.quarantine /Applications/AltServer-mac.app
   ```

4. 打开该 App，确认菜单栏出现 AltServer 图标。本包使用 ad-hoc 签名、未公证；不要通过其官方自动更新入口覆盖本构建。
5. 用数据线连接 iPhone，解锁，并在手机或 Finder 出现提示时信任电脑。

### 2. 安装本次 Release 附带的 AltStore IPA

1. **按住 Option，再点击 AltServer 菜单栏图标**，选择 **Sideload .ipa… → 你的设备**。
2. 在文件选择框中选取本次 Release 下载的 **`AltStore-mac-anisette.ipa`**。
3. 输入自己的 Apple ID 和密码，按提示完成受信任设备的 2FA。SMS 2FA 在相关社区方案中仍有兼容性报告，本构建没有验证其可靠性。
4. 如 iOS 要求信任开发者，在 **设置 → 通用 → VPN 与设备管理** 中信任自己的开发者身份。
5. 如 iOS 要求开发者模式，在 **设置 → 隐私与安全性 → 开发者模式** 中开启，重启后确认。然后打开 AltStore。

**不要直接使用普通的 “Install AltStore…” 来安装这份修改版 IPA：该入口按官方配置下载 AltStore，不会自动使用本次 Release 附件。** 免费账号仍遵守苹果的应用数量、App ID 数量和 7 天有效期限制。

### 3. 配置手机远程刷新

1. 进入 AltStore 的 **Settings → Remote AltServer**，完成设置向导。
2. 在需要电脑配对的系统上，保持 USB 连接和 AltServer 运行，点击 **Pair with AltServer**，按提示确认信任。iOS 27 的向导可能改为 **Pair in Settings / Start Pairing**，按界面提示操作。
3. 安装并打开 [LocalDevVPN](https://apps.apple.com/app/id6755608044)，允许添加 VPN 配置并连接；保持 Wi-Fi 开启，返回 AltStore 完成向导。
4. 在 Remote AltServer 的服务器列表中，明确选择 **SideStore (Mac ADI)**（`new.ani.sidestore.io`）或 **jkcoxson (Mac ADI)**（`mac-ani.jkcoxson.com`）。本轮成功刷新时使用的是后者。
5. 确认远程模式已启用，界面展示所选服务，并在 Connected 时核对 Device / Platform。Connected 仅表示本机设备连接可达，不保证 Apple 认证成功。
6. 在 **My Apps** 刷新 AltStore 或其他应用。确认应用的到期时间确实更新；仅看到“7 days”不足以区分是否刚刚刷新成功。
7. 完成首次配对后，手机远程刷新不要求电脑持续运行，但需要 Wi-Fi、LocalDevVPN，以及可访问的 Anisette 和 Apple 服务。

### 4. 覆盖安装时的建议

**通过电脑覆盖安装 AltStore 后，建议重置 Remote AltServer 配置并重新配对。无需先卸载 AltStore 或其他已安装应用。**

1. 在 **Settings → Remote AltServer → Reset Remote AltServer** 中重置配置。
2. 重新执行上面的配对和 LocalDevVPN 设置步骤。
3. 重新选择其中一个 Mac Anisette 服务，然后测试刷新。

电脑覆盖安装会生成新的内嵌配对文件，而手机可能保留 Keychain 中已有的配对文件。遇到 `OnDeviceError 2` / `Connection reset by peer` 时，新旧配对不一致是需要排查的方向；它与 Apple 的 HTTP 503 是不同故障。重置不是已实现的自动更新修复，本包仍保留官方的配对导入策略。

## 自定义服务及问题排查

- 手机端优先使用用户选中的服务；获取 Anisette 数据失败时才尝试候选列表。Apple 已经返回认证 503 时，不会因此自动轮换所有服务。
- macOS 27+ 如需自定义电脑端远程 Anisette 服务，退出 AltServer 后设置，再重新打开：

  ```sh
  defaults write com.rileytestut.AltServer AnisetteServerURL https://mac-ani.jkcoxson.com
  ```

  恢复默认列表：

  ```sh
  defaults delete com.rileytestut.AltServer AnisetteServerURL
  ```

  此设置不适用于 macOS 27 以下的原生路径，也不修改手机端所选服务。
- 本包不内置 Anisette 服务器，依赖社区服务。按照当前实现，Apple ID 密码和验证码提交给 Apple；Anisette 服务参与设备身份 provisioning 和数据生成。
- 遇到 503 请记录错误发生于 `init`、`complete` 还是 `apptokens`，以及服务地址、系统和应用版本；稍后再试，避免连续密集尝试。不要公开账号密码、验证码、配对文件、adi.pb 或认证 token。

## 校验和源码

在两个安装包与校验文件所在目录运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

源码以[本次 Release](https://github.com/liuzhe1117/AltStore/releases/tag/v1.8-mac-anisette-unofficial-20261021) 标签为准，AltSign 子模块固定为 [`020ddb5691ffb9b75dfdd92b83a6809bbfdd1d5b`](https://github.com/liuzhe1117/AltSign/commit/020ddb5691ffb9b75dfdd92b83a6809bbfdd1d5b)。

```sh
git clone --recurse-submodules --branch v1.8-mac-anisette-unofficial-20261021 https://github.com/liuzhe1117/AltStore.git
cd AltStore
pod install
xcodebuild -workspace AltStore.xcworkspace -scheme AltServer -configuration Release -sdk macosx -destination 'platform=macOS' CURRENT_PROJECT_VERSION=98 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -workspace AltStore.xcworkspace -scheme AltStore -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CURRENT_PROJECT_VERSION=73 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

本轮使用 Xcode 26.3.0 构建。以上命令生成构建产物；macOS 分发包另作 ad-hoc 签名，iOS 产物封装成 `Payload/AltStore.app` 的 IPA，由安装工具重新签名。

感谢上述 PR 作者，以及 iLoader / isideload、SideStore、Anisette 服务维护者。原项目和依赖的许可证及版权声明保持适用。
