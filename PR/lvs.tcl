#!/usr/bin/tclsh

# Standalone Calibre LVS flow. Run this script inside PR_ydx/lvs_flow.

set top       riscv
set flow_dir  [file normalize [file dirname [info script]]]
set pr_root   [file dirname $flow_dir]

set src_gds   [file join $pr_root output ${top}.gds2]
set src_vg    [file join $pr_root data ${top}_lvs.vg]
set gds_file  [file join $flow_dir ${top}.gds2]
set vg_file   [file join $flow_dir ${top}.vg]
set spice_out [file join $flow_dir ${top}_source.sp]
set v2lvs_log [file join $flow_dir v2lvs.log]
set run_deck  [file join $flow_dir calibre_project.lvs]
set lvs_log   [file join $flow_dir lvs.log]
set lvs_rpt   [file join $flow_dir lvs.report]
set svdb_dir  [file join $flow_dir svdb]

set std_cdl "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/spice/tcbn65lp_200a/tcbn65lp_200a.spi"
set sram_cdl "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/SPICE/ts1n65lpll2048x64m8_220a.spi"
set rule_deck "/home/library/tsmc65lp/pdk_new/Calibre/online/lvs_online/1p9m_6X2Z0U/calibre.lvs"

proc require_file {path} {
  if {![file exists $path] || ![file readable $path]} {
    error "Required file is missing or unreadable: $path"
  }
}

proc require_command {name} {
  if {[auto_execok $name] eq ""} {
    error "Command not found: $name"
  }
}

proc backup_path {path stamp} {
  if {[file exists $path]} {
    file rename -force $path "${path}.bak_${stamp}"
  }
}

proc run_logged {label command log_file {allow_nonzero 0}} {
  puts "\n== $label =="
  puts [join $command " "]

  set rc [catch {exec {*}$command 2>@1} output options]
  set fp [open $log_file w]
  puts $fp $output
  close $fp
  puts $output

  if {$rc && !$allow_nonzero} {
    error "$label failed; see $log_file"
  }
  return $rc
}

proc replace_required {text pattern replacement label} {
  set count [regsub -all -line $pattern $text $replacement new_text]
  if {$count != 1} {
    error "Expected one active $label statement in the PDK deck, found $count"
  }
  return $new_text
}

cd $flow_dir
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]

# Check tools and source files.
require_command v2lvs
require_command calibre
foreach path [list $src_gds $src_vg $std_cdl $sram_cdl $rule_deck] {
  require_file $path
}

# Preserve previous outputs before a new run.
foreach path [list $spice_out $v2lvs_log $run_deck $lvs_log $lvs_rpt $svdb_dir] {
  backup_path $path $stamp
}

# Refresh the local GDS and Verilog from the final PR results.
file copy -force $src_gds $gds_file
file copy -force $src_vg  $vg_file

# Convert the final Verilog netlist to an LVS SPICE source.
set v2lvs_cmd [list \
  v2lvs \
  -v $vg_file \
  -o $spice_out \
  -lsr $std_cdl \
  -lsr $sram_cdl \
  -s $std_cdl \
  -s $sram_cdl \
  -s0 VSS \
  -s1 VDD \
]
run_logged "V2LVS" $v2lvs_cmd $v2lvs_log
require_file $spice_out

# Check the generated top-level and SRAM subcircuits.
set fp [open $spice_out r]
set source_text [read $fp]
close $fp

if {![regexp -nocase -line {^\.SUBCKT[ \t]+riscv[ \t]} $source_text]} {
  error "Top .SUBCKT riscv was not found in $spice_out"
}
if {![regexp -nocase -line {^\.SUBCKT[ \t]+TS1N65LPLL2048X64M8[ \t]} $source_text]} {
  error "SRAM .SUBCKT was not found in $spice_out"
}

# The PDK deck is a TVF template with active lvs_top placeholders.  Create a
# private copy and replace only its project-specific input/output statements.
set fp [open $rule_deck r]
set deck_text [read $fp]
close $fp

set deck_text [replace_required $deck_text \
  {^[ \t]*LAYOUT[ \t]+PRIMARY[^\n]*$} \
  "LAYOUT PRIMARY \"$top\"" "LAYOUT PRIMARY"]
set deck_text [replace_required $deck_text \
  {^[ \t]*LAYOUT[ \t]+PATH[^\n]*$} \
  "LAYOUT PATH \"$gds_file\"" "LAYOUT PATH"]
set deck_text [replace_required $deck_text \
  {^[ \t]*SOURCE[ \t]+PRIMARY[^\n]*$} \
  "SOURCE PRIMARY \"$top\"" "SOURCE PRIMARY"]
set deck_text [replace_required $deck_text \
  {^[ \t]*SOURCE[ \t]+PATH[^\n]*$} \
  "SOURCE PATH \"$spice_out\"" "SOURCE PATH"]
set deck_text [replace_required $deck_text \
  {^[ \t]*LVS[ \t]+REPORT[ \t]+\"[^\"]*\"[ \t]*$} \
  "LVS REPORT \"$lvs_rpt\"" \
  "LVS REPORT filename"]

set fp [open $run_deck w]
puts -nonewline $fp $deck_text
close $fp

# Run Calibre LVS. Preserve its report even when comparison is incorrect.
set calibre_cmd [list calibre -lvs -hier -turbo 32 $run_deck]
set calibre_rc [run_logged "CALIBRE LVS" $calibre_cmd $lvs_log 1]

if {![file exists $lvs_rpt]} {
  error "Calibre did not generate $lvs_rpt; see $lvs_log"
}

# Print key result lines.
set fp [open $lvs_rpt r]
set report_text [read $fp]
close $fp

puts "\n== LVS RESULT =="
foreach line [split $report_text "\n"] {
  if {[regexp -nocase {correct|incorrect|not compared|unmatched|error} $line]} {
    puts $line
  }
}

if {[regexp -nocase {incorrect|not compared} $report_text]} {
  puts "\nLVS comparison is not clean. Start RVE with: calibre -rve"
  exit 2
}
if {$calibre_rc != 0} {
  puts "\nCalibre returned a non-zero status. Check: $lvs_log"
  exit 3
}

puts "\nLVS run completed. Report: $lvs_rpt"
puts "RVE command: calibre -rve"
