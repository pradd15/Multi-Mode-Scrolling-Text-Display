`timescale 1ns/1ps
//
// lcd_scroller.v  --  multi-mode text display for the Digilent PmodCLS (16x2 LCD)
//
// Switch controls (Basys 3 slide switches):
//   SW1:SW0  mode        00 = scroll left   (running text)
//                        01 = still text
//                        10 = scroll right  (reversed direction)
//                        11 = mirrored text (characters in reverse order, still)
//   SW3:SW2  speed       00 = slowest ... 11 = fastest
//   SW4      message     0 = TEXT0, 1 = TEXT1
//   SW5      (unused, free for your own feature)
//
// Row 0 of the LCD shows the text, row 1 shows the name of the current mode.
// Serial format: UART, 9600 baud, 8N1, to the PmodCLS RXD pin.
// Switch changes take effect at the start of the next screen update.
//
// ---------------------------------------------------------------------------
// UART transmitter (8N1)
// ---------------------------------------------------------------------------
module uart_tx #(
    parameter CLKS_PER_BIT = 10417          // 100 MHz / 9600 baud
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,                // pulse high for 1 clock to send `data`
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  st;
    reg [31:0] clk_cnt;
    reg [2:0]  bit_i;
    reg [7:0]  shreg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st      <= IDLE;
            tx      <= 1'b1;
            busy    <= 1'b0;
            clk_cnt <= 32'd0;
            bit_i   <= 3'd0;
            shreg   <= 8'd0;
        end else begin
            case (st)
                IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 32'd0;
                    bit_i   <= 3'd0;
                    if (start) begin
                        shreg <= data;
                        busy  <= 1'b1;
                        tx    <= 1'b0;          // start bit
                        st    <= START;
                    end
                end

                START: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 32'd0;
                        tx      <= shreg[0];    // first data bit (LSB first)
                        shreg   <= {1'b0, shreg[7:1]};
                        bit_i   <= 3'd0;
                        st      <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 32'd0;
                        if (bit_i == 3'd7) begin
                            tx <= 1'b1;         // stop bit
                            st <= STOP;
                        end else begin
                            tx    <= shreg[0];
                            shreg <= {1'b0, shreg[7:1]};
                            bit_i <= bit_i + 1'b1;
                        end
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 32'd0;
                        busy    <= 1'b0;
                        st      <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule


// ---------------------------------------------------------------------------
// Top level
// ---------------------------------------------------------------------------
module lcd_scroller #(
    parameter CLKS_PER_BIT = 10417,         // 100 MHz / 9600 baud
    parameter PWRUP_CLKS   = 10000000,      // 100 ms wait after reset (display boot)
    // Pause between screen updates for the 4 speed settings (SW3:SW2).
    // A full update also takes ~46 ms to transmit, so real period = gap + 46 ms.
    parameter GAP0 = 50000000,              // ~0.55 s
    parameter GAP1 = 25000000,              // ~0.30 s
    parameter GAP2 = 10000000,              // ~0.15 s
    parameter GAP3 = 2500000                // ~0.07 s
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [5:0] sw,
    output wire       lcd_rxd               // connect to PmodCLS RXD
);

    // ---- Edit the messages here (length must match the text) ----
    localparam LEN0 = 11;
    localparam [LEN0*8-1:0] TEXT0 = "HELLO WORLD";
    localparam LEN1 = 12;
    localparam [LEN1*8-1:0] TEXT1 = "BUS 42 NORTH";

    // 16 blank characters are appended so scrolling text leaves the display
    // completely before it re-enters.
    localparam PAD  = 16;
    localparam TOT0 = LEN0 + PAD;
    localparam TOT1 = LEN1 + PAD;
    localparam [TOT0*8-1:0] MSG0 = {TEXT0, {PAD{8'h20}}};
    localparam [TOT1*8-1:0] MSG1 = {TEXT1, {PAD{8'h20}}};

    // ---- Row-2 labels: exactly 16 characters each ----
    localparam [127:0] LBL_SCROLL_L = "SCROLL LEFT     ";
    localparam [127:0] LBL_STILL    = "STILL TEXT      ";
    localparam [127:0] LBL_SCROLL_R = "SCROLL RIGHT    ";
    localparam [127:0] LBL_MIRROR   = "MIRRORED TEXT   ";

    function [7:0] get_char;
        input sel;
        input integer idx;
        begin
            if (sel) get_char = MSG1[(TOT1-1-idx)*8 +: 8];
            else     get_char = MSG0[(TOT0-1-idx)*8 +: 8];
        end
    endfunction

    // ---- Synchronise the (asynchronous) switches ----
    reg [5:0] sw_m, sw_s;
    always @(posedge clk) begin
        sw_m <= sw;
        sw_s <= sw_m;
    end

    // ---- UART instance ----
    reg        tx_start;
    reg  [7:0] tx_byte;
    wire       busy;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .start(tx_start), .data(tx_byte),
        .tx(lcd_rxd), .busy(busy)
    );

    // ---- Controller state ----
    localparam S_PWRUP = 3'd0,
               S_SEND  = 3'd1,
               S_BUSY1 = 3'd2,   // wait for UART to start
               S_BUSY0 = 3'd3,   // wait for UART to finish
               S_GAP   = 3'd4;

    reg [2:0]  state;
    reg [31:0] cnt;
    reg [5:0]  byte_idx;
    reg        frame_mode;       // 0 = sending the clear command, 1 = sending screens
    reg [7:0]  start_pos;        // first message character in the window
    reg [1:0]  mode_l;           // mode latched at the start of each screen update
    reg        msg_l;            // message select latched likewise

    integer cur_len;
    always @(*) cur_len = msg_l ? TOT1 : TOT0;

    reg [31:0] gap_clks;
    always @(*) begin
        case (sw_s[3:2])
            2'd0:    gap_clks = GAP0;
            2'd1:    gap_clks = GAP1;
            2'd2:    gap_clks = GAP2;
            default: gap_clks = GAP3;
        endcase
    end

    // Bytes sent:
    //   clear command : ESC [ j                                   (3 bytes, idx 0..2)
    //   screen update : ESC [ 0 ; 0 H + 16 text chars             (idx 0..21)
    //                   ESC [ 1 ; 0 H + 16 label chars            (idx 22..43)
    integer ci, k, wk, base;
    reg [127:0] lbl;
    always @(*) begin
        ci = 0; k = 0; wk = 0; base = 0;
        lbl = LBL_SCROLL_L;
        tx_byte = 8'h20;
        if (!frame_mode) begin
            case (byte_idx)
                6'd0:    tx_byte = 8'h1B;   // ESC
                6'd1:    tx_byte = "[";
                default: tx_byte = "j";     // clear display, cursor home
            endcase
        end else if (byte_idx < 6) begin
            case (byte_idx)
                6'd0:    tx_byte = 8'h1B;
                6'd1:    tx_byte = "[";
                6'd2:    tx_byte = "0";     // row 0
                6'd3:    tx_byte = ";";
                6'd4:    tx_byte = "0";     // column 0
                default: tx_byte = "H";
            endcase
        end else if (byte_idx < 22) begin
            k    = byte_idx - 6;                         // 0..15
            wk   = (mode_l == 2'b11) ? (15 - k) : k;     // mirrored reads backwards
            base = (mode_l == 2'b00 || mode_l == 2'b10) ? start_pos : 0;
            ci   = base + wk;
            if (ci >= cur_len) ci = ci - cur_len;
            tx_byte = get_char(msg_l, ci);
        end else if (byte_idx < 28) begin
            case (byte_idx)
                6'd22:   tx_byte = 8'h1B;
                6'd23:   tx_byte = "[";
                6'd24:   tx_byte = "1";     // row 1
                6'd25:   tx_byte = ";";
                6'd26:   tx_byte = "0";     // column 0
                default: tx_byte = "H";
            endcase
        end else begin
            k = byte_idx - 28;                           // 0..15
            case (mode_l)
                2'b00:   lbl = LBL_SCROLL_L;
                2'b01:   lbl = LBL_STILL;
                2'b10:   lbl = LBL_SCROLL_R;
                default: lbl = LBL_MIRROR;
            endcase
            tx_byte = lbl[(15-k)*8 +: 8];
        end
    end

    wire last_byte = frame_mode ? (byte_idx == 6'd43) : (byte_idx == 6'd2);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_PWRUP;
            cnt        <= 32'd0;
            byte_idx   <= 6'd0;
            frame_mode <= 1'b0;
            start_pos  <= 8'd0;
            mode_l     <= 2'b00;
            msg_l      <= 1'b0;
            tx_start   <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                S_PWRUP: begin
                    if (cnt == PWRUP_CLKS-1) begin
                        cnt   <= 32'd0;
                        state <= S_SEND;
                    end else
                        cnt <= cnt + 1'b1;
                end

                S_SEND: begin
                    if (!busy) begin
                        tx_start <= 1'b1;
                        state    <= S_BUSY1;
                    end
                end

                S_BUSY1: if (busy) state <= S_BUSY0;

                S_BUSY0: begin
                    if (!busy) begin
                        if (last_byte) begin
                            byte_idx <= 6'd0;
                            cnt      <= 32'd0;
                            state    <= S_GAP;
                            if (!frame_mode) begin
                                frame_mode <= 1'b1;          // clear done -> start screens
                            end else if (mode_l == 2'b00) begin
                                // scroll left: window start moves forward
                                start_pos <= (start_pos + 1 >= cur_len) ? 8'd0
                                                                        : start_pos + 1'b1;
                            end else if (mode_l == 2'b10) begin
                                // scroll right: window start moves backward
                                start_pos <= (start_pos == 0) ? (cur_len - 1)
                                                              : start_pos - 1'b1;
                            end
                            // still / mirrored: start_pos is left alone
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= S_SEND;
                        end
                    end
                end

                S_GAP: begin
                    if (cnt >= gap_clks - 1) begin
                        cnt    <= 32'd0;
                        state  <= S_SEND;
                        // latch the switches for the next whole screen update
                        mode_l <= sw_s[1:0];
                        msg_l  <= sw_s[4];
                        if (sw_s[4] != msg_l)
                            start_pos <= 8'd0;               // new message: restart
                    end else
                        cnt <= cnt + 1'b1;
                end

                default: state <= S_PWRUP;
            endcase
        end
    end

endmodule
