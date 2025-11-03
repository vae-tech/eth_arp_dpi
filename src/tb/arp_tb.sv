/*================================================================
  ARP Testbench
  ================================================================
    Author:   Artem Voropaev
    Email:    voropaev.art@gmail.com
    Created:  2025-11-06

    Description:
        This testbench is used to test the ARP module.
        It uses SystemVerilog DPI-C to interface with the host application.
        The host application is responsible for sending and receiving packets to and from the DUT.

    Version:
        2025-11-06 - 0.1:   - Init
================================================================*/

`timescale 1ns / 1ns

import arp_pkg::*;

module arp_tb;

    typedef byte pkt_q_t[$];
    pkt_q_t pkt_q;

    // Clock and Reset Signals
    logic        clk_rx=0;
    logic        clk_tx=0;
    logic        areset;
    // CFG
    logic [47:0] my_mac;
    logic [31:0] my_ipv4;
    // RX
    logic        data_valid_rx;
    logic [7:0]  data_rx;
    // TX
    logic        data_valid_tx;
    logic [7:0]  data_tx;
    logic        data_ack_tx;
    
    // !!! Thread safe mailboxes
    mailbox #(pkt_q_t) to_hdl_mbx = new();
    mailbox #(pkt_q_t) from_hdl_mbx = new();
    
    // Packet queues
    pkt_q_t pkt_pull_q = {}; 
    pkt_q_t pkt_tx_q = {};
    pkt_q_t pkt_rx_q = {};
    
    //=======================================================================
    // Clock Generation
    //=======================================================================

    always #4ns clk_rx <= ~clk_rx;
    always #4ns clk_tx <= ~clk_tx;
  
    //=======================================================================
    // DUT
    //=======================================================================
    arp_top dut (
        // Reset and Configuration
        .ARESET         (areset),
        .MY_MAC         (my_mac),
        .MY_IPV4        (my_ipv4),
        
        // RX Path (Receive clock domain)
        .CLK_RX         (clk_rx),
        .DATA_VALID_RX  (data_valid_rx),
        .DATA_RX        (data_rx),
        
        // TX Path (Transmit clock domain)
        .CLK_TX         (clk_tx),
        .DATA_VALID_TX  (data_valid_tx),
        .DATA_TX        (data_tx),
        .DATA_ACK_TX    (data_ack_tx)
    );

    //=======================================================================
    // MAIN
    //=======================================================================
    /**
     * @brief Main testbench thread
     * @details Initializes the testbench and starts the threads
     **/
    initial begin : MAIN
        // Initialize signals
        areset        = 1'b1;
        my_mac        = 48'h001122334455;
        my_ipv4       = 32'hC0A80101; // 192.168.1.1
        data_valid_rx = 1'b0;
        data_rx       = 8'h00;
        data_ack_tx   = 1'b0;
        
        // Wait for some time and release reset
        #100ns;
        areset = 1'b0;
        
        // Wait for stable operation
        #50ns;
        
        $display("Simulation started at time %0t", $time);
        $display("Config:");
        $display("    MY_MAC  = 0x%12h", my_mac);
        $display("    MY_IPV4 = 0x%8h", my_ipv4);

        $display("Initializing threads...");
        fork 
            //=======================================================================
            // THREAD: Receive packets from host
            //=======================================================================
            begin : PKT_RX_FROM_HOST_THREAD
                forever begin : PKT_RX_FROM_HOST
                    @(posedge clk_rx);
                    if(to_hdl_mbx.num() > 0) begin  // received packets from host, send to DUT
                        to_hdl_mbx.get(pkt_rx_q); 
                        $display("[%t] RX: Got packet;  sz =%5d", $time(), pkt_rx_q.size());
                        // Send received packets to DUT via RX path
                        do begin
                            @(posedge clk_rx); 
                            data_valid_rx = '1;
                            data_rx = pkt_rx_q.pop_front();
                        end while (pkt_rx_q.size() > 0);
                        // all data sent
                        @(posedge clk_rx);
                        data_valid_rx = '0;
                    end
                end
            end

            //=======================================================================
            // THREAD: Capture TX data from DUT and store in queue
            //=======================================================================
            begin : TX_DATA_CAPTURE_THREAD
                forever begin
                    @(posedge clk_tx);
                    if(data_ack_tx) begin // wait for ack from MAC
                        while(data_valid_tx) begin
                            pkt_tx_q.push_back(data_tx);
                            @(posedge clk_tx);
                        end 
                    end 
                end
            end

            //=======================================================================
            // THREAD: Generate random ack from MAC
            //=======================================================================
            begin : MAC_ACK_GENERATION_THREAD
                forever begin
                    @(posedge data_valid_tx); // wait for beginning of the packet
                    repeat($urandom_range(0, 10)) begin // wait for random number of clock cycles
                        @(posedge clk_tx);
                    end
                    // send ack 1 clk cycle
                    data_ack_tx <= 1'b1; // FIXME: non-blocking assignment to avoid race condition with data_ack_tx in capture thread
                    @(posedge clk_tx);
                    data_ack_tx <= 1'b0; 
                end
            end

            //=======================================================================
            // THREAD: Send packets to host
            //=======================================================================
            begin : PKT_TX_TO_HOST_THREAD
                forever begin
                    @(negedge data_valid_tx);
                    if (pkt_tx_q.size() > 0) begin // prevent sending empty packets -> host app will fail
                        from_hdl_mbx.put(pkt_tx_q);
                        $display("[%t] TX: Packets in store=%5d", $time(), from_hdl_mbx.num());
                        $display("[%t] TX: Sent packet; sz =%5d", $time(), pkt_tx_q.size());
                        pkt_tx_q = {};
                    end
                end
            end
        join_any; // one or more thread terminated
           
        $display("Simulation ended at %0t", $time);
        $finish;
    end
    
    //=======================================================================
    // DPI-C tasks for dut TX path
    //=======================================================================

    export "DPI-C" task host_delay;
    export "DPI-C" task host_rx_pkt_valid;
    export "DPI-C" task host_rx_pkt_pull;
    export "DPI-C" task host_rx_pkt_get_data;
    
    /**
     * @brief Delays the simulation for the specified number of clock cycles
     * @param nclk Number of clock cycles to delay
     * @details Required to sync between SW and HDL
     **/
    task host_delay(input int nclk);
        repeat(nclk)
            @(posedge clk_rx);
    endtask : host_delay

    task  host_rx_pkt_valid(output int npkt);
        npkt = from_hdl_mbx.num();
    endtask

    /**
     * @brief Pulls a packet from the mailbox and returns its length
     * @param pkt_len Output parameter containing the length of the pulled packet
     **/
    task host_rx_pkt_pull(output int pkt_len);
        if(from_hdl_mbx.num() > 0) begin
            pkt_pull_q = {};
            from_hdl_mbx.get(pkt_pull_q);
            pkt_len = pkt_pull_q.size();
        end else begin
            pkt_len = 0;
        end
    endtask

    /**
     * @brief Retrieves data from the pulled packet at the specified index
     * @param data_o Output parameter containing the data at the specified index
     * @param index Index of the data to retrieve
     **/
    task host_rx_pkt_get_data(output logic [7:0] data_o, input int index);
        data_o = pkt_pull_q[index];
    endtask

    //=======================================================================
    // DPI-C tasks for RX path
    //=======================================================================

    export "DPI-C" task host_tx_data_push;
    export "DPI-C" task host_tx_transfer_init;

    /**
     * @brief Pushes a byte of data to the packet queue
     * @param data Byte of data to push to the packet queue
     **/
    task host_tx_data_push(input byte data);
        pkt_q.push_back(data);
    endtask

    /**
     * @brief Initializes the packet transmission
     * @details Puts the packet queue into the mailbox to be sent to the DUT
     **/
    task host_tx_transfer_init();
        to_hdl_mbx.put(pkt_q);
        pkt_q = {}; // free queue
    endtask

    //=======================================================================
    // DPI-C init host application
    //=======================================================================

    import "DPI-C" context task eth_dpi_main();

    /**
     * @brief Initializes the host application
     **/
    initial 
    begin   :   MAIN_NET_ADAPT
        eth_dpi_main();
    end

endmodule