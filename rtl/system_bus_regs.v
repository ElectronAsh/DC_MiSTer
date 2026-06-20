module system_bus_regs (


);


parameter SB_C2DSTAT_addr = 32'h005F6800; reg [31:0] SB_C2DSTAT;	// RW ch2-DMA destination address
parameter SB_C2DLEN_addr  = 32'h005F6804; reg [31:0] SB_C2DLEN;		// RW ch2-DMA length
parameter SB_C2DST_addr   = 32'h005F6808; reg [31:0] SB_C2DST;		// RW ch2-DMA start
parameter SB_SDSTAW_addr  = 32'h005F6810; reg [31:0] SB_SDSTAW;		// RW Sort-DMA start link table address
parameter SB_SDBAAW_addr  = 32'h005F6814; reg [31:0] SB_SDBAAW;		// RW Sort-DMA link base address
parameter SB_SDWLT_addr   = 32'h005F6818; reg [31:0] SB_SDWLT;		// RW Sort-DMA link address bit width
parameter SB_SDLAS_addr   = 32'h005F681C; reg [31:0] SB_SDLAS;		// RW Sort-DMA link address shift control
parameter SB_SDST_addr    = 32'h005F6820; reg [31:0] SB_SDST;		// RW Sort-DMA start
parameter SB_DBREQM_addr  = 32'h005F6840; reg [31:0] SB_DBREQM;		// RW DBREQ# signal mask control
parameter SB_BAVLWC_addr  = 32'h005F6844; reg [31:0] SB_BAVLWC;		// RW BAVL# signal wait count
parameter SB_C2DPRYC_addr = 32'h005F6848; reg [31:0] SB_C2DPRYC;	// RW DMA (TA/Root Bus) priority count
parameter SB_C2DMAXL_addr = 32'h005F684C; reg [31:0] SB_C2DMAXL;	// RW ch2-DMA maximum burst length
parameter SB_TFREM_addr   = 32'h005F6880; reg [31:0] SB_TFREM;		// R TA FIFO remaining amount
parameter SB_LMMODE0_addr = 32'h005F6884; reg [31:0] SB_LMMODE0;	// RW Via TA texture memory bus select 0
parameter SB_LMMODE1_addr = 32'h005F6888; reg [31:0] SB_LMMODE1;	// RW Via TA texture memory bus select 1
parameter SB_FFST_addr    = 32'h005F688C; reg [31:0] SB_FFST;		// R FIFO status
parameter SB_SFRES_addr   = 32'h005F6890; reg [31:0] SB_SFRES;		// W System reset
parameter SB_SBREV_addr   = 32'h005F689C; reg [31:0] SB_SBREV;		// R System bus revision number
parameter SB_RBSPLT_addr  = 32'h005F68A0; reg [31:0] SB_RBSPLT;		// RW SH4 Root Bus split enable
parameter SB_ISTNRM_addr  = 32'h005F6900; reg [31:0] SB_ISTNRM;		// RW Normal interrupt status
parameter SB_ISTEXT_addr  = 32'h005F6904; reg [31:0] SB_ISTEXT;		// R External interrupt status
parameter SB_ISTERR_addr  = 32'h005F6908; reg [31:0] SB_ISTERR;		// RW Error interrupt status
parameter SB_IML2NRM_addr = 32'h005F6910; reg [31:0] SB_IML2NRM;	// RW Level 2 normal interrupt mask
parameter SB_IML2EXT_addr = 32'h005F6914; reg [31:0] SB_IML2EXT;	// RW Level 2 external interrupt mask
parameter SB_IML2ERR_addr = 32'h005F6918; reg [31:0] SB_IML2ERR;	// RW Level 2 error interrupt mask
parameter SB_IML4NRM_addr = 32'h005F6920; reg [31:0] SB_IML4NRM;	// RW Level 4 normal interrupt mask
parameter SB_IML4EXT_addr = 32'h005F6924; reg [31:0] SB_IML4EXT;	// RW Level 4 external interrupt mask
parameter SB_IML4ERR_addr = 32'h005F6928; reg [31:0] SB_IML4ERR;	// RW Level 4 error interrupt mask
parameter SB_IML6NRM_addr = 32'h005F6930; reg [31:0] SB_IML6NRM;	// RW Level 6 normal interrupt mask
parameter SB_IML6EXT_addr = 32'h005F6934; reg [31:0] SB_IML6EXT;	// RW Level 6 external interrupt mask
parameter SB_IML6ERR_addr = 32'h005F6938; reg [31:0] SB_IML6ERR;	// RW Level 6 error interrupt mask
parameter SB_PDTNRM_addr  = 32'h005F6940; reg [31:0] SB_PDTNRM;		// RW Normal interrupt PVR-DMA startup mask
parameter SB_PDTEXT_addr  = 32'h005F6944; reg [31:0] SB_PDTEXT;		// RW External interrupt PVR-DMA startup mask
parameter SB_G2DTNRM_addr = 32'h005F6950; reg [31:0] SB_G2DTNRM;	// RW Normal interrupt G2-DMA startup mask
parameter SB_G2DTEXT_addr = 32'h005F6954; reg [31:0] SB_G2DTEXT;	// RW External interrupt G2-DMA startup mask

parameter SB_MDSTAR_addr  = 32'h005F6C04; reg [31:0] SB_MDSTAR;		// RW Maple-DMA command table address
parameter SB_MDTSEL_addr  = 32'h005F6C10; reg [31:0] SB_MDTSEL;		// RW Maple-DMA trigger select
parameter SB_MDEN_addr    = 32'h005F6C14; reg [31:0] SB_MDEN;		// RW Maple-DMA enable

parameter SB_MDST_addr    = 32'h005F6C18; reg [31:0] SB_MDST;		// RW Maple-DMA start
parameter SB_MSYS_addr    = 32'h005F6C80; reg [31:0] SB_MSYS;		// RW Maple system control
parameter SB_MST_addr     = 32'h005F6C84; reg [31:0] SB_MST;		// R Maple status
parameter SB_MSHTCL_addr  = 32'h005F6C88; reg [31:0] SB_MSHTCL;		// W Maple-DMA hard trigger clear
parameter SB_MDAPRO_addr  = 32'h005F6C8C; reg [31:0] SB_MDAPRO;		// W Maple-DMA address range
parameter SB_MMSEL_addr   = 32'h005F6CE8; reg [31:0] SB_MMSEL;		// RW Maple MSB selection
parameter SB_MTXDAD_addr  = 32'h005F6CF4; reg [31:0] SB_MTXDAD;		// R Maple Txd address counter
parameter SB_MRXDAD_addr  = 32'h005F6CF8; reg [31:0] SB_MRXDAD;		// R Maple Rxd address counter
parameter SB_MRXDBD_addr  = 32'h005F6CFC; reg [31:0] SB_MRXDBD;		// R Maple Rxd base address
parameter SB_GDSTAR_addr  = 32'h005F7404; reg [31:0] SB_GDSTAR;		// RW GD-DMA start address
parameter SB_GDLEN_addr   = 32'h005F7408; reg [31:0] SB_GDLEN;		// RW GD-DMA length
parameter SB_GDDIR_addr   = 32'h005F740C; reg [31:0] SB_GDDIR;		// RW GD-DMA direction
parameter SB_GDEN_addr    = 32'h005F7414; reg [31:0] SB_GDEN;		// RW GD-DMA enable
parameter SB_GDST_addr    = 32'h005F7418; reg [31:0] SB_GDST;		// RW GD-DMA start
parameter SB_G1RRC_addr   = 32'h005F7480; reg [31:0] SB_G1RRC;		// W System ROM read access timing
parameter SB_G1RWC_addr   = 32'h005F7484; reg [31:0] SB_G1RWC;		// W System ROM write access timing
parameter SB_G1FRC_addr   = 32'h005F7488; reg [31:0] SB_G1FRC;		// W Flash ROM read access timing
parameter SB_G1FWC_addr   = 32'h005F748C; reg [31:0] SB_G1FWC;		// W Flash ROM write access timing
parameter SB_G1CRC_addr   = 32'h005F7490; reg [31:0] SB_G1CRC;		// W GD PIO read access timing
parameter SB_G1CWC_addr   = 32'h005F7494; reg [31:0] SB_G1CWC;		// W GD PIO write access timing
parameter SB_G1GDRC_addr  = 32'h005F74A0; reg [31:0] SB_G1GDRC;		// W GD-DMA read access timing
parameter SB_G1GDWC_addr  = 32'h005F74A4; reg [31:0] SB_G1GDWC;		// W GD-DMA write access timing
parameter SB_G1SYSM_addr  = 32'h005F74B0; reg [31:0] SB_G1SYSM;		// R System mode
parameter SB_G1CRDYC_addr = 32'h005F74B4; reg [31:0] SB_G1CRDYC;	// W G1IORDY signal control
parameter SB_GDAPRO_addr  = 32'h005F74B8; reg [31:0] SB_GDAPRO;		// W GD-DMA address range
parameter SB_GDSTARD_addr = 32'h005F74F4; reg [31:0] SB_GDSTARD;	// R GD-DMA address count (on Root Bus)
parameter SB_GDLEND_addr  = 32'h005F74F8; reg [31:0] SB_GDLEND;		// R GD-DMA transfer counter
parameter SB_ADSTAG_addr  = 32'h005F7800; reg [31:0] SB_ADSTAG;		// RW AICA:G2-DMA G2 start address
parameter SB_ADSTAR_addr  = 32'h005F7804; reg [31:0] SB_ADSTAR;		// RW AICA:G2-DMA system memory start address
parameter SB_ADLEN_addr   = 32'h005F7808; reg [31:0] SB_ADLEN;		// RW AICA:G2-DMA length
parameter SB_ADDIR_addr   = 32'h005F780C; reg [31:0] SB_ADDIR;		// RW AICA:G2-DMA direction
parameter SB_ADTSEL_addr  = 32'h005F7810; reg [31:0] SB_ADTSEL;		// RW AICA:G2-DMA trigger select
parameter SB_ADEN_addr    = 32'h005F7814; reg [31:0] SB_ADEN;		// RW AICA:G2-DMA enable

parameter SB_ADST_addr    = 32'h005F7818; reg [31:0] SB_ADST;		// RW AICA:G2-DMA start
parameter SB_ADSUSP_addr  = 32'h005F781C; reg [31:0] SB_ADSUSP;		// RW AICA:G2-DMA suspend
parameter SB_E1STAG_addr  = 32'h005F7820; reg [31:0] SB_E1STAG;		// RW Ext1:G2-DMA G2 start address
parameter SB_E1STAR_addr  = 32'h005F7824; reg [31:0] SB_E1STAR;		// RW Ext1:G2-DMA system memory start address
parameter SB_E1LEN_addr   = 32'h005F7828; reg [31:0] SB_E1LEN;		// RW Ext1:G2-DMA length
parameter SB_E1DIR_addr   = 32'h005F782C; reg [31:0] SB_E1DIR;		// RW Ext1:G2-DMA direction
parameter SB_E1TSEL_addr  = 32'h005F7830; reg [31:0] SB_E1TSEL;		// RW Ext1:G2-DMA trigger select
parameter SB_E1EN_addr    = 32'h005F7834; reg [31:0] SB_E1ENd;		// RW Ext1:G2-DMA enable

parameter SB_E1ST_addr    = 32'h005F7838; reg [31:0] SB_E1ST;		// RW Ext1:G2-DMA start
parameter SB_E1SUSP_addr  = 32'h005F783C; reg [31:0] SB_E1SUSP;		// RW Ext1: G2-DMA suspend
parameter SB_E2STAG_addr  = 32'h005F7840; reg [31:0] SB_E2STAG;		// RW Ext2:G2-DMA G2 start address
parameter SB_E2STAR_addr  = 32'h005F7844; reg [31:0] SB_E2STAR;		// RW Ext2:G2-DMA system memory start address
parameter SB_E2LEN_addr   = 32'h005F7848; reg [31:0] SB_E2LEN;		// RW Ext2:G2-DMA length
parameter SB_E2DIR_addr   = 32'h005F784C; reg [31:0] SB_E2DIR;		// RW Ext2:G2-DMA direction
parameter SB_E2TSEL_addr  = 32'h005F7850; reg [31:0] SB_E2TSEL;		// RW Ext2:G2-DMA trigger select
parameter SB_E2EN_addr    = 32'h005F7854; reg [31:0] SB_E2EN;		// RW Ext2:G2-DMA enable
parameter SB_E2ST_addr    = 32'h005F7858; reg [31:0] SB_E2ST;		// RW Ext2:G2-DMA start
parameter SB_E2SUSP_addr  = 32'h005F785C; reg [31:0] SB_E2SUSP;		// RW Ext2: G2-DMA suspend
parameter SB_DDSTAG_addr  = 32'h005F7860; reg [31:0] SB_DDSTAG;		// RW Dev:G2-DMA G2 start address
parameter SB_DDSTAR_addr  = 32'h005F7864; reg [31:0] SB_DDSTAR;		// RW Dev:G2-DMA system memory start address
parameter SB_DDLEN_addr   = 32'h005F7868; reg [31:0] SB_DDLEN;		// RW Dev:G2-DMA length
parameter SB_DDDIR_addr   = 32'h005F786C; reg [31:0] SB_DDDIR;		// RW Dev:G2-DMA direction
parameter SB_DDTSEL_addr  = 32'h005F7870; reg [31:0] SB_DDTSEL;		// RW Dev:G2-DMA trigger select
parameter SB_DDEN_addr    = 32'h005F7874; reg [31:0] SB_DDEN;		// RW Dev:G2-DMA enable
parameter SB_DDST_addr    = 32'h005F7878; reg [31:0] SB_DDST;		// RW Dev:G2-DMA start
parameter SB_DDSUSP_addr  = 32'h005F787C; reg [31:0] SB_DDSUSP;		// RW Dev: G2-DMA suspend
parameter SB_G2ID_addr    = 32'h005F7880; reg [31:0] SB_G2ID;		// R G2 bus version
parameter SB_G2DSTO_addr  = 32'h005F7890; reg [31:0] SB_G2DSTO;		// RW G2/DS timeout
parameter SB_G2TRTO_addr  = 32'h005F7894; reg [31:0] SB_G2TRTO;		// RW G2/TR timeout
parameter SB_G2MDMTO_addr = 32'h005F7898; reg [31:0] SB_G2MDMTO;	// RW Modem unit wait timeout
parameter SB_G2MDMW_addr  = 32'h005F789C; reg [31:0] SB_G2MDMW;		// RW Modem unit wait time
parameter SB_G2APRO_addr  = 32'h005F78BC; reg [31:0] SB_G2APRO;		// W G2-DMA address range
parameter SB_ADSTAGD_addr = 32'h005F78C0; reg [31:0] SB_ADSTAGD;	// R AICA-DMA address counter (on AICA)
parameter SB_ADSTARD_addr = 32'h005F78C4; reg [31:0] SB_ADSTARD;	// R AICA-DMA address counter (on root bus)
parameter SB_ADLEND_addr  = 32'h005F78C8; reg [31:0] SB_ADLEND;		// R AICA-DMA transfer counter
parameter SB_E1STAGD_addr = 32'h005F78D0; reg [31:0] SB_E1STAGD;	// R Ext-DMA1 address counter (on Ext)
parameter SB_E1STARD_addr = 32'h005F78D4; reg [31:0] SB_E1STARD;	// R Ext-DMA1 address counter (on root bus)
parameter SB_E1LEND_addr  = 32'h005F78D8; reg [31:0] SB_E1LEND;		// R Ext-DMA1 transfer counter

parameter SB_E2STAGD_addr = 32'h005F78E0; reg [31:0] SB_E2STAGD;	// R Ext-DMA2 address counter (on Ext)
parameter SB_E2STARD_addr = 32'h005F78E4; reg [31:0] SB_E2STARD;	// R Ext-DMA2 address counter (on root bus)
parameter SB_E2LEND_addr  = 32'h005F78E8; reg [31:0] SB_E2LEND;		// R Ext-DMA2 transfer counter
parameter SB_DDSTAGD_addr = 32'h005F78F0; reg [31:0] SB_DDSTAGD;	// R Dev-DMA address counter (on Ext)
parameter SB_DDSTARD_addr = 32'h005F78F4; reg [31:0] SB_DDSTARD;	// R Dev-DMA address counter (on root bus)
parameter SB_DDLEND_addr  = 32'h005F78F8; reg [31:0] SB_DDLEND;		// R Dev-DMA transfer counter
parameter SB_PDSTAP_addr  = 32'h005F7C00; reg [31:0] SB_PDSTAP;		// RW PVR-DMA PVR start address
parameter SB_PDSTAR_addr  = 32'h005F7C04; reg [31:0] SB_PDSTAR;		// RW PVR-DMA system memory start address
parameter SB_PDLEN_addr   = 32'h005F7C08; reg [31:0] SB_PDLEN;		// RW PVR-DMA length
parameter SB_PDDIR_addr   = 32'h005F7C0C; reg [31:0] SB_PDDIR;		// RW PVR-DMA direction
parameter SB_PDTSEL_addr  = 32'h005F7C10; reg [31:0] SB_PDTSEL;		// RW PVR-DMA trigger select
parameter SB_PDEN_addr    = 32'h005F7C14; reg [31:0] SB_PDEN;		// RW PVR-DMA enable
parameter SB_PDST_addr    = 32'h005F7C18; reg [31:0] SB_PDST;		// RW PVR-DMA start

parameter SB_PDAPRO_addr  = 32'h005F7C80; reg [31:0] SB_PDAPRO;		// W PVR-DMA address range
parameter SB_PDSTAPD_addr = 32'h005F7CF0; reg [31:0] SB_PDSTAPD;	// R PVR-DMA address counter (on Ext)
parameter SB_PDSTARD_addr = 32'h005F7CF4; reg [31:0] SB_PDSTARD;	// R PVR-DMA address counter (on root bus)
parameter SB_PDLEND_addr  = 32'h005F7CF8; reg [31:0] SB_PDLEND;		// R PVR-DMA transfer counter

endmodule
