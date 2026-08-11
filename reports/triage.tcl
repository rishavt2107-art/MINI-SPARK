set fp [open "reports/no_driven_nets.txt" r]
set fp_out [open "reports/no_driven_triage.txt" w]
foreach n [split [read $fp] "\n"] {
    set n [string trim $n]
    if {$n == ""} { continue }
    if {[catch {get_db [get_db nets -if [list .name == $n]] .num_loads} nload]} {
        puts $fp_out "$n\tERROR\t$nload"
    } else {
        puts $fp_out "$n\t$nload"
    }
}
close $fp
close $fp_out
puts ">>>>> triage done, wrote reports/no_driven_triage.txt"
