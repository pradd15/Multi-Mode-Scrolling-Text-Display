# Multi-Mode-Scrolling-Text-Display
Verilog-based scrolling text display controller using a Basys 3 FPGA and UART-driven PmodCLS LCD.
# Multi-Mode Scrolling Text Display Controller

A Verilog-based text display controller for the **Digilent Basys 3 FPGA** that communicates with a **PmodCLS 16×2 LCD** using UART serial communication.

## Overview

This project implements a configurable text display controller using Verilog HDL. It sends commands and text to the LCD through a UART transmitter and allows the display behavior to be controlled using the Basys 3 board's slide switches.

The design consists of two Verilog modules: `uart_tx`, which handles serial data transmission, and `lcd_scroller`, which manages the text, display modes, scrolling direction, speed selection, and LCD updates.

 Features

* Scroll Left: Moves the text window forward through the message.
* Still Text: Displays a stationary text window.
* Scroll Right: Moves the text window in the reverse direction.
* Mirrored Text: Displays the text window with its characters in reverse order.
* Message Selection: Selects between two predefined messages.
* Four Speed Settings: Adjusts the delay between display updates.
* UART Communication: Transmits LCD commands and characters at 9600 baud using an 8-N-1 serial format.
* LCD Mode Labels: Displays the current operating mode on the second LCD row.

 Hardware Requirements

* Digilent Basys 3 FPGA development board
* PmodCLS 16×2 LCD
* Appropriate connections between the FPGA's UART output and the LCD's RXD input

Software and Technologies

* Verilog HDL
* Xilinx Vivado — FPGA design and implementation
* ModelSim — optional simulation and verification

 Switch Controls

The design uses six slide-switch inputs (`sw[5:0]`).

| Switches | Function          | Settings                                                                         |
| -------- | ----------------- | -------------------------------------------------------------------------------- |
| SW1:SW0  | Display mode      | `00` = Scroll Left, `01` = Still Text, `10` = Scroll Right, `11` = Mirrored Text |
| SW3:SW2  | Scrolling speed   | `00` = Slowest, `01` = Speed 2, `10` = Speed 3, `11` = Fastest                   |
| SW4      | Message selection | `0` = HELLO WORLD, `1` = BUS 42 NORTH                                            |
| SW5      | Reserved          | Currently unused                                                                 |

Switch changes are synchronized and applied at the beginning of a subsequent screen update.



 1. UART Transmitter

The `uart_tx` module converts each 8-bit data value into a serial UART frame. It generates a start bit, transmits the data bits least-significant-bit first, and finishes with a stop bit.

The default timing parameter is configured for a 100 MHz clock and 9600 baud.

 2. LCD Controller

The `lcd_scroller` module manages the display update sequence. After a power-up delay, it sends a display-clear command and then transmits the text and mode label.

The controller uses a state machine to coordinate UART transmission, wait for each byte to finish, and pause between screen updates.

 3. Scrolling and Display Modes

The controller maintains a starting position in the selected message. In scroll-left mode, the position advances; in scroll-right mode, it moves backward. Still-text mode keeps the starting position unchanged, while mirrored mode reverses the character order in the displayed window.

Sixteen blank characters are appended to each message to provide spacing during scrolling.

 4. Speed and Message Selection

The speed switches select one of four programmable delays between screen updates. SW4 selects between the two predefined messages. The selected mode and message are latched for a screen update.

Source Code

The project is implemented in a single Verilog source file containing:

* `uart_tx` — UART transmitter module
* `lcd_scroller` — top-level LCD scrolling controller

The controller's timing and message parameters can be adjusted in the source code.

How to Use

1. Open the Verilog source file in Xilinx Vivado.
2. Create or open a project targeting the Digilent Basys 3 FPGA.
3. Add the source file to the project.
4. Assign the clock, reset, switch, and UART output ports to the correct FPGA pins using an appropriate constraints file.
5. Run synthesis and implementation.
6. Program the FPGA and connect the LCD's RXD input to the configured UART output.
7. Use the slide switches to select the display mode, speed, and message.

Note:The correct pin assignments, reset polarity, LCD configuration, and physical connections must be verified for the specific board setup before hardware operation.

Academic VLSI Design Lab project. This repository contains the Verilog implementation of the UART-based scrolling text display controller.


