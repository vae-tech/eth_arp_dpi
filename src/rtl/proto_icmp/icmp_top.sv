/*================================================================
  ICMP Protocol Top Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-17

    Description:
        This module handles the ICMP protocol processing (ping).
        It receives ICMP echo request packets from the Ethernet MAC,
        performs clock domain crossing, and sends echo reply packets.
        
        Architecture:
        - ICMP Parser (RX clock domain)
        - CDC FIFO (RX to TX clock domain crossing)
        - ICMP Sender (TX clock domain)

    Version:
        2025-11-17 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

module icmp_top #(
    parameter FIFO_DEPTH = 16)
(
    // Reset and Configuration
    input  logic        rst,
    input  logic [47:0] ether_hw_addr_i,
    input  logic [31:0] ether_ipv4_addr_i,
    
    // RX Path (Receive clock domain)
    input  logic        clk_rx_i,
    input  logic        mac_rx_valid_i,
    input  logic [7:0]  mac_rx_data_i,
    
    // TX Path (Transmit clock domain)
    input  logic        clk_tx_i,
    output logic        mac_tx_valid_o,
    output logic [7:0]  mac_tx_data_o,
    input  logic        mac_tx_ack_i
);

    //=======================================================================
    // Internal Signals
    //=======================================================================
    
    //-----------------------------------------------------------------------
    // ICMP protocol interface and type definitions
    //
    icmp_if     icmp_proto_if();                                 // ICMP protocol interface
    typedef icmp_proto_if.proto_frame_t icmp_proto_frame_t;      // ICMP protocol frame type
    
    //-----------------------------------------------------------------------
    // RX clock domain signals
    //
    icmp_proto_frame_t icmp_req_pkt;                             // Parsed ICMP request packet
    logic              icmp_req_pkt_valid;                       // Valid signal for parsed packet
    logic              icmp_fifo_full;                           // CDC FIFO full flag
    
    //-----------------------------------------------------------------------
    // TX clock domain signals
    //
    icmp_proto_frame_t icmp_req_pkt_tx;                          // ICMP request packet in TX domain
    logic              icmp_req_pkt_valid_tx;                    // Valid signal in TX domain
    logic              icmp_req_pkt_tx_ack;                      // Acknowledge to read next packet
    logic              icmp_fifo_empty;                          // CDC FIFO empty flag
    logic [7:0]        icmp_data_tx;                             // Output data to MAC
    logic              icmp_valid_tx;                            // Output valid signal

    //=======================================================================
    // ICMP parser
    //=======================================================================
    eth_proto_parser #(
        .T_PROTO_FRAME    (icmp_proto_frame_t)
    ) icmp_parser_inst (
        // Clock and Reset
        .clk              (clk_rx_i),
        .rst              (rst),
        // Protocol interface
        .proto_if         (icmp_proto_if),
        // Configuration
        .hw_addr_i        (ether_hw_addr_i),
        .ip_addr_i        (ether_ipv4_addr_i),
        // Input data from Ethernet MAC
        .mac_data_i       (mac_rx_data_i),
        .mac_valid_i      (mac_rx_valid_i),
        // Output ICMP packet
        .proto_pkt_o      (icmp_req_pkt),
        .proto_pkt_valid_o(icmp_req_pkt_valid)
    );
    
    //=======================================================================
    // DC FIFO for clock domain crossing between RX and TX domains
    //=======================================================================
    dc_fifo_wrapper #(
        .VENDOR           ("ALTERA"),
        .DATA_WIDTH       ($bits(icmp_proto_frame_t)),
        .FIFO_DEPTH       (FIFO_DEPTH),
        .MEMORY_TYPE      ("distributed")                        // For Altera: USE_EAB=ON
    ) icmp_cdc_fifo_inst (
        // Write Clock Domain (RX)
        .wr_clk           (clk_rx_i),
        .wr_rst           (rst),
        .wr_en            (icmp_req_pkt_valid && ~icmp_fifo_full),
        .wr_data          (icmp_req_pkt),
        .wr_full          (icmp_fifo_full),
        
        // Read Clock Domain (TX)
        .rd_clk           (clk_tx_i),
        .rd_rst           (rst),
        .rd_en            (icmp_req_pkt_tx_ack && ~icmp_fifo_empty),
        .rd_data          (icmp_req_pkt_tx),
        .rd_empty         (icmp_fifo_empty),
        .rd_valid         (icmp_req_pkt_valid_tx)
    );
    
    //=======================================================================
    // ICMP sender
    //=======================================================================
    eth_proto_sender #(
        .T_PROTO_FRAME    (icmp_proto_frame_t)
    ) icmp_sender_inst (
        .clk                  (clk_tx_i),
        .rst                  (rst),
        // Protocol interface
        .proto_if             (icmp_proto_if),
        // Configuration
        .hw_addr_i            (ether_hw_addr_i),
        .ip_addr_i            (ether_ipv4_addr_i),
        // Input ICMP request
        .proto_req_pkt_i      (icmp_req_pkt_tx),
        .proto_req_pkt_valid_i(icmp_req_pkt_valid_tx),
        .proto_req_pkt_ack_o  (icmp_req_pkt_tx_ack),             // 1 clk strobe to get new data from FIFO
        // Output data to Ethernet MAC
        .mac_data_o           (icmp_data_tx),
        .mac_valid_o          (icmp_valid_tx),
        .mac_ack_i            (mac_tx_ack_i)
    );
    
    //=======================================================================
    // Output assignments
    //=======================================================================
    assign mac_tx_data_o  = icmp_data_tx;
    assign mac_tx_valid_o = icmp_valid_tx;

endmodule : icmp_top