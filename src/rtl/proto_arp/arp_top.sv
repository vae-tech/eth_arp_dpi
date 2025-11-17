/*================================================================
  ARP Protocol Top Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-17

    Description:
        This module handles the ARP protocol processing.
        It receives ARP request packets from the Ethernet MAC,
        performs clock domain crossing, and sends reply packets.
        
        Architecture:
        - ARP Parser (RX clock domain)
        - CDC FIFO (RX to TX clock domain crossing)
        - ARP Sender (TX clock domain)

    Version:
        2025-11-17 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

module arp_top #(
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
    // ARP protocol interface and type definitions
    //
    arp_if      arp_proto_if();                                  // ARP protocol interface
    typedef arp_proto_if.proto_frame_t arp_proto_frame_t;        // ARP protocol frame type
    
    //-----------------------------------------------------------------------
    // RX clock domain signals
    //
    arp_proto_frame_t arp_req_pkt;                               // Parsed ARP request packet
    logic             arp_req_pkt_valid;                         // Valid signal for parsed packet
    logic             arp_fifo_full;                             // CDC FIFO full flag
    
    //-----------------------------------------------------------------------
    // TX clock domain signals
    //
    arp_proto_frame_t arp_req_pkt_tx;                            // ARP request packet in TX domain
    logic             arp_req_pkt_valid_tx;                      // Valid signal in TX domain
    logic             arp_req_pkt_tx_ack;                        // Acknowledge to read next packet
    logic             arp_fifo_empty;                            // CDC FIFO empty flag
    logic [7:0]       arp_data_tx;                               // Output data to MAC
    logic             arp_valid_tx;                              // Output valid signal

    //=======================================================================
    // ARP parser
    //=======================================================================
    eth_proto_parser #(
        .T_PROTO_FRAME    (arp_proto_frame_t)
    ) arp_parser_inst (
        .clk              (clk_rx_i),
        .rst              (rst),
        // Protocol interface
        .proto_if         (arp_proto_if),
        // Configuration
        .hw_addr_i        (ether_hw_addr_i),
        .ip_addr_i        (ether_ipv4_addr_i),
        // Input data from Ethernet MAC
        .mac_data_i       (mac_rx_data_i),
        .mac_valid_i      (mac_rx_valid_i),
        // Output ARP packet
        .proto_pkt_o      (arp_req_pkt),
        .proto_pkt_valid_o(arp_req_pkt_valid)
    );
    
    //=======================================================================
    // DC FIFO for clock domain crossing between RX and TX domains
    //=======================================================================
    dc_fifo_wrapper #(
        .VENDOR           ("ALTERA"),
        .DATA_WIDTH       ($bits(arp_proto_frame_t)),
        .FIFO_DEPTH       (FIFO_DEPTH),
        .MEMORY_TYPE      ("distributed")                        // For Altera: USE_EAB=ON
    ) arp_cdc_fifo_inst (
        // Write Clock Domain (RX)
        .wr_clk           (clk_rx_i),
        .wr_rst           (rst),
        .wr_en            (arp_req_pkt_valid && ~arp_fifo_full),
        .wr_data          (arp_req_pkt),
        .wr_full          (arp_fifo_full),
        
        // Read Clock Domain (TX)
        .rd_clk           (clk_tx_i),
        .rd_rst           (rst),
        .rd_en            (arp_req_pkt_tx_ack && ~arp_fifo_empty),
        .rd_data          (arp_req_pkt_tx),
        .rd_empty         (arp_fifo_empty),
        .rd_valid         (arp_req_pkt_valid_tx)
    );

    //=======================================================================
    // ARP sender
    //=======================================================================
    eth_proto_sender #(
        .T_PROTO_FRAME        (arp_proto_frame_t)
    ) arp_sender_i (
        .clk                  (clk_tx_i),
        .rst                  (rst),
        // Protocol interface
        .proto_if             (arp_proto_if),
        // Configuration
        .hw_addr_i            (ether_hw_addr_i),
        .ip_addr_i            (ether_ipv4_addr_i),
        // Input ARP request
        .proto_req_pkt_i      (arp_req_pkt_tx),
        .proto_req_pkt_valid_i(arp_req_pkt_valid_tx),
        .proto_req_pkt_ack_o  (arp_req_pkt_tx_ack),              // 1 clk strobe to get new data from FIFO
        // Output data to Ethernet MAC
        .mac_data_o           (arp_data_tx),
        .mac_valid_o          (arp_valid_tx),
        .mac_ack_i            (mac_tx_ack_i)
    );
    
    //=======================================================================
    // Output assignments
    //=======================================================================
    assign mac_tx_data_o  = arp_data_tx;
    assign mac_tx_valid_o = arp_valid_tx;

endmodule : arp_top