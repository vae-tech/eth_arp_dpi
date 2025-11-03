#!/bin/bash

# !!! Update to your Modelsim home directory
export MSIM_HOME=/home/vae/Questa_sim/questasim
export LM_LICENSE_FILE=/home/vae/Questa_sim/license.dat


export MSIM_INCLUDES=$MSIM_HOME/include
# MSIM 64bit mode 
export MTI_VCO_MODE=64

ROOT_DIR=$(pwd)

# Parse command line arguments

GUI="-c" # default to console mode

while [[ $# -gt 0 ]]; do
    case $1 in
        -gui| -g)
            GUI=""
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -gui, -g       Run with GUI"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done


rm -rf work **.wlf transcript
rm -rf ${ROOT_DIR}/tb/alt_verilog_libs \
${ROOT_DIR}/tb/modelsim.ini \
${ROOT_DIR}/tb/transcript \
${ROOT_DIR}/tb/*.wlf
${ROOT_DIR}/tb/vsim_stacktrace.vstf

cd ${ROOT_DIR}/sw
make

cd ${ROOT_DIR}/src/tb


vsim ${GUI} -do start_sim.tcl