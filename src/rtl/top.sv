/*================================================================
  Ethernet Protocol Top Module (ARP + ICMP)
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This module handles both ARP and ICMP protocols.
        It receives ARP and ICMP request packets from the Ethernet MAC 
        and sends the appropriate reply packets through a TX mux.

    Version:
        2025-11-06 - 0.1:   - Init
        2025-11-11 - 0.2:   - Added ICMP support and TX mux
================================================================*/

`timescale 1ns / 1ns

// import arp_pkg::*;
// import icmp_pkg::*;

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

    //-----------------------------------------------------------------------
    // ARP protocol interface
    //
    arp_if      arp_proto_if(); // ARP protocol interface
    typedef arp_proto_if.proto_frame_t arp_proto_frame_t; // ARP protocol frame type

    arp_proto_frame_t arp_req_pkt;
    logic             arp_req_pkt_valid;
    // CDC ARP
    arp_proto_frame_t arp_req_pkt_tx;
    logic             arp_req_pkt_valid_tx;
    logic             arp_req_pkt_tx_ack;
    logic             arp_fifo_full;
    logic             arp_fifo_empty;
    
    //-----------------------------------------------------------------------
    // ICMP protocol interface
    //
    icmp_if            icmp_proto_if(); // ICMP protocol interface
    typedef icmp_proto_if.proto_frame_t icmp_proto_frame_t; // ICMP protocol frame type
    icmp_proto_frame_t icmp_req_pkt;
    logic              icmp_req_pkt_valid;
    // CDC ICMP
    logic              icmp_req_pkt_valid_tx;
    logic              icmp_req_pkt_tx_ack;
    logic              icmp_fifo_full;
    logic              icmp_fifo_empty;
    
    //-----------------------------------------------------------------------
    // TX Mux signals
    //
    logic [7:0]  arp_data_tx;
    logic        arp_valid_tx;
    logic        arp_ack_tx;
    logic [7:0]  icmp_data_tx;
    logic        icmp_valid_tx;
    logic        icmp_ack_tx;

        
    //=======================================================================
    // ARP parser
    //=======================================================================
    eth_proto_parser #(
        .T_PROTO_FRAME    (arp_proto_frame_t)
    ) arp_parser_i (
        .clk              (CLK_RX),
        .rst              (ARESET),
        // Protocol interface
        .proto_if         (arp_proto_if),
        // Configuration
        .hw_addr_i        (MY_MAC),
        .ip_addr_i        (MY_IPV4),
        // Input data from Ethernet MAC
        .mac_data_i       (DATA_RX),
        .mac_valid_i      (DATA_VALID_RX),
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
        .FIFO_DEPTH       (16),
        .MEMORY_TYPE      ("distributed") // fir altera USE_EAB=ON
    ) arp_cdc_fifo (
        // Write Clock Domain (RX)
        .wr_clk           (CLK_RX),
        .wr_rst           (ARESET),
        .wr_en            (arp_req_pkt_valid && ~arp_fifo_full),
        .wr_data          (arp_req_pkt),
        .wr_full          (arp_fifo_full),
        
        // Read Clock Domain (TX)
        .rd_clk           (CLK_TX),
        .rd_rst           (ARESET),
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
        .clk                  (CLK_TX),
        .rst                  (ARESET),
        // Protocol interface
        .proto_if             (arp_proto_if),
        // Configuration
        .hw_addr_i            (MY_MAC),
        .ip_addr_i            (MY_IPV4),
        // Input ARP request
        .proto_req_pkt_i      (arp_req_pkt_tx),
        .proto_req_pkt_valid_i(arp_req_pkt_valid_tx),
        .proto_req_pkt_ack_o  (arp_req_pkt_tx_ack),    // 1 clk strobe to get new data from FIFO
        // Output data to Ethernet MAC
        .mac_data_o           (arp_data_tx),
        .mac_valid_o          (arp_valid_tx),
        .mac_ack_i            (DATA_ACK_TX)
    );
    
    //=======================================================================
    // ICMP parser
    //=======================================================================
    eth_proto_parser #(
        .T_PROTO_FRAME    (icmp_proto_frame_t)
    ) icmp_parser_i (
        // Clock and Reset
        .clk              (CLK_RX),
        .rst              (ARESET),
        // Protocol interface
        .proto_if         (icmp_proto_if),
        // Configuration
        .hw_addr_i        (MY_MAC),
        .ip_addr_i        (MY_IPV4),
        // Input data from Ethernet MAC
        .mac_data_i       (DATA_RX),
        .mac_valid_i      (DATA_VALID_RX),
        // Output ICMP packet
        .proto_pkt_o      (icmp_req_pkt),
        .proto_pkt_valid_o(icmp_req_pkt_valid)
    );
    
    //=======================================================================
    // DC FIFO for ICMP clock domain crossing between RX and TX domains
    //=======================================================================
    dc_fifo_wrapper #(
        .VENDOR           ("ALTERA"),
        .DATA_WIDTH       ($bits(icmp_proto_frame_t)),
        .FIFO_DEPTH       (16),
        .MEMORY_TYPE      ("distributed") // fir altera USE_EAB=ON
    ) icmp_cdc_fifo (
        // Write Clock Domain (RX)
        .wr_clk           (CLK_RX),
        .wr_rst           (ARESET),
        .wr_en            (icmp_req_pkt_valid && ~icmp_fifo_full),
        .wr_data          (icmp_req_pkt),
        .wr_full          (icmp_fifo_full),
        
        // Read Clock Domain (TX)
        .rd_clk           (CLK_TX),
        .rd_rst           (ARESET),
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
    ) icmp_sender_i (
        .clk                  (CLK_TX),
        .rst                  (ARESET),
        // Protocol interface
        .proto_if             (icmp_proto_if),
        // Configuration
        .hw_addr_i            (MY_MAC),
        .ip_addr_i            (MY_IPV4),
        // Input ICMP request
        .proto_req_pkt_i      (icmp_req_pkt_tx),
        .proto_req_pkt_valid_i(icmp_req_pkt_valid_tx),
        .proto_req_pkt_ack_o  (icmp_req_pkt_tx_ack),
        // Output data to Ethernet MAC
        .mac_data_o           (icmp_data_tx),
        .mac_valid_o          (icmp_valid_tx),
        .mac_ack_i            (DATA_ACK_TX)
    );
    
    //=======================================================================
    // TX Mux - Arbitrate between ARP and ICMP transmitters
    //=======================================================================
    // Priority: ARP > ICMP
    // Simple mux that forwards whichever protocol has valid data
    // If both are valid simultaneously, ARP takes priority
    
    always_comb begin
        if (icmp_valid_tx) begin
            // ICMP when ARP is not transmitting
            DATA_TX       = icmp_data_tx;
            DATA_VALID_TX = icmp_valid_tx;
            arp_ack_tx    = 1'b0;
            icmp_ack_tx   = DATA_ACK_TX;
        end
        else if (arp_valid_tx) begin
            // ARP has priority
            DATA_TX       = arp_data_tx;
            DATA_VALID_TX = arp_valid_tx;
            arp_ack_tx    = DATA_ACK_TX;
            icmp_ack_tx   = 1'b0;
        end
        else begin
            DATA_TX       = 8'h00;
            DATA_VALID_TX = 1'b0;
            arp_ack_tx    = 1'b0;
            icmp_ack_tx   = 1'b0;
        end
        
    end

endmodule

