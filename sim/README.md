# RTL 功能仿真（sim）

本目录用于验证原始 RTL 的功能正确性。仿真 DUT 为 RTL `riscv`，不包含门级网表、SDF 或标准单元库时序。

## 目录约定

```text
sim/
├── hex/    # 程序指令，例如 code.hex
├── rtl/    # RTL 源码
├── tb/     # RTL testbench
└── sim/    # VCS 的 Makefile、files.f 与运行产物
```

## 运行

进入 `sim/sim/`：

```bash
make clean
make test
```

`files.f` 应包含 RTL 和 testbench，不应加入标准单元模型、SRAM 宏模型或 SDF。

## 通过判据

仿真日志中出现：

```text
PASS: x31 = 0x00000001
```

如果 RTL 仿真未通过，先修复 RTL / 指令文件 / testbench；不要直接转入 DC 或 PR 后仿真排查。
