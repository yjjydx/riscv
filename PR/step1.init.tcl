# 命令说明：加载初始化变量、库路径、网表路径、约束路径和通用运行设置。
source ../script/init_setup.tcl
# 命令说明：向 runtime.log 追加初始化导入阶段的开始时间记录。
echo "START : 01_innovus_import_design $rundate" >> ../report/runtime.log

# 命令说明：删除旧的 init 阶段报告目录，避免历史报告混入本次结果。
exec rm -rf ../report/init
# 命令说明：重新创建 init 阶段报告目录。
file mkdir  ../report/init
# 命令说明：设置本地并行 CPU 数为 32，加速设计导入和检查。
setMultiCpuUsage -localCpu 32

# 命令说明：加载全局 Innovus 初始化变量和时序全局开关。
source ../script/global.tcl


# 命令说明：执行 Innovus 设计导入，读取网表、LEF、MMMC 和电源地网络设置。
init_design 

# 命令说明：设置工艺节点为 65nm。
setDesignMode -process 65
# 命令说明：设置实现流程努力程度为 standard。
setDesignMode -flowEffort standard

# 命令说明：创建基础时序路径组，便于后续报告和优化按路径类别展开。
createBasicPathGroups -expanded

# 命令说明：检查设计对象命名是否唯一，并输出详细信息。
checkUnique -verbose
# 命令说明：检查网表连通性和结构问题，并把结果写入 init 报告。
checkNetlist         -outfile ../report/init/$init_design.checkNetlist.rpt
# 命令说明：执行完整设计检查，并把各类检查报告输出到 init 目录。
checkDesign -all     -outdir ../report/init/
# 命令说明：执行详细时序检查，并把输出重定向到 check_timing 报告。
check_timing -verbose   >       ../report/init/$init_design.check_timing.rpt
# 命令说明：导出当前设计中的时钟报告。
report_clocks > ../report/init/clock.rpt

# 命令说明：在布局前执行 setup 时序分析，展开寄存器到寄存器路径并输出最多 100 条路径。
timeDesign  -expandReg2Reg -prePlace  -numPaths 100          -outdir ../report/init
# 命令说明：在布局前执行 hold 时序分析，展开寄存器到寄存器路径并输出最多 100 条路径。
timeDesign  -expandReg2Reg -prePlace  -numPaths 100  -hold   -outdir ../report/init

# 命令说明：保存初始化导入后的 Innovus 数据库。
saveDesign  ../database/$init_design.init.enc

# 命令说明：向 runtime.log 追加初始化导入阶段的结束时间记录。
echo "END : 01_innovus_import_design $rundate" >> ../report/runtime.log

# 命令说明：退出 Innovus 当前批处理脚本。
exit


