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

module eth_proto_top (
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
   
    logic [7:0]  arp_data_tx;
    logic        arp_valid_tx;
    logic        arp_ack_tx;
    //
    logic [7:0]  icmp_data_tx;
    logic        icmp_valid_tx;
    logic        icmp_ack_tx;

    //=======================================================================
    // ARP Protocol Instance
    //=======================================================================
    arp_top #(
        .FIFO_DEPTH(16)
    ) arp_top_inst (
        // Reset and Configuration
        .rst               (ARESET),
        .ether_hw_addr_i   (MY_MAC),
        .ether_ipv4_addr_i (MY_IPV4),
        
        // RX Path (Receive clock domain)
        .clk_rx_i          (CLK_RX),
        .mac_rx_valid_i    (DATA_VALID_RX),
        .mac_rx_data_i     (DATA_RX),
        
        // TX Path (Transmit clock domain)
        .clk_tx_i          (CLK_TX),
        .mac_tx_valid_o    (arp_valid_tx),
        .mac_tx_data_o     (arp_data_tx),
        .mac_tx_ack_i      (arp_ack_tx)
    );
    
    //=======================================================================
    // ICMP Protocol Instance
    //=======================================================================
    icmp_top #(
        .FIFO_DEPTH(16)
    ) icmp_top_inst (
        // Reset and Configuration
        .rst               (ARESET),
        .ether_hw_addr_i   (MY_MAC),
        .ether_ipv4_addr_i (MY_IPV4),
        
        // RX Path (Receive clock domain)
        .clk_rx_i          (CLK_RX),
        .mac_rx_valid_i    (DATA_VALID_RX),
        .mac_rx_data_i     (DATA_RX),
        
        // TX Path (Transmit clock domain)
        .clk_tx_i          (CLK_TX),
        .mac_tx_valid_o    (icmp_valid_tx),
        .mac_tx_data_o     (icmp_data_tx),
        .mac_tx_ack_i      (icmp_ack_tx)
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

endmodule : eth_proto_top

