

/*================================================================
  Ethernet Protocol Sender Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-17

    Description:
        This module is used to send various Ethernet protocol reply packets to the Ethernet MAC.
        It receives the protocol request packet and sends the appropriate reply packet.

    Version:
        2025-11-17 - 0.1:   - Init
================================================================*/
`timescale 1ns / 1ns

module eth_proto_sender #(
    parameter type T_PROTO_FRAME
) (
    // Clock and Reset
    input  logic         clk,
    input  logic         rst,
    
    // Protocol interface - ARP, ICMP, etc.
    interface            proto_if,

    // Configuration
    input  logic [47:0]  hw_addr_i,
    input  logic [31:0]  ip_addr_i,
    
    // Input protocol request from parser
    input  T_PROTO_FRAME proto_req_pkt_i,
    input  logic         proto_req_pkt_valid_i,
    output logic         proto_req_pkt_ack_o,
    
    // Output data to Ethernet MAC
    output logic [7:0]   mac_data_o,
    output logic         mac_valid_o,
    input  logic         mac_ack_i         
);

    //=======================================================================
    // Local Parameters and Type Definitions
    //=======================================================================
    
    // Transmit state machine states
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_ACK,
        ST_SEND_BYTES,
        ST_DONE
    } state_t;

    // Protocol packet type
    typedef proto_if.proto_frame_t proto_frame_t;
    
    
    //=======================================================================
    // Internal Signals
    //=======================================================================
    
    // State machine variables
    state_t     state;
    logic [7:0] tx_byte_cnt;
    
    // Protocol reply packet
    proto_frame_t proto_reply_pkt;
    logic [$bits(proto_frame_t)-1:0] proto_reply_raw;
    
    // Latch the incoming request
    proto_frame_t proto_req_latched;
    
    //=======================================================================
    // Protocol Reply Packet Generation
    //=======================================================================
    
    always_comb begin : PROTO_REPLY_MAP
        // Build protocol reply from the received request using interface function
        proto_reply_pkt = proto_if.build_reply_pkt(proto_req_latched, hw_addr_i, ip_addr_i);
        
        // Convert to raw bits
        proto_reply_raw = proto_reply_pkt;
    end
    
    //=======================================================================
    // Output Data Assignment
    //=======================================================================

    assign proto_req_pkt_ack_o = (state == ST_IDLE && proto_req_pkt_valid_i); // 1 clk strobe to get new data from FIFO
    
    // Extract the current byte from the protocol reply packet - MSB first
    always_comb begin : SHIFT_PROTO_REPLY_BYTES
        int bit_offset;
        bit_offset = ($bits(proto_frame_t) - 8) - (tx_byte_cnt * 8);
        mac_data_o = proto_reply_raw[bit_offset +: 8];
    end
    
    //=======================================================================
    // Main Transmit State Machine
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= ST_IDLE;
            tx_byte_cnt       <= '0;
            mac_valid_o       <= 1'b0;
            proto_req_latched <= '0;
        end 
        else begin
            case (state)
            //===============================================================
            // Wait for new protocol request
            //===============================================================
                ST_IDLE: begin
                    tx_byte_cnt <= '0;
                    mac_valid_o <= 1'b0;
                    
                    if (proto_req_pkt_valid_i) begin
                        state             <= ST_WAIT_ACK;
                        tx_byte_cnt       <= '0;
                        mac_valid_o       <= 1'b1;
                        proto_req_latched <= proto_req_pkt_i;
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
            // Send bytes of protocol reply packet
            //===============================================================
                ST_SEND_BYTES: begin
                    if (mac_valid_o) begin  
                        if (tx_byte_cnt == proto_if.lp_PROTO_FRM_SZ - 1) begin
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

