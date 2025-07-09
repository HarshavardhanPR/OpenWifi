# // Author: Xianjun Jiao, xianjun.jiao@imec.be, putaoshu@msn.com
# // SPDX-FileCopyrightText: 2022 UGent
# // SPDX-License-Identifier: AGPL-3.0-or-later

#set iq_file_set [list \
# /home/jxj/git/openofdminternal/testing_inputs/simulated/phy1_mcs7_gi1rdm1_64B_gap2.5_2.5us_pkt2_snr25_fo0_ch1_iq_openwifi_20220724-142055.txt \
# /home/jxj/git/openofdminternal/testing_inputs/simulated/phy1_mcs7_gi1rdm1_64B_gap2.5_2.5us_pkt1_snr25_fo0_ch1_iq_openwifi_20220724-142033.txt \
# /home/jxj/git/openofdminternal/testing_inputs/simulated/phy1_mcs7_gi1rdm1_64B_gap2.5_2.5us_pkt1_snr25_fo0_ch2_iq_openwifi_20220724-142033.txt \
#]

# set iq_file_set [glob /home/jxj/git/tmp/openofdminternal1/testing_inputs/simulated/iq/*.txt]
# set iq_file_set [glob /home/jxj/git/tmp/openofdminternal1/testing_inputs/simulated/iq/phy1_mcs2_gi1rdm1_64B_gap2.5_2.5us_pkt2000_snr10_fo20000_ch1_iq_openwifi_20220725-000949.txt]
# set iq_file_set [glob /home/jxj/Downloads/phy1_mcs0_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr6_fo20000_ch1_iq_openwifi_20220725-002826/phy1_mcs0_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr6_fo20000_ch1_iq_openwifi_20220725-002826_pkt4.txt]

# set iq_file_set [list \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt260.txt \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt298.txt \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt493.txt \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt1163.txt \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt1450.txt \
# /home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt1723.txt \
# ]

set iq_file_set [list \
/home/jxj/Downloads/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021/phy1_mcs1_gi1rdm1_62B_gap2.5_2.5us_pkt2000_snr8_fo20000_ch1_iq_openwifi_20220725-003021_pkt1450.txt \
]
# Check files before actual simulation
foreach iq_file $iq_file_set {	;# Now loop 
    puts "iq_filename $iq_file"
    set num_iq [exec wc -l < $iq_file]
    puts "num_iq $num_iq"
    if {$num_iq < 480} {
        puts "$num_iq < 480!"
        return
    }
}

foreach iq_file $iq_file_set {	;# Now loop 
    set argv [list $iq_file]
    source openofdm_rx_sim_iq_file.tcl
}
