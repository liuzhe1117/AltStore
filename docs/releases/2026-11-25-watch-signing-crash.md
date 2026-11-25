# AltStore 安装第三方 App 时的签名崩溃修复

## 证据与原因

连接设备导出的两份 2026-11-25 崩溃报告均来自 AltStore 2.3.1（74），为 `EXC_BAD_ACCESS / SIGSEGV`，故障链为 `ldid::Allocate → std::string(const char *) → strlen(NULL)`。AltStoreCore 的 UUID 与本次本地构建 dSYM 一致。

符号及反汇编显示，空指针是 `CodesignAllocation.arch_`：旧 ldid 未识别 Apple Watch 的 `CPU_TYPE_ARM64_32`（0x0200000c），架构名称保持 NULL，进度回调将其转换为 std::string 时崩溃。该过程在重签名阶段发生，早于 Remote AltServer / LocalDevVPN 的实际安装。

下载目录中的一个 Watch 可执行文件同时包含 arm64 和 arm64_32。使用上一构建的真实签名对象进行离线重签名可复现 SIGSEGV；修复后的同一操作返回 0。实际导致用户这次安装的 IPA 名称尚未独立确认。

## 修复

- 在 ldid 中支持 arm64_32 的架构名称和 16 KiB 对齐。
- 对其他未知 CPU 类型抛出带类型值的异常。AltSigner 已有 std::exception 捕获，将其转为安装错误，避免 strlen(NULL)。
- 签名库源码位于 [liuzhe1117/ldid 的修复分支](https://github.com/liuzhe1117/ldid/tree/fix/arm64-32-signing-crash)，AltSign 与主工程固定完整依赖节点。

## 验证

- 七种已知架构的分配进度回调均通过；未知 CPU 类型返回可捕获错误。
- 实际 Watch 可执行文件：旧签名库 SIGSEGV，修复后离线 ad-hoc 重签名成功返回；两个架构的 SHA-1 / SHA-256 代码页哈希共 17,566 项全部通过。
- 离线测试使用 ad-hoc 身份，不能满足原包的 Apple 身份要求；未把此测试解释为 Apple 开发者证书或真机安装验证。
- iOS Release 与 Universal macOS Release 构建成功。
- Mac 分发包通过 ad-hoc 签名验证；ZIP / IPA 完整性及 SHA-256 校验通过。
- 仍需使用者在手机上重试原第三方 App 的完整安装流程。

## 产物与使用

- AltStore 2.3.1（75）：`AltStore-2.3.1-75.ipa`，arm64，iOS 17.4+，安装时重新签名。
- AltServer 1.8.2（103）：`AltServer-1.8.2-103.zip`，arm64 / x86_64，macOS 12+，ad-hoc 签名，未公证。

通过 Mac AltServer 的 Option 菜单 → **Sideload .ipa…** 覆盖安装本次 IPA，无需卸载现有 AltStore。打开后确认 build 为 75，再用原来的 Remote AltServer + LocalDevVPN 路径重试第三方 App。Mac 包也更新了共用签名库，可用于电脑侧安装含 Watch 二进制的 IPA。

复现和测试文件保留在本地临时目录，未提交原始设备报告、第三方 IPA、证书、账号或配对材料。
