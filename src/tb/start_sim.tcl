
quit -sim

# Project paths and configuration
quietly set PROJECT_ROOT "../.."
quietly set RTL_PATH "${PROJECT_ROOT}/src/rtl"
quietly set TB_PATH "${PROJECT_ROOT}/src/tb"
quietly set SW_PATH "${PROJECT_ROOT}/sw"
quietly set SO_LIB_FILE "${PROJECT_ROOT}/sw/eth_dpi"

file mkdir alt_verilog_libs

vlib alt_verilog_libs/altera_mf_ver
vmap altera_mf_ver ./alt_verilog_libs/altera_mf_ver
vlog -vlog01compat -work altera_mf_ver "${PROJECT_ROOT}/src/rtl/altera_mf.v"



# Source file lists
quietly set RTL_FILES [list \
    "${RTL_PATH}/arp_pkg.sv" \
    "${RTL_PATH}/arp_parser.sv" \
    "${RTL_PATH}/arp_sender.sv" \
    "${RTL_PATH}/icmp_pkg.sv" \
    "${RTL_PATH}/icmp_parser.sv" \
    "${RTL_PATH}/icmp_sender.sv" \
    "${RTL_PATH}/top.sv" \
    "${RTL_PATH}/dc_fifo_wrapper.sv" \
]

# Testbench files
quietly set TB_FILES [list \
    "${TB_PATH}/arp_tb.sv" \
]


# Clean 
if { [file exists "work"] } { 
    file delete -force "work" 
}

vlib work


puts "Compiling RTL sources..."
foreach rtl_file $RTL_FILES {
    vlog -quiet -sv +nowarnSVCHK $rtl_file
}

puts "Compiling testbench sources..."
foreach tb_file $TB_FILES {
    vlog -quiet -sv +define+SIMULATION +incdir+${TB_PATH} $tb_file
}

puts "Starting simulation..."
vsim -sv_lib ${SO_LIB_FILE} \
     -voptargs="+acc" \
     -t 1ns \
     -L work \
     -L altera_mf_ver \
     work.arp_tb

log -r *

do wave.do
run -all

