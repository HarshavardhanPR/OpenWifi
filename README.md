OpenWiFi - Open-Source 802.11a/g/n Wi-Fi for FPGA

OpenWiFi is a fully open-source implementation of the IEEE 802.11a/g/n physical (PHY) and media access control (MAC) layers. It is designed to run on FPGA platforms integrated with Analog Devices AD9361/AD9364 RF frontends and supports real-time over-the-air Wi-Fi transmission and reception.

Features

PHY Layer

OFDM baseband implementation (supports 20 MHz channel bandwidth)
Modulation: BPSK, QPSK, 16-QAM, 64-QAM
FEC: Convolutional coding, puncturing, and Viterbi decoding
FFT/IFFT-based OFDM modulation and demodulation
Channel estimation, CFO correction, timing sync

MAC Layer

CSMA/CA-based contention
Retry logic, retransmission, and acknowledgment handling
Works with both hardware and Linux-based MAC

System Integration

Designed for Xilinx Zynq SoCs (ZC706, ZCU102, ADRV9361-Z7035, and custom boards)
Supports AXI Stream interfaces for MAC-to-PHY communication
Linux driver and PetaLinux integration

Real-time DMA interface with Linux networking stack

Build Toolchain

Vivado (tested with 2020.2 - 2024.2)
Xilinx SDK / Vitis / PetaLinux
Customizable for different RFSoC boards
