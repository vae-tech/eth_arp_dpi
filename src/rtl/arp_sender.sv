/*================================================================
  ARP Sender Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This module is used to send the ARP reply packet to the Ethernet MAC.
        It receives the ARP request packet from the parser and sends the ARP reply packet.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

import arp_pkg::*;

module arp_sender (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst,
    
    // Configuration
    input  logic [47:0] hw_addr_i,
    input  logic [31:0] ip_addr_i,
    
    // Input ARP request from parser
    input  ether_arp_frame_t arp_req_pkt_i,
    input  logic             arp_req_pkt_valid_i,
    output logic             arp_req_pkt_ack_o,
    
    // Output data to Ethernet MAC
    output logic [7:0]  mac_data_o,
    output logic        mac_valid_o,
    input  logic        mac_ack_i         
);

    //=======================================================================
    // Local Parameters and Type Definitions
    //=======================================================================
    
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_ACK,
        ST_SEND_BYTES,
        ST_DONE
    } state_t;
    
    
    //=======================================================================
    // Internal Signals
    //=======================================================================
    
    // State machine variables
    state_t state;
    logic [7:0] tx_byte_cnt;
    
    // ARP reply packet
    ether_arp_frame_t arp_reply_pkt;
    logic [$bits(ether_arp_frame_t)-1:0] arp_reply_raw;
    
    // Latch the incoming request
    ether_arp_frame_t arp_req_latched;
    logic             start_tx;
    
    //=======================================================================
    // ARP Reply Packet Generation
    //=======================================================================
    
    always_comb begin : ARP_MAP
        // Build ARP reply from the received request
        arp_reply_pkt.dst_mac    = arp_req_latched.src_mac;       // Reply to sender
        arp_reply_pkt.src_mac    = hw_addr_i;                     // Our MAC
        arp_reply_pkt.ethertype  = 16'h0806;                      // ARP EtherType
        arp_reply_pkt.hw_type    = 16'h0001;                      // Ethernet
        arp_reply_pkt.proto_type = 16'h0800;                      // IPv4
        arp_reply_pkt.hw_len     = 8'h06;                         // MAC address length
        arp_reply_pkt.proto_len  = 8'h04;                         // IP address length
        arp_reply_pkt.opcode     = 16'h0002;                      // ARP Reply (2)
        arp_reply_pkt.sender_mac = hw_addr_i;                     // Our MAC
        arp_reply_pkt.sender_ip  = ip_addr_i;                     // Our IP
        arp_reply_pkt.target_mac = arp_req_latched.sender_mac;    // Requester's MAC
        arp_reply_pkt.target_ip  = arp_req_latched.sender_ip;     // Requester's IP
        
        // Convert to raw bits
        arp_reply_raw = arp_reply_pkt;
    end
    
    //=======================================================================
    // Output Data Assignment
    //=======================================================================

    assign arp_req_pkt_ack_o = (state == ST_IDLE && arp_req_pkt_valid_i); // 1 clk strobe to get new data from FIFO
    
    // Extract the current byte from the ARP reply packet - MSB first
    always_comb begin : SHIFT_ARP_REPLY_BYTES
        int bit_offset;
        bit_offset = ($bits(ether_arp_frame_t) - 8) - (tx_byte_cnt * 8);
        mac_data_o = arp_reply_raw[bit_offset +: 8];
    end
    
    //=======================================================================
    // Main Transmit State Machine
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= ST_IDLE;
            tx_byte_cnt     <= '0;
            mac_valid_o     <= 1'b0;
            arp_req_latched <= '0;
        end 
        else begin
            case (state)
            //===============================================================
            // Wait for new ARP request
            // To get SRC MAC and IP address
            //===============================================================
                ST_IDLE: begin
                    tx_byte_cnt <= '0;
                    mac_valid_o <= 1'b0;
                    
                    if (arp_req_pkt_valid_i) begin
                        state             <= ST_WAIT_ACK;
                        tx_byte_cnt       <= '0;
                        mac_valid_o       <= 1'b1;
                        arp_req_latched   <= arp_req_pkt_i;
                    end
                end

            //===============================================================
            // Wait for ack from MAC
            //===============================================================
                ST_WAIT_ACK: begin
                    if (mac_ack_i && mac_valid_o) begin
                        state <= ST_SEND_BYTES;
                        tx_byte_cnt <= tx_byte_cnt + 1'b1;
                    end
                end
                
            //===============================================================
            // Send bytes of ARP reply packet
            //===============================================================
                ST_SEND_BYTES: begin
                    if (mac_valid_o) begin  // If MAC acknowledges or no flow control
                        if (tx_byte_cnt == lp_ARP_FRM_SZ - 1) begin
                            state       <= ST_IDLE;
                            mac_valid_o <= 1'b0;
                            tx_byte_cnt <= '0;
                        end 
                        else begin
                            tx_byte_cnt <= tx_byte_cnt + 1'b1;
                            mac_valid_o <= 1'b1;
                        end
                    end
                end
                
            //===============================================================
            // Default state
            //===============================================================
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

