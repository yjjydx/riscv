# Calculate current Innovus core box area.
# Usage in Innovus:
#   source area.tcl

# Output report path. Change this if you want the result saved elsewhere.
set area_report_file "./core_area.rpt"

# Read the current core box from Innovus database.
# The value is expected to be: xMin yMin xMax yMax, in database/user length units.
set core_box [dbGet top.fPlan.coreBox]

if {$core_box eq "" || [llength $core_box] != 4} {
  puts "ERROR: Cannot read top.fPlan.coreBox. Please run this after floorPlan is created."
  return
}

set x_min [lindex $core_box 0]
set y_min [lindex $core_box 1]
set x_max [lindex $core_box 2]
set y_max [lindex $core_box 3]

set core_width  [expr {$x_max - $x_min}]
set core_height [expr {$y_max - $y_min}]
set core_area   [expr {$core_width * $core_height}]
set core_area_mm2 [expr {$core_area / 1000000.0}]

set fp [open $area_report_file "w"]
puts $fp "Core Box Area Report"
puts $fp "===================="
puts $fp "core_box       : $core_box"
puts $fp "core_width     : $core_width um"
puts $fp "core_height    : $core_height um"
puts $fp "core_area      : $core_area um^2"
puts $fp "core_area_mm2  : $core_area_mm2 mm^2"
close $fp

puts "Core box       : $core_box"
puts "Core width     : $core_width um"
puts "Core height    : $core_height um"
puts "Core area      : $core_area um^2"
puts "Core area mm^2 : $core_area_mm2 mm^2"
puts "Report saved to $area_report_file"
