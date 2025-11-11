/*================================================================
  ICMP Package
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-11

    Description:
        This package contains the definitions for the ICMP protocol.

    Version:
        2025-11-11 - 0.1:   - Init
================================================================*/

package icmp_pkg;

    // Complete Ethernet + IP + ICMP frame structure
    typedef struct packed {
        // Ethernet header (14 bytes)
        logic [47:0] dst_mac;       // Destination MAC address
        logic [47:0] src_mac;       // Source MAC address
        logic [15:0] ethertype;     // EtherType (IPv4 = 0x0800)
        
        // IPv4 header (20 bytes - minimum, no options)
        logic [3:0]  ip_version;    // IP version (4)
        logic [3:0]  ip_ihl;        // Internet Header Length (5 for 20 bytes)
        logic [7:0]  ip_tos;        // Type of Service
        logic [15:0] ip_length;     // Total Length
        logic [15:0] ip_id;         // Identification
        logic [2:0]  ip_flags;      // Flags
        logic [12:0] ip_frag_off;   // Fragment offset
        logic [7:0]  ip_ttl;        // Time to Live
        logic [7:0]  ip_protocol;   // Protocol (ICMP = 1)
        logic [15:0] ip_checksum;   // Header checksum
        logic [31:0] ip_src;        // Source IP address
        logic [31:0] ip_dst;        // Destination IP address
        
        // ICMP header (8 bytes)
        logic [7:0]  icmp_type;     // ICMP type (8=echo request, 0=echo reply)
        logic [7:0]  icmp_code;     // ICMP code (0 for echo)
        logic [15:0] icmp_checksum; // ICMP checksum
        logic [15:0] icmp_id;       // Identifier
        logic [15:0] icmp_seq;      // Sequence number
        
        // ICMP data (56 bytes payload for standard ping)
        logic [447:0] icmp_data;    // Data payload
    } ether_icmp_frame_t;

    const ether_icmp_frame_t icmp_req_ref = '{
        dst_mac       : 48'h0,
        src_mac       : 48'h0,
        ethertype     : 16'h0800,
        ip_version    : 4'h4,
        ip_ihl        : 4'h5,
        ip_tos        : 8'h0,
        ip_length     : 16'h0,
        ip_id         : 16'h0,
        ip_flags      : 3'b010,    // Don't fragment
        ip_frag_off   : 13'h0,
        ip_ttl        : 8'h40,     // 64 hops
        ip_protocol   : 8'h01,     // ICMP
        ip_checksum   : 16'h0,
        ip_src        : 32'h0,
        ip_dst        : 32'h0,
        icmp_type     : 8'h08,     // Echo request
        icmp_code     : 8'h00,
        icmp_checksum : 16'h0,
        icmp_id       : 16'h0,
        icmp_seq      : 16'h0,
        icmp_data     : 448'h0
    };

    localparam int    lp_ICMP_FRM_SZ = $bits(ether_icmp_frame_t)/8; // Size in bytes (98)
    localparam int    lp_IP_HDR_SZ   = 20;                           // IP header size in bytes
    localparam int    lp_ICMP_HDR_SZ = 8;                            // ICMP header size in bytes
    localparam int    lp_ICMP_DATA_SZ = 56;                          // ICMP data size in bytes

    //=======================================================================
    // Helper Functions
    //=======================================================================

    // Calculate IP header checksum
    function logic [15:0] calc_ip_checksum(
            input logic [3:0]  version,
            input logic [3:0]  ihl,
            input logic [7:0]  tos,
            input logic [15:0] length,
            input logic [15:0] id,
            input logic [2:0]  flags,
            input logic [12:0] frag_off,
            input logic [7:0]  ttl,
            input logic [7:0]  protocol,
            input logic [31:0] src_ip,
            input logic [31:0] dst_ip
        );
        
        logic [31:0] sum;
        logic [15:0] checksum;
        
        // Add all 16-bit words
        sum = {version, ihl, tos} + length + id + {flags, frag_off} + 
              {ttl, protocol} + src_ip[31:16] + src_ip[15:0] + 
              dst_ip[31:16] + dst_ip[15:0];
        
        // Add carry bits
        sum = (sum & 16'hFFFF) + (sum >> 16);
        sum = (sum & 16'hFFFF) + (sum >> 16);
        
        // One's complement
        checksum = ~sum[15:0];
        return checksum;
    endfunction

    // Calculate ICMP checksum
    function logic [15:0] calc_icmp_checksum(
            input logic [7:0]   icmp_type,
            input logic [7:0]   icmp_code,
            input logic [15:0]  icmp_id,
            input logic [15:0]  icmp_seq,
            input logic [447:0] icmp_data
        );
        
        logic [31:0] sum;
        logic [15:0] checksum;
        int i;
        
        // Add type and code
        sum = {icmp_type, icmp_code};
        
        // Add ID and sequence
        sum = sum + icmp_id + icmp_seq;
        
        // Add data (28 16-bit words for 56 bytes)
        for (i = 0; i < 28; i++) begin
            sum = sum + icmp_data[(447 - i*16) -: 16];
        end
        
        // Add carry bits
        sum = (sum & 16'hFFFF) + (sum >> 16);
        sum = (sum & 16'hFFFF) + (sum >> 16);
        
        // One's complement
        checksum = ~sum[15:0];
        return checksum;
    endfunction

    function int validate_icmp_frame(
            input ether_icmp_frame_t icmp_lhs,
            input ether_icmp_frame_t icmp_rhs,
            input logic [47:0] mac_addr_i,
            input logic [31:0] ip_addr_i
        );

        if (icmp_lhs.dst_mac != mac_addr_i && icmp_lhs.dst_mac != 48'hFFFFFFFFFFFF) begin
            return -1; // Not for us
        end
        else if (icmp_lhs.src_mac == mac_addr_i) begin
            return -2; // Echo protection
        end
        else if (icmp_lhs.ethertype != icmp_req_ref.ethertype) begin
            return -3; // Wrong EtherType
        end
        else if (icmp_lhs.ip_version != icmp_req_ref.ip_version) begin
            return -4; // Wrong IP version
        end
        else if (icmp_lhs.ip_protocol != icmp_req_ref.ip_protocol) begin
            return -5; // Wrong protocol (not ICMP)
        end
        else if (icmp_lhs.ip_dst != ip_addr_i) begin
            return -6; // Not for our IP
        end
        else if (icmp_lhs.icmp_type != icmp_req_ref.icmp_type) begin
            return -7; // Not an echo request
        end
        else if (icmp_lhs.icmp_code != icmp_req_ref.icmp_code) begin
            return -8; // Wrong ICMP code
        end
        else begin
            return 1; // Valid ICMP echo request
        end
    endfunction

endpackage : icmp_pkg

