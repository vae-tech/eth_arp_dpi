onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate /arp_tb/dut/*
add wave -noupdate -expand -group ARP -group parser /arp_tb/dut/arp_top_inst/arp_parser_inst/*
add wave -noupdate -expand -group ARP -group sender /arp_tb/dut/arp_top_inst/arp_sender_inst/*
add wave -noupdate -expand -group ICMP -group parser /arp_tb/dut/icmp_top_inst/icmp_parser_inst/*
add wave -noupdate -expand -group ICMP -group sender /arp_tb/dut/icmp_top_inst/icmp_sender_inst/*

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 326
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update

WaveRestoreZoom {0 ns} {887 ns}
