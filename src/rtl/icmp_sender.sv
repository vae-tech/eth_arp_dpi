/*================================================================
  ICMP Sender Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-11

    Description:
        This module is used to send the ICMP echo reply packet to the Ethernet MAC.
        It receives the ICMP echo request packet from the parser and sends the ICMP echo reply packet.

    Version:
        2025-11-11 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

import icmp_pkg::*;

module icmp_sender (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst,
    
    // Configuration
    input  logic [47:0] hw_addr_i,
    input  logic [31:0] ip_addr_i,
    
    // Input ICMP request from parser
    input  ether_icmp_frame_t icmp_req_pkt_i,
    input  logic              icmp_req_pkt_valid_i,
    output logic              icmp_req_pkt_ack_o,
    
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
    
    // ICMP reply packet
    ether_icmp_frame_t icmp_reply_pkt;
    logic [$bits(ether_icmp_frame_t)-1:0] icmp_reply_raw;
    
    // Latch the incoming request
    ether_icmp_frame_t icmp_req_latched;
    logic              start_tx;
    
    // Checksum calculation
    logic [15:0] ip_checksum_calc;
    logic [15:0] icmp_checksum_calc;
    logic [15:0] ip_total_length;
    
    //=======================================================================
    // ICMP Reply Packet Generation
    //=======================================================================
    
    always_comb begin : ICMP_MAP
        // Calculate total IP packet length (IP header + ICMP header + data)
        ip_total_length = lp_IP_HDR_SZ + lp_ICMP_HDR_SZ + lp_ICMP_DATA_SZ;
        
        // Calculate IP checksum
        ip_checksum_calc = calc_ip_checksum(
            4'h4,                               // version
            4'h5,                               // ihl (5 * 4 = 20 bytes)
            8'h00,                              // tos
            ip_total_length,                    // total length
            icmp_req_latched.ip_id,             // id (echo back)
            3'b000,                             // flags
            13'h0,                              // fragment offset
            8'h40,                              // ttl (64)
            8'h01,                              // protocol (ICMP)
            ip_addr_i,                          // source IP (our IP)
            icmp_req_latched.ip_src             // destination IP (requester's IP)
        );
        
        // Calculate ICMP checksum (for echo reply)
        icmp_checksum_calc = calc_icmp_checksum(
            8'h00,                              // type (echo reply)
            8'h00,                              // code
            icmp_req_latched.icmp_id,           // id (echo back)
            icmp_req_latched.icmp_seq,          // sequence (echo back)
            icmp_req_latched.icmp_data          // data (echo back)
        );
        
        // Build ICMP reply from the received request
        // Ethernet header
        icmp_reply_pkt.dst_mac    = icmp_req_latched.src_mac;       // Reply to sender
        icmp_reply_pkt.src_mac    = hw_addr_i;                      // Our MAC
        icmp_reply_pkt.ethertype  = 16'h0800;                       // IPv4 EtherType
        
        // IP header
        icmp_reply_pkt.ip_version   = 4'h4;                         // IPv4
        icmp_reply_pkt.ip_ihl       = 4'h5;                         // 5 * 4 = 20 bytes
        icmp_reply_pkt.ip_tos       = 8'h00;                        // Default TOS
        icmp_reply_pkt.ip_length    = ip_total_length;              // Total length
        icmp_reply_pkt.ip_id        = icmp_req_latched.ip_id;       // Echo back ID
        icmp_reply_pkt.ip_flags     = 3'b000;                       // No flags
        icmp_reply_pkt.ip_frag_off  = 13'h0;                        // No fragmentation
        icmp_reply_pkt.ip_ttl       = 8'h40;                        // TTL = 64
        icmp_reply_pkt.ip_protocol  = 8'h01;                        // ICMP
        icmp_reply_pkt.ip_checksum  = ip_checksum_calc;             // Calculated checksum
        icmp_reply_pkt.ip_src       = ip_addr_i;                    // Our IP
        icmp_reply_pkt.ip_dst       = icmp_req_latched.ip_src;      // Requester's IP
        
        // ICMP header
        icmp_reply_pkt.icmp_type     = 8'h00;                       // Echo Reply (0)
        icmp_reply_pkt.icmp_code     = 8'h00;                       // Code 0
        icmp_reply_pkt.icmp_checksum = icmp_checksum_calc;          // Calculated checksum
        icmp_reply_pkt.icmp_id       = icmp_req_latched.icmp_id;    // Echo back ID
        icmp_reply_pkt.icmp_seq      = icmp_req_latched.icmp_seq;   // Echo back sequence
        
        // ICMP data
        icmp_reply_pkt.icmp_data     = icmp_req_latched.icmp_data;  // Echo back data
        
        // Convert to raw bits
        icmp_reply_raw = icmp_reply_pkt;
    end
    
    //=======================================================================
    // Output Data Assignment
    //=======================================================================

    assign icmp_req_pkt_ack_o = (state == ST_IDLE && icmp_req_pkt_valid_i); // 1 clk strobe to get new data from FIFO
    
    // Extract the current byte from the ICMP reply packet - MSB first
    always_comb begin : SHIFT_ICMP_REPLY_BYTES
        int bit_offset;
        bit_offset = ($bits(ether_icmp_frame_t) - 8) - (tx_byte_cnt * 8);
        mac_data_o = icmp_reply_raw[bit_offset +: 8];
    end
    
    //=======================================================================
    // Main Transmit State Machine
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= ST_IDLE;
            tx_byte_cnt      <= '0;
            mac_valid_o      <= 1'b0;
            icmp_req_latched <= '0;
        end 
        else begin
            case (state)
            //===============================================================
            // Wait for new ICMP request
            // To get SRC MAC and IP address
            //===============================================================
                ST_IDLE: begin
                    tx_byte_cnt <= '0;
                    mac_valid_o <= 1'b0;
                    
                    if (icmp_req_pkt_valid_i) begin
                        state             <= ST_WAIT_ACK;
                        tx_byte_cnt       <= '0;
                        mac_valid_o       <= 1'b1;
                        icmp_req_latched  <= icmp_req_pkt_i;
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
            // Send bytes of ICMP reply packet
            //===============================================================
                ST_SEND_BYTES: begin
                    if (mac_valid_o) begin  // If MAC acknowledges or no flow control
                        if (tx_byte_cnt == lp_ICMP_FRM_SZ - 1) begin
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


