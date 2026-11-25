# Watch 伴随 App 标识符、描述文件与签名修复

## 问题

AltStore 2.3.1（75）已修复 arm64_32 签名崩溃，但安装 Yandex Music 时，主 App ID 改为带签名团队后缀的新值，Watch 的 WKCompanionAppBundleIdentifier 仍指向原值，导致 iOS 安装校验失败。

这不是单一字段的问题：原流程没有为 Watch App 和内部扩展生成、改写及嵌入独立的 provisioning profile，也没有完整保留每个嵌套 bundle 的签名权限。

## 集成

在现有修复分支上集成尚未合并的社区 PR：

- [AltStore #1859](https://github.com/altstoreio/AltStore/pull/1859)：嵌套应用 provisioning、准确的 Bundle ID 映射、权限校验、过期时间和完整重签名刷新。
- [AltSign #64](https://github.com/rileytestut/AltSign/pull/64)：递归发现 Watch App、改写 WKCompanionAppBundleIdentifier / WKAppBundleIdentifier、嵌入独立描述文件与权限。
- [ldid #7](https://github.com/rileytestut/ldid/pull/7)：递归签名 Watch App 和扩展，分别使用各 bundle 的权限。

本 fork 中的认证及 arm64_32 修复仍包含在对应依赖节点中。

## 验证

- 独立回归套件：108 项断言通过。
- 使用下载目录中的 Yandex Music IPA 的临时副本运行生产代码测试：136 项断言通过，涵盖主 App、三个 iPhone 扩展、Watch App 的 ID 映射、独立描述文件、权限和 codesign 深度严格验证。
- 真实 IPA 测试使用临时生成的测试证书与合成描述文件，并向副本中注入 HealthKit 测试权限。它验证改写及签名完整性，不代表真实 Apple 账号的 capability、设备覆盖或安装成功。
- iOS Release 构建成功。Mac Release、打包与校验结果以随附 build-info.json 为准。
- 没有使用 Apple 账号进行设备安装、Watch 同步或实际续签测试。

## 产物

- `AltStore-2.3.1-76.ipa`：iOS 17.4+，arm64，安装时重新签名。
- `AltServer-1.8.2-104.zip`：macOS 12+，Universal，ad-hoc 签名，未公证。

用 Mac AltServer 的 Option 菜单 → Sideload .ipa… 覆盖安装 build 76，然后通过手机 Remote AltServer + LocalDevVPN 重试原 IPA。无需卸载 AltStore。

Watch 和内部扩展会占用额外 App ID；实际 Watch 安装仍要求相应设备和权限已获开发者账号授权。完整要求见 `docs/WatchCompanionSigning.md`。
