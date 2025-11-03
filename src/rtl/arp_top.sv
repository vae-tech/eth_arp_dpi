/*================================================================
  ARP Top Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This module is used to connect the ARP parser and sender modules.
        It receives the ARP request packet from the Ethernet MAC and sends the ARP reply packet.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

import arp_pkg::*;

module arp_top (
    // Reset and Configuration
    input  logic        ARESET,
    input  logic [47:0] MY_MAC,
    input  logic [31:0] MY_IPV4,
    
    // RX Path (Receive clock domain)
    input  logic        CLK_RX,
    input  logic        DATA_VALID_RX,
    input  logic [7:0]  DATA_RX,
    
    // TX Path (Transmit clock domain)
    input  logic        CLK_TX,
    output logic        DATA_VALID_TX,
    output logic [7:0]  DATA_TX,
    input  logic        DATA_ACK_TX
);


    //=======================================================================
    // Internal Signals
    //=======================================================================
    
    ether_arp_frame_t arp_req_pkt;
    logic             arp_req_pkt_valid;

    // Clock domain crossing signals for ARP request packet
    ether_arp_frame_t arp_req_pkt_tx;
    logic             arp_req_pkt_valid_tx;
    logic             arp_req_pkt_tx_ack;
    logic             fifo_full;
    logic             fifo_empty;
    
    //=======================================================================
    // ARP parser
    //=======================================================================
    arp_parser arp_parser_i (
        .clk              (CLK_RX),
        .rst              (ARESET),
        // Configuration
        .hw_addr_i        (MY_MAC),
        .ip_addr_i        (MY_IPV4),
        // Input data from Ethernet MAC
        .mac_data_i       (DATA_RX),
        .mac_valid_i      (DATA_VALID_RX),
        // Output ARP packet
        .arp_pkt_o        (arp_req_pkt),
        .arp_pkt_valid_o  (arp_req_pkt_valid)
    );
    
    //=======================================================================
    // DC FIFO for clock domain crossing between RX and TX domains
    //=======================================================================

    dc_fifo_wrapper #(
        .VENDOR           ("ALTERA"),
        .DATA_WIDTH       ($bits(ether_arp_frame_t)),
        .FIFO_DEPTH       (16),
        .MEMORY_TYPE      ("distributed") // fir altera USE_EAB=ON
    ) arp_cdc_fifo (
        // Write Clock Domain (RX)
        .wr_clk           (CLK_RX),
        .wr_rst           (ARESET),
        .wr_en            (arp_req_pkt_valid && ~fifo_full),
        .wr_data          (arp_req_pkt),
        .wr_full          (fifo_full),
        
        // Read Clock Domain (TX)
        .rd_clk           (CLK_TX),
        .rd_rst           (ARESET),
        .rd_en            (arp_req_pkt_tx_ack && ~fifo_empty),
        .rd_data          (arp_req_pkt_tx),
        .rd_empty         (fifo_empty),
        .rd_valid         (arp_req_pkt_valid_tx)
    );

    //=======================================================================
    // ARP sender
    //=======================================================================
    arp_sender arp_sender_i (
        .clk                  (CLK_TX),
        .rst                  (ARESET),
        // Configuration
        .hw_addr_i            (MY_MAC),
        .ip_addr_i            (MY_IPV4),
        // Input ARP request
        .arp_req_pkt_i        (arp_req_pkt_tx),
        .arp_req_pkt_valid_i  (arp_req_pkt_valid_tx),
        .arp_req_pkt_ack_o    (arp_req_pkt_tx_ack),    // 1 clk strobe to get new data from FIFO
        // Output data to Ethernet MAC
        .mac_data_o           (DATA_TX),
        .mac_valid_o          (DATA_VALID_TX),
        .mac_ack_i            (DATA_ACK_TX)
    );

endmodule

