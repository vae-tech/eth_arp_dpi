/*================================================================
  DC FIFO Wrapper Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This module is used to wrap the DC FIFO module for Xilinx and Altera.
        It provides a common interface for the DC FIFO module.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

module dc_fifo_wrapper #(
    // Vendor Selection
    parameter VENDOR           = "XILINX",        // "XILINX" or "ALTERA"/"INTEL"
    
    // Common FIFO Configuration
    parameter DATA_WIDTH       = 32,              // Data width in bits
    parameter FIFO_DEPTH       = 2048,            // FIFO depth (must be power of 2)
    parameter ADDR_WIDTH       = $clog2(FIFO_DEPTH),
    
    // Common Functional Parameters
    parameter FWFT_MODE        = 1,               // 1 = First Word Fall Through, 0 = Standard read
    parameter MEMORY_TYPE      = "auto",          // "auto", "block", "distributed" (registers/logic)
    parameter CDC_SYNC_STAGES  = 2,               // Clock domain crossing synchronization stages (2-8)
    
    // Common Threshold Parameters
    parameter PROG_FULL_THRESH  = 10,             // Programmable full threshold
    parameter PROG_EMPTY_THRESH = 10,             // Programmable empty threshold
    parameter ALMOST_FULL_THRESH  = FIFO_DEPTH - 4,  // Almost full threshold
    parameter ALMOST_EMPTY_THRESH = 4,            // Almost empty threshold
    
    // Common Feature Enables
    parameter ENABLE_OVERFLOW_CHECK  = 1,         // Enable overflow checking
    parameter ENABLE_UNDERFLOW_CHECK = 1,         // Enable underflow checking
    parameter ENABLE_DATA_COUNT      = 0,         // Enable data count outputs
    parameter ENABLE_ALMOST_FLAGS    = 0,         // Enable almost full/empty flags
    
    // Device-Specific Overrides (Optional - for advanced users)
    parameter XILINX_ECC_MODE      = "no_ecc",    // Xilinx: "no_ecc", "en_ecc"
    parameter ALTERA_DEVICE_FAMILY = "Cyclone V", // Altera: Device family
    parameter ALTERA_SYNC_DEPTH    = 4            // Altera: Sync pipeline depth
) (
    // Write Clock Domain
    input  logic                    wr_clk,
    input  logic                    wr_rst,
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    output logic                    wr_full,
    output logic                    wr_rst_busy,
    
    // Read Clock Domain
    input  logic                    rd_clk,
    input  logic                    rd_rst,
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_empty,
    output logic                    rd_valid,
    output logic                    rd_rst_busy
);

    //-----------------------------------------------------------------------------------
    // Internal signals and parameter mappings
    //-----------------------------------------------------------------------------------
    
    localparam RD_DATA_COUNT_WIDTH = ADDR_WIDTH + 1;
    localparam WR_DATA_COUNT_WIDTH = ADDR_WIDTH + 1;
    
    // Map common parameters to vendor-specific values
    // Xilinx READ_MODE: "std" or "fwft"
    localparam XILINX_READ_MODE = (FWFT_MODE == 1) ? "fwft" : "std";
    
    // Xilinx FIFO_MEMORY_TYPE: "auto", "block", "distributed", "ultra"
    localparam XILINX_MEMORY_TYPE = (MEMORY_TYPE == "auto")        ? "auto" :
                                     (MEMORY_TYPE == "block")       ? "block" :
                                     (MEMORY_TYPE == "distributed") ? "distributed" :
                                     "auto";
    
    // Xilinx USE_ADV_FEATURES: 16-bit binary string
    // Bit encoding: [overflow, underflow, prog_full, prog_empty, almost_full, almost_empty, wr_data_count, rd_data_count, wr_ack, data_valid, ...]
    localparam [15:0] XILINX_ADV_FEAT = {
        4'b0000,  // Reserved
        ENABLE_OVERFLOW_CHECK[0],    // overflow
        ENABLE_UNDERFLOW_CHECK[0],   // underflow  
        1'b1,                        // prog_full (always enabled for threshold)
        1'b1,                        // prog_empty (always enabled for threshold)
        ENABLE_ALMOST_FLAGS[0],      // almost_full
        ENABLE_ALMOST_FLAGS[0],      // almost_empty
        ENABLE_DATA_COUNT[0],        // wr_data_count
        ENABLE_DATA_COUNT[0],        // rd_data_count
        1'b0,                        // wr_ack
        1'b1,                        // data_valid (always enabled)
        2'b00                        // Reserved
    };
    localparam XILINX_USE_ADV_STR = $sformatf("%04x", XILINX_ADV_FEAT);
    
    // Altera LPM_SHOWAHEAD: "ON" or "OFF"
    localparam ALTERA_SHOWAHEAD = (FWFT_MODE == 1) ? "ON" : "OFF";
    
    // Altera USE_EAB: "ON" for block RAM, "OFF" for logic
    localparam ALTERA_USE_EAB = (MEMORY_TYPE == "distributed") ? "ON" : "OFF";
    
    // Altera overflow/underflow checking
    localparam ALTERA_OVERFLOW_CHK  = ENABLE_OVERFLOW_CHECK  ? "ON" : "OFF";
    localparam ALTERA_UNDERFLOW_CHK = ENABLE_UNDERFLOW_CHECK ? "ON" : "OFF";
    
    // Internal signals for advanced features
    logic                              almost_empty;
    logic                              almost_full;
    logic                              overflow;
    logic                              underflow;
    logic [RD_DATA_COUNT_WIDTH-1:0]    rd_data_count;
    logic [WR_DATA_COUNT_WIDTH-1:0]    wr_data_count;
    logic                              prog_empty;
    logic                              prog_full;
    
    // Xilinx specific signals
    logic                              dbiterr;
    logic                              sbiterr;
    logic                              r_rst_busy;
    logic                              w_rst_busy;
    logic                              wr_ack;

    // xilinx specific signals
    assign wr_rst_busy = VENDOR == "XILINX" ? w_rst_busy : 1'b0;
    assign rd_rst_busy = VENDOR == "XILINX" ? r_rst_busy : 1'b0;
    //-----------------------------------------------------------------------------------
    // Vendor Selection using Generate Blocks
    //-----------------------------------------------------------------------------------
    
    generate
        if (VENDOR == "XILINX") begin : gen_xilinx_fifo
            
            // Xilinx XPM Dual Clock FIFO
            xpm_fifo_async #(
                .CASCADE_HEIGHT      (0),
                .CDC_SYNC_STAGES     (CDC_SYNC_STAGES),
                .DOUT_RESET_VALUE    ("0"),
                .ECC_MODE            (XILINX_ECC_MODE),
                .FIFO_MEMORY_TYPE    (XILINX_MEMORY_TYPE),
                .FIFO_READ_LATENCY   (1),
                .FIFO_WRITE_DEPTH    (FIFO_DEPTH),
                .FULL_RESET_VALUE    (0),
                .PROG_EMPTY_THRESH   (PROG_EMPTY_THRESH),
                .PROG_FULL_THRESH    (PROG_FULL_THRESH),
                .RD_DATA_COUNT_WIDTH (RD_DATA_COUNT_WIDTH),
                .READ_DATA_WIDTH     (DATA_WIDTH),
                .READ_MODE           (XILINX_READ_MODE),
                .RELATED_CLOCKS      (0),
                .SIM_ASSERT_CHK      (0),
                .USE_ADV_FEATURES    (XILINX_USE_ADV_STR),
                .WAKEUP_TIME         (0),
                .WRITE_DATA_WIDTH    (DATA_WIDTH),
                .WR_DATA_COUNT_WIDTH (WR_DATA_COUNT_WIDTH)
            ) xpm_fifo_async_inst (
                // Write Clock Domain
                .wr_clk        (wr_clk),
                .wr_rst        (wr_rst),
                .wr_en         (wr_en),
                .din           (wr_data),
                .full          (wr_full),
                .almost_full   (almost_full),
                .wr_ack        (wr_ack),
                .overflow      (overflow),
                .wr_data_count (wr_data_count),
                .prog_full     (prog_full),
                .wr_rst_busy   (w_rst_busy),
                
                // Read Clock Domain
                .rd_clk        (rd_clk),
                .rd_rst        (rd_rst),
                .rd_en         (rd_en),
                .dout          (rd_data),
                .empty         (rd_empty),
                .almost_empty  (almost_empty),
                .data_valid    (rd_valid),
                .underflow     (underflow),
                .rd_data_count (rd_data_count),
                .prog_empty    (prog_empty),
                .rd_rst_busy   (r_rst_busy),
                
                // ECC
                .sleep         (1'b0),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (sbiterr),
                .dbiterr       (dbiterr)
            );
            
        end else if (VENDOR == "ALTERA" || VENDOR == "INTEL") begin : gen_altera_fifo
            
            // Intel/Altera DCFIFO
            dcfifo #(
                .lpm_width              (DATA_WIDTH),
                .lpm_widthu             (ADDR_WIDTH),
                .lpm_numwords           (FIFO_DEPTH),
                .lpm_showahead          (ALTERA_SHOWAHEAD),
                .lpm_type               ("dcfifo"),
                .overflow_checking      (ALTERA_OVERFLOW_CHK),
                .underflow_checking     (ALTERA_UNDERFLOW_CHK),
                .use_eab                (ALTERA_USE_EAB),
                .add_ram_output_register("OFF"),
                .intended_device_family (ALTERA_DEVICE_FAMILY),
                .rdsync_delaypipe       (ALTERA_SYNC_DEPTH),
                .wrsync_delaypipe       (ALTERA_SYNC_DEPTH),
                .add_usedw_msb_bit      ("ON"),
                .write_aclr_synch       ("OFF")
            ) dcfifo_inst (
                // Write Clock Domain
                .wrclk      (wr_clk),
                .wrreq      (wr_en),
                .data       (wr_data),
                .wrfull     (wr_full),
                .wrempty    (),
                .wrusedw    (wr_data_count[ADDR_WIDTH-1:0]),
                
                // Read Clock Domain  
                .rdclk      (rd_clk),
                .rdreq      (rd_en),
                .q          (rd_data),
                .rdempty    (rd_empty),
                .rdfull     (),
                .rdusedw    (rd_data_count[ADDR_WIDTH-1:0]),
                
                // Asynchronous Clear
                .aclr       (wr_rst | rd_rst),
                
                // Unused ports
                .eccstatus  ()
            );
            
            // For Altera, data_valid needs to be generated
            // In FWFT mode (showahead), data is valid when not empty
            // In standard mode, data is valid after a read (delayed read enable)
            logic rd_en_d;
            always_ff @(posedge rd_clk or posedge rd_rst) begin
                if (rd_rst) begin
                    rd_en_d <= 1'b0;
                end else begin
                    rd_en_d <= rd_en;
                end
            end
            
            assign rd_valid = (FWFT_MODE == 1) ? ~rd_empty : rd_en_d;
            
        end else begin : gen_error
            
            // Generate a compile-time error for unsupported vendor
            initial begin
                $error("Unsupported VENDOR parameter: %s. Must be 'XILINX' or 'ALTERA'/'INTEL'", VENDOR);
            end
            
        end
    endgenerate

endmodule
