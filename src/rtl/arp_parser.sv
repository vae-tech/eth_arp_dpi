/*================================================================
  ARP Parser Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This module is used to parse the ARP packet from the Ethernet MAC.
        It validates the ARP frame and outputs the ARP packet if it is valid.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

import arp_pkg::*;

module arp_parser (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst,
    
    // Configuration
    input  logic [47:0] hw_addr_i,
    input  logic [31:0] ip_addr_i,
    
    // Input data from Ethernet MAC
    input  logic [7:0]  mac_data_i,
    input  logic        mac_valid_i,
    
    // Output ARP packet
    output ether_arp_frame_t arp_pkt_o,
    output logic             arp_pkt_valid_o
);

    //=======================================================================
    // Local Parameters and Type Definitions
    //=======================================================================
    
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_RCV_BYTES,
        ST_CHECK_ARP
    } state_t;
    
    //=======================================================================
    // Internal Signals
    //=======================================================================
    
    // State machine variables
    state_t state;
    logic [7:0] rcv_byte_cnt;
    
    // Packet assembly
    logic [$bits(ether_arp_frame_t)-1:0] arp_pkt_raw;
    ether_arp_frame_t arp_req_pkt;
    
    // Control signals
    logic valid_d;
    logic sop;                     // Start of packet
    logic eop;                     // End of packet               // End of packet
    logic arp_frm_ok;              // ARP frame validation result
    
    //=======================================================================
    // Start/End of Packet Detection
    //=======================================================================
    
    assign sop =  mac_valid_i & ~valid_d;
    assign eop = ~mac_valid_i & valid_d;
    
    assign arp_req_pkt = ether_arp_frame_t'(arp_pkt_raw);
    
    //=======================================================================
    // ARP Frame Validation Logic
    //=======================================================================

    assign arp_frm_ok = state == ST_CHECK_ARP && validate_arp_frame(arp_req_pkt, arp_req_ref, hw_addr_i, ip_addr_i);
     
    //=======================================================================
    // Output Frame Generation
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            arp_pkt_o       <= '0;
            arp_pkt_valid_o <= 1'b0;
        end 
        else begin
            if (arp_frm_ok) begin
                arp_pkt_o       <= arp_req_pkt;
                arp_pkt_valid_o <= 1'b1;
            end 
            else begin
                arp_pkt_o       <= '0;
                arp_pkt_valid_o <= 1'b0;
            end
        end
    end
    
    //=======================================================================
    // Valid Delay Register
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_d <= 1'b0;
        end 
        else begin
            valid_d <= mac_valid_i;
        end
    end
    
    //=======================================================================
    // Main Receive State Machine
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= ST_IDLE;
            rcv_byte_cnt <= '0;
            arp_pkt_raw  <= '0;
        end 
        else begin
            case (state)
            //===============================================================
            // Wait for new packet
            //===============================================================
                ST_IDLE: begin
                    arp_pkt_raw  <= '0;
                    rcv_byte_cnt <= '0;
                    
                    if (sop) begin
                        state        <= ST_RCV_BYTES;
                        rcv_byte_cnt <= rcv_byte_cnt + 1'b1;
                        arp_pkt_raw  <= (arp_pkt_raw << 8) | mac_data_i;
                    end
                end
                
            //===============================================================
            // Receive bytes from Ethernet MAC until byte 
            // count reaches ARP frame size
            //===============================================================
                ST_RCV_BYTES: begin
                    rcv_byte_cnt <= rcv_byte_cnt + 1'b1;
                    arp_pkt_raw  <= (arp_pkt_raw << 8) | mac_data_i; // Shift left by 8 bits and add the new byte
                    
                    if (rcv_byte_cnt == lp_ARP_FRM_SZ-1) begin
                        state <= ST_CHECK_ARP;
                    end
                end
                
            //===============================================================
            // Check if ARP frame received
            //===============================================================
                ST_CHECK_ARP: begin
                    state        <= ST_IDLE;
                    rcv_byte_cnt <= '0;
                    arp_pkt_raw  <= '0;
                end
            //===============================================================
            // Default state
            //===============================================================
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule