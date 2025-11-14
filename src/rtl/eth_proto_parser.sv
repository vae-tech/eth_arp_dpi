

/*================================================================
  Ethernet Protocol Parser Module
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-14

    Description:
        This module is used to parse various Ethernet protocol packets from the Ethernet MAC.
        It validates the protocol frame and outputs the protocol packet if it is valid.

    Version:
        2025-11-14 - 0.1:   - Init
================================================================*/
`timescale 1ns / 1ns

module eth_proto_parser #(
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
    
    // Input data from Ethernet MAC
    input  logic [7:0]   mac_data_i,
    input  logic         mac_valid_i,
    // Output PROTO packet
    output T_PROTO_FRAME proto_pkt_o,
    output logic         proto_pkt_valid_o
);
    
    //=======================================================================
    // Local Parameters and Type Definitions
    //=======================================================================
    
    // Receive state machine states
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_RCV_BYTES,
        ST_CHECK_PROTO
    } state_t;

    // Protocol packet type
    typedef proto_if.proto_frame_t proto_frame_t;
    
    //=======================================================================
    // Internal Signals
    //=======================================================================
       
    // State machine variables
    state_t     state;
    logic [7:0] rcv_byte_cnt;
        
    // Control signals
    logic       valid_d;
    logic       sop;           // Start of packet
    logic       eop;           // End of packet
    logic       proto_frm_ok;  // PROTO frame validation result

    // Received PROTO packet
    proto_frame_t proto_rcv_pkt; 
    // Packet assembly
    logic [$bits(proto_frame_t)-1:0] proto_pkt_raw;


    //=======================================================================
    // Start/End of Packet Detection
    //=======================================================================
    
    assign sop =  mac_valid_i & ~valid_d;
    assign eop = ~mac_valid_i & valid_d;
    
    assign proto_rcv_pkt = proto_frame_t'(proto_pkt_raw);
    
    //=======================================================================
    // PROTO Frame Validation Logic
    //=======================================================================

    assign proto_frm_ok = (state == ST_CHECK_PROTO) && 
                          (proto_if.validate_proto_frame(proto_rcv_pkt, proto_if.proto_ref, hw_addr_i, ip_addr_i) == 1);
     
    //=======================================================================
    // Output Frame Generation
    //=======================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            proto_pkt_o       <= '0;
            proto_pkt_valid_o <= 1'b0;
        end 
        else begin
            if (proto_frm_ok) begin
                proto_pkt_o       <= proto_rcv_pkt;
                proto_pkt_valid_o <= 1'b1;
            end 
            else begin
                proto_pkt_o       <= '0;
                proto_pkt_valid_o <= 1'b0;
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
            proto_pkt_raw  <= '0;
        end 
        else begin
            case (state)
            //===============================================================
            // Wait for new packet
            //===============================================================
                ST_IDLE: begin
                    proto_pkt_raw  <= '0;
                    rcv_byte_cnt <= '0;
                    
                    if (sop) begin
                        state        <= ST_RCV_BYTES;
                        rcv_byte_cnt <= rcv_byte_cnt + 1'b1;
                        proto_pkt_raw  <= (proto_pkt_raw << 8) | mac_data_i;
                    end
                end
                
            //===============================================================
            // Receive bytes from Ethernet MAC until byte 
            // count reaches PROTO frame size
            //===============================================================
                ST_RCV_BYTES: begin
                    rcv_byte_cnt <= rcv_byte_cnt + 1'b1;
                    proto_pkt_raw  <= (proto_pkt_raw << 8) | mac_data_i; // Shift left by 8 bits and add the new byte
                    
                    if (rcv_byte_cnt == proto_if.lp_PROTO_FRM_SZ-1) begin
                        state <= ST_CHECK_PROTO;
                    end
                    else if(eop) begin
                        state <= ST_IDLE;
                        rcv_byte_cnt <= '0;
                        proto_pkt_raw <= '0;
                    end
                end
                
            //===============================================================
            // Check if PROTO frame received
            //===============================================================
                ST_CHECK_PROTO: begin
                    state        <= ST_IDLE;
                    rcv_byte_cnt <= '0;
                    proto_pkt_raw  <= '0;
                end
            //===============================================================
            // Default state
            //===============================================================
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule