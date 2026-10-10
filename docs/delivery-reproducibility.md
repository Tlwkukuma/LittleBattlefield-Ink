# 源码交付与打包检查（2026-10-09）

## 源码包

`.gitignore` 只忽略 Godot 缓存、构建输出、日志、Python 缓存和本机秘密配置。
工具、QA 脚本、文档、美术源文件、启动批处理、原始音频及许可说明属于源码交付范围。
这不会改变运行包中排除旧 `assets/audio/combat/` 的既有约定。

静态检查不启动游戏、不导入素材，也不写入 `.godot`：

```sh
python tools/test_validate_delivery.py
python tools/validate_delivery.py --manifest ../source-manifest.json
python tools/validate_delivery.py --verify ../source-manifest.json
```

请在所有修改合入、文件不再变化后重新生成最终清单。清单记录每个源码文件的路径、大小和 SHA-256，
并检查必要入口、JSON 语法和脚本/场景中的完整字面量资源引用。
动态构造的资源路径、运行时逻辑、画面、联机与素材授权资格不在该命令的证明范围内。
清单放在项目外或 `build/` 内，避免自包含散列。交付后再次比对可以发现缺失、增加或修改的文件。

## Windows x86-64 运行包

需要已安装的 Godot **4.6.3 stable** 以及匹配的 Windows release 导出模板。
`export_presets.cfg` 的 `Windows Release` 使用 `all_resources` 和 `*.json`，因此新战役 JSON 自动纳入，
除非路径匹配现有排除规则。`exports/*` 防止下一次导出把旧运行包内的 JSON 清单再次纳入；`qa/iteration_20261009/*` 与明确列出的 `qa/flash_registration_contract.json` 排除本轮诊断轨迹，源文件仍保留供审查。确认活动脚本/场景没有引用后，`data/campaign/drafts/*` 也排除出运行包；废止设计仍保留在源码包并标注历史状态。引擎与游戏版本是两个不同值；游戏版本仍只读取 `BUILD_VERSION`。

```powershell
$env:GODOT_EXE = 'C:\Godot\Godot_v4.6.3-stable_win64_console.exe'
powershell -NoProfile -File tools/package_lan_release.ps1
# 可选指定房主，格式与加入启动器一致：
powershell -NoProfile -File tools/package_lan_release.ps1 -HostAddress '192.168.1.8:27829'
```

打包脚本：

- 每次创建唯一的新构建和发行目录，不复用旧目录，不删除已有发行文件
- 没有提供房主地址时不会携带上次的 `host-address.txt`
- 检查导出退出码、错误日志、EXE/PCK 存在及非空
- 包含 Godot 生成的附属文件、原 LAN 启动器和两份现有音效许可说明
- 写入游戏与引擎版本，对所有发行文件计算 SHA-256，并为整个 ZIP 生成旁置 `.sha256`
- 保留失败导出日志，错误时不生成“成功”的 ZIP

底层跨平台导出命令（模板可用时）：

```sh
godot --headless --path . --export-release 'Windows Release' /absolute/output/LittleBattlefield.exe
```

### 云端模板准备与 Python 打包（后续已验证）

初始环境没有导出模板。获得用户许可后，已从 Godot 官方 4.6.3 release 下载标准模板包，
同时比对官方 GitHub release API 的 SHA-256 和 `SHA512-SUMS.txt` 的 SHA-512：

- 官方页面：https://godotengine.org/download/archive/4.6.3-stable/
- 模板包大小：1,255,918,323 字节；官方没有单独的 Windows 模板下载项
- SHA-256：`3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8`
- SHA-512：`da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68`

只展开 Windows x86-64 release/debug 与控制台程序、Linux x86-64 release/debug、版本文件，
位于源码项目旁的 `toolchain/share/godot/export_templates/4.6.3.stable/`。
没有改动全局 Godot 安装或安全设置；完整下载包及接收记录保留在项目旁的 `toolchain/`。
`toolchain/receipts/template-receipt.json` 记录来源、官方校验值、抽取文件的逐个散列。
工具链不混入游戏源码包或运行包。

Python 3.9+ 标准库打包工具不需要 PowerShell：

```sh
# 默认只检查版本、模板、校验回执与许可文件，不执行游戏导出
python tools/package_windows_release.py
python tools/test_package_windows_release.py

# 关卡/资源集成冻结并完成验收检查后，显式导出与打包
python tools/package_windows_release.py --export
# 可选参数：--godot /path/to/godot --data-home /path/to/toolchain/share
#            --receipt /path/to/template-receipt.json --host-address 192.168.1.8:27829
```

脚本导出前后各做一次源码清单比较。发现导出期间源码变化时停止，避免把混合版本称为完成版本。
每次使用独立输出目录，保留 Godot 日志，检查 Windows x86-64 PE 头和 Godot PCK 头，
打包后逐个核对 ZIP 内容与 SHA-256。导出后另外只读解析 PCK 目录，逐项核对内容 MD5、必需战役数据，以及明确排除的诊断/旧包/废止任务路径；无需启动游戏。目录格式依据 Godot 官方 4.6.3 的 `core/io/file_access_pack.cpp`。模板准备与包完整性检查都不能替代 Windows 实机运行或游戏可玩性验收。

`GODOT_LICENSE.txt`、`GODOT_COPYRIGHT.txt` 及原始音效许可一起纳入两种打包方式。
两条打包路径还复制精选四份文档到“资料”目录：五关历史设计（未实现）、原版关卡对照、十章实现/验证范围、AI迭代记录。当前使用说明先介绍离线战役；旧LAN说明保存在源码历史目录。所有资料文件也纳入递归SHA-256清单。PowerShell源码使用UTF-8 BOM以兼容Windows PowerShell 5.1的中文路径，校验清单使用无BOM UTF-8。

Godot 官方许可说明来源记在 `tools/lan-release/GODOT_NOTICES_SOURCE.txt`；这些文件不改变项目资产自身的授权范围。

## 编辑器 JSON 防护

`editor_plan_validation.gd` 在 `range_editor.gd` 建立撤销点或替换场景之前只读检查候选数据：
世界大小、已知容器形状、物件坐标、有限数值、重复物件 ID、已知预制体/组件/车辆 ID、出生点与地形点结构。
拒绝坏文件时不清空当前场景、选择或撤销历史，也不先编译候选场景。
这是导入边界防护，并非运行时和视觉正确性的完整证明。

纯数据回归测试：

```sh
godot --headless --path . --script qa/editor_plan_validation_check.gd
```

本轮测试在独立临时项目中运行，只加载验证模块和原始场景 JSON，不自动操作游戏，不访问并行导入缓存。

独立运行包内容检查（需已有导出的 PCK）：

```sh
python tools/test_inspect_release_pck.py
python tools/inspect_release_pck.py /path/LittleBattlefield.pck --verify-md5 --check-release --output /path/pck-inventory.json
```

### v2026.10.09.2 候选导出记录

Windows export 已成功，PCK 目录格式为 v3，1,179 个条目通过内容 MD5 复核，四份必需战役 JSON 存在，明确禁止的诊断、废止草案及旧导出路径不存在。候选 ZIP 的 22 个文件与逐文件 SHA-256 一致。

第一遍导出生成了 24 个缺失 `.gd.uid` 文件，源码冻结检查因此拒绝打包；保留日志后重新冻结元数据并第二次导出，检查通过。引擎仅提示忽略历史参考目录中的另一个 `project.godot`，未出现脚本/着色器/导出错误。

相同 PCK 配合官方 Linux release 模板，使用正常的同目录同名程序/PCK布局，在独立用户数据目录完成默认入口及第四、十章短启动检查。官方 release 模板不接受 `--path` 覆盖；前一次使用该参数的设置失败被保留，随后按标准便携目录结构启动成功。没有改动引擎安全配置。两个章节均停留在简报，模拟时间为0，未操作战斗。

以上建立运行包资源与启动证据，不代表Windows EXE在Windows上运行、完整关卡试玩、平衡、联机或性能已验证。最终归档会在AI剩余章节诊断结束后刷新文档；运行二进制若未变，不把文档更新称作新的玩法测试。
