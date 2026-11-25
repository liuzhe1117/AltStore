# 重签名 App Group 配置导致的 Yandex Music 启动崩溃

## 本次证据

- iPhone 的 Maple 崩溃记录显示 Yandex Music 821（243839）在 AppMetrica 队列中抛出 Objective-C 异常，调用链包括 `AMAFileUtility writeData:filePath:error:`、`AMADiskFileStorage writeData:error:` 和 `NSURL fileURLWithPath:`。
- 下载目录原 IPA 的 Maple UUID 与设备崩溃镜像一致；以上 AppMetrica 方法由该二进制的 ObjC 方法元数据核对，未使用供应商 dSYM。
- 原始 Info.plist 的 `AMAApplicationGroupIdentifier` 和 `ExtensionAppGroup` 均指向 `group.ru.yandex.mobile.music`。
- AltStore / AltServer 的 provisioning 流程将组名改为 `原组名.签名团队`，但此前只写入 ALTAppGroups，未同步 SDK 自己的配置键。
- [AppMetrica 的组名读取逻辑](https://github.com/appmetrica/appmetrica-sdk-ios/blob/669e4cea5f46e165af75862850fd1e16ec667283/AppMetricaCore/Sources/AMAAppGroupIdentifierProvider.m)读取 AMAApplicationGroupIdentifier；[共享目录查询](https://github.com/appmetrica/appmetrica-sdk-ios/blob/669e4cea5f46e165af75862850fd1e16ec667283/AppMetricaCoreUtils/Sources/Utilities/AMAFileUtility.m)在不可访问组中返回 nil。这与文件路径异常、配置值及重签名行为一致。

另有一份首次启动 scene-create watchdog（约 19 秒）报告，当前不能证明与上述路径异常同源。实时日志补采因手机锁定失败，未取得异常 reason 原文；不把 nil 参数和整个启动问题表述为已完成实机闭环。

## 修复

新增两端共用的 Info.plist App Group 引用改写：从原始可执行文件的 App Group entitlement 到新 provisioning profile 实际授权的组名，递归改写完全相等的字符串值，包括 SDK 自定义字段、扩展字典和数组。

匹配仅限原组名与该组名加当前团队后缀，并以 profile 授权列表为准。不会通过任意子串猜测组名，也不会对已授权的原组名重复追加后缀。

## 验证

```sh
xcrun swiftc Shared/Extensions/AppGroupInfoPlist.swift AltTests/AppGroupInfoPlistTests.swift -o /tmp/appgroup-plist-tests
/tmp/appgroup-plist-tests /path/to/Yandex.app/Info.plist
```

回归通过：真实 Yandex Info.plist 两个字段、嵌套值、文件提供扩展、已授权原组、重复改写、无授权映射，以及不相关 URL / Bundle ID / 字典键 / 数字 / 布尔值。

iOS Release 构建通过；Mac 构建、签名及压缩包校验结果以随附 build-info.json 为准。未使用 Apple 账号安装本次修复包，实际启动仍待复测。

## 使用

- AltStore 2.3.1（77）用于手机重签名路径。
- AltServer 1.8.2（106）用于 Mac 重签名路径（Universal，ad-hoc，未公证）。

更新所用的签名工具后，必须用原始 Yandex Music IPA 覆盖重装 Yandex，使新配置进入它的安装包。仅更新 AltStore 或 AltServer 不会修改已安装的 Yandex App。
