# AltServer 安装完成后不返回、后续安装排队的修复

## 本机证据

- 正在运行的是 AltServer 1.8.2（104）。
- 安装日志显示文件已写入设备并发出安装请求；采样显示串行安装队列停在 ALTDeviceManager.mm 的无限 semaphore 等待，主线程仍响应事件。
- usbmuxd 在该次安装请求发出约两秒后记录目标 iPhone 的 USB 连接断开。
- 通过 devicectl 读取到手机已经安装 AltStore 2.3.1（76）。随后另一个安装请求仍被堵在同一安装队列。
- 这些证据确认队列没有结束等待，但不能单独证明旧进程究竟漏掉了哪一条设备状态回调。

## 修复

- 明确处理 installation_proxy 的 Complete 状态，包括没有任何先行百分比进度的情况。
- 非终态状态缺少 PercentComplete 时不再提前判定成功。
- 检查 instproxy_install 的立即返回值，请求未启动时直接回报错误。
- 将无限等待改为五分钟上限；失联或没有终态回调时结束该次等待，并提示先检查手机是否已安装。
- 通过锁保护首次终态结果，避免重复回调或超时竞争导致重复完成。
- 将 C 客户端释放和上层完成通知移到安装队列，避免在接收回调线程内释放客户端、等待自身线程。
- 对安装回调映射的访问加同步，释放状态解析分配的字符串。

## 验证

```sh
python3 AltTests/run-installation-callback-tests.py
```

测试直接编译源码中的生产回调及首次完成 block，使用合成设备状态与 64 个并发终态回调。覆盖无先行进度的 Complete、中间状态、错误映射、迟到回调和仅唤醒一次。

同一测试针对修复前的 HEAD 版本在 Complete without preceding progress 用例失败；当前源码全部通过。

Universal macOS Release 构建通过。未使用 Apple 账号重试真实设备安装。

## 使用

安装 `AltServer-1.8.2-105.zip` 中的 Mac App（ad-hoc 签名，未公证）。先完全退出旧 AltServer，再替换并重新打开，以清除旧进程已经卡住的安装队列。保持 iPhone 解锁和连接稳定，重新尝试安装 Yandex Music。

手机上的 AltStore 2.3.1（76）已经安装，可以继续使用。此修复只涉及 Mac 端安装管理。
