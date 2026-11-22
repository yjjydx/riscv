# DC 门级后仿真（sim_dc）

本目录用于验证 **DC 综合输出的门级网表 + SDF**。它确认综合后的逻辑映射和延迟回标下，程序功能仍正确。

## 目录约定

```text
sim_dc/
├── hex/    # code.hex
├── rtl/    # 同一次 DC 输出的门级 .v、.sdf、.sdc
├── tb/     # 门级 testbench
└── sim/    # files.f、Makefile、sram.preload.data、VCS 产物
```

## 必要输入

- DC 门级网表 `.v` 与 SDF `.sdf` 必须来自同一次综合输出。
- 标准单元功能模型：
  `/home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/verilog/tcbn65lp_200a/tcbn65lp.v`
- SRAM 功能模型：
  `/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/VERILOG/ts1n65lpll2048x64m8_220a_ss1p08v125c.v`

`files.f` 顺序：标准单元模型、SRAM 模型、DC 门级网表、TB。不要再加入原 RTL，也不要把 `.sdc` / `.sdf` 放入 `files.f`。

## 运行

在 `sim_dc/sim/` 中先把 `code.hex` 转为 SRAM 预加载文件：

```csh
tr -d '\r' < ../hex/code.hex | \
perl -ne 'chomp; next if /^\s*$/; die "bad word: $_\n" unless /^[0-9A-Fa-f]{8}$/; printf "%064b\n", hex($_);' \
>! sram.preload.data
```

然后：

```bash
make clean
make test
```

TB 中对 DUT 执行 `$sdf_annotate`；若 SDF 为 `min::max` 格式，setup 仿真使用 `"MAXIMUM"`，hold 仿真使用 `"MINIMUM"`。

## 通过判据

```text
PASS: x31 = 0x00000001
```

出现 `Undefined module` 时检查单元/SRAM 功能模型；出现 SDF 实例不匹配时确认网表与 SDF 是同一次 DC 输出。
