/*================================================================
  ARP Package
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This package contains the definitions for the ARP protocol.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

interface arp_if;

    // Complete Ethernet ARP frame structure
    typedef struct packed {
        logic [47:0] dst_mac;      // Destination MAC address
        logic [47:0] src_mac;      // Source MAC address
        logic [15:0] ethertype;    // EtherType (ARP = 0x0806)
        logic [15:0] hw_type;      // Hardware type (Ethernet = 0x0001)
        logic [15:0] proto_type;   // Protocol type (IPv4 = 0x0800)
        logic [7:0]  hw_len;       // Hardware address length (6 for MAC)
        logic [7:0]  proto_len;    // Protocol address length (4 for IPv4)
        logic [15:0] opcode;       // Operation code (1=request, 2=reply)
        logic [47:0] sender_mac;   // Sender hardware address (MAC)
        logic [31:0] sender_ip;    // Sender protocol address (IP)
        logic [47:0] target_mac;   // Target hardware address (MAC)
        logic [31:0] target_ip;    // Target protocol address (IP)
    } proto_frame_t;

    const proto_frame_t proto_ref = '{
        dst_mac     : 48'h0,
        src_mac     : 48'h0,
        ethertype   : 16'h0806,
        hw_type     : 16'h0001,
        proto_type  : 16'h0800,
        hw_len      : 8'h06,
        proto_len   : 8'h04,
        opcode      : 16'h1,
        sender_mac  : 48'h0,
        sender_ip   : 32'h0,
        target_mac  : 48'h0,
        target_ip   : 32'h0
    };

    localparam int    lp_PROTO_FRM_SZ = $bits(proto_frame_t)/8; // Size in bytes
    localparam logic [47:0] lp_BROADCAST_MAC = 48'hFFFFFFFFFFFF; // Broadcast MAC address

    //=======================================================================
    // Helper Functions
    //=======================================================================

    //-----------------------------------------------------------------------
    // Validate ARP frame
    //  
    function int validate_proto_frame(
            input proto_frame_t arp_lhs,
            input proto_frame_t arp_rhs,
            input logic [47:0] mac_addr_i,
            input logic [31:0] ip_addr_i
        );

        if (arp_lhs.dst_mac != mac_addr_i && arp_lhs.dst_mac != lp_BROADCAST_MAC) begin
            return -1; // Not for us
        end
        else if (arp_lhs.src_mac == mac_addr_i) begin
            return -2; // Echo protection
        end
        else if (arp_lhs.ethertype != arp_rhs.ethertype) begin
            return -3; // Wrong EtherType
        end
        else if (arp_lhs.hw_type != arp_rhs.hw_type) begin
            return -4; // Wrong hardware type
        end
        else if (arp_lhs.proto_type != arp_rhs.proto_type) begin
            return -5; // Wrong protocol type
        end
        else if (arp_lhs.hw_len != arp_rhs.hw_len) begin
            return -6; // Wrong hardware length
        end
        else if (arp_lhs.proto_len != arp_rhs.proto_len) begin
            return -7; // Wrong protocol length
        end
        else if (arp_lhs.opcode != arp_rhs.opcode) begin
            return -8; // Wrong opcode
        end
        else if (arp_lhs.target_ip != ip_addr_i) begin
            return -9; // Not requesting our IP
        end
        else begin
            return 1; // Valid ARP request
        end
    endfunction

    //-----------------------------------------------------------------------
    // Build ARP reply packet from request
    //  
    function proto_frame_t build_reply_pkt(
            input proto_frame_t req_pkt,
            input logic [47:0] hw_addr_i,
            input logic [31:0] ip_addr_i
        );
        
        proto_frame_t reply_pkt;
        
        // Build ARP reply from the received request
        reply_pkt.dst_mac    = req_pkt.src_mac;       // Reply to sender
        reply_pkt.src_mac    = hw_addr_i;             // Our MAC
        reply_pkt.ethertype  = 16'h0806;              // ARP EtherType
        reply_pkt.hw_type    = 16'h0001;              // Ethernet
        reply_pkt.proto_type = 16'h0800;              // IPv4
        reply_pkt.hw_len     = 8'h06;                 // MAC address length
        reply_pkt.proto_len  = 8'h04;                 // IP address length
        reply_pkt.opcode     = 16'h0002;              // ARP Reply (2)
        reply_pkt.sender_mac = hw_addr_i;             // Our MAC
        reply_pkt.sender_ip  = ip_addr_i;             // Our IP
        reply_pkt.target_mac = req_pkt.sender_mac;    // Requester's MAC
        reply_pkt.target_ip  = req_pkt.sender_ip;     // Requester's IP
        
        return reply_pkt;
    endfunction

endinterface : arp_if
