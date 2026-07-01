#include <iostream>
#include <fstream>
#include <string>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

#include <verilated.h>
#include "Vsimtop.h"
#include "Vsimtop___024root.h"

constexpr auto FRAC_BITS   = 12;	// 12 is about the max atm.
constexpr auto Z_FRAC_BITS = 17;	// 17 is about the max atm.

#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <d3d11.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <tchar.h>

#include "imgui_memory_editor.h"

#include "EasyBMP.h"

bool render_120 = 0;

bool force_sof1 = 0;

float x1_min = 10000.0f, x1_max = 0.0f;
float y1_min = 10000.0f, y1_max = 0.0f;
float z1_min = 10000.0f, z1_max = 0.0f;

float x2_min = 10000.0f, x2_max = 0.0f;
float y2_min = 10000.0f, y2_max = 0.0f;
float z2_min = 10000.0f, z2_max = 0.0f;

float x3_min = 10000.0f, x3_max = 0.0f;
float y3_min = 10000.0f, y3_max = 0.0f;
float z3_min = 10000.0f, z3_max = 0.0f;

float x4_min = 10000.0f, x4_max = 0.0f;
float y4_min = 10000.0f, y4_max = 0.0f;

struct RangeTracker {
	int64_t max_abs = 0;
	void update(int64_t v) { int64_t a = v < 0 ? -v : v; if (a > max_abs) max_abs = a; }
	int bits_signed() const {
		if (max_abs == 0) return 1;
		int b = 1; while ((int64_t(1) << b) <= max_abs) b++; return b + 1;
	}
	void reset() { max_abs = 0; }
};

RangeTracker rng_FZ, rng_Aa, rng_Ba, rng_BIG_C, rng_FDDX, rng_FDDY, rng_small_c, rng_interp_col;

struct VertexUvSnapshot {
	uint32_t x = 0;
	uint32_t y = 0;
	uint32_t z = 0;
	uint32_t u = 0;
	uint32_t v = 0;
};

struct ParamWriteSnapshot {
	bool valid = false;
	uint64_t cycle = 0;
	uint16_t tag = 0;
	uint8_t bank = 0;
	uint8_t tile_x = 0;
	uint8_t tile_y = 0;
	VertexUvSnapshot a;
	VertexUvSnapshot b;
	VertexUvSnapshot c;
	uint64_t fddx_u = 0;
	uint64_t fddy_u = 0;
	uint64_t fddx_v = 0;
	uint64_t fddy_v = 0;
	uint64_t tile_start_u = 0;
	uint64_t tile_start_v = 0;
};

struct TspIssueSnapshot {
	bool valid = false;
	uint64_t cycle = 0;
	uint16_t tag = 0;
	uint8_t bank = 0;
	uint8_t tile_x = 0;
	uint8_t tile_y = 0;
	uint16_t x = 0;
	uint16_t y = 0;
	uint32_t isp_inst = 0;
	uint32_t tsp_inst = 0;
	uint32_t tcw_word = 0;
	uint64_t fddx_u = 0;
	uint64_t fddy_u = 0;
	uint64_t fddx_v = 0;
	uint64_t fddy_v = 0;
	uint64_t tile_start_u = 0;
	uint64_t tile_start_v = 0;
	ParamWriteSnapshot param_write;
};

ParamWriteSnapshot param_write_snapshots[2][1024];
TspIssueSnapshot last_tsp_issue;

// DirectX data
static ID3D11Device*            g_pd3dDevice = NULL;
static ID3D11DeviceContext*     g_pd3dDeviceContext = NULL;
static IDXGIFactory*            g_pFactory = NULL;
static ID3D11Buffer*            g_pVB = NULL;
static ID3D11Buffer*            g_pIB = NULL;
static ID3D10Blob*              g_pVertexShaderBlob = NULL;
static ID3D11VertexShader*      g_pVertexShader = NULL;
static ID3D11InputLayout*       g_pInputLayout = NULL;
static ID3D11Buffer*            g_pVertexConstantBuffer = NULL;
static ID3D10Blob*              g_pPixelShaderBlob = NULL;
static ID3D11PixelShader*       g_pPixelShader = NULL;

static ID3D11SamplerState*       g_pDispSampler = NULL;
static ID3D11ShaderResourceView* g_pDispTextureView = NULL;

static ID3D11SamplerState*       g_pTileSampler = NULL;
static ID3D11ShaderResourceView* g_pTileTextureView = NULL;

static ID3D11RasterizerState*   g_pRasterizerState = NULL;
static ID3D11BlendState*        g_pBlendState = NULL;
static ID3D11DepthStencilState* g_pDepthStencilState = NULL;
static int                      g_VertexBufferSize = 5000, g_IndexBufferSize = 10000;


struct DdramEmu {
	bool pending = false;
	bool burst_active = false;
	uint32_t addr_latched = 0;
	uint32_t addr_curr = 0;
	uint64_t dout_latched = 0;
	uint32_t latency = 0;
	uint32_t burst_remaining = 0;
};

static constexpr uint32_t DDR_LATENCY_CYCLES = 0;

static void ddram_tick(
	DdramEmu &s,
	const uint8_t *vram_ptr,
	bool rd,
	uint32_t addr,
	uint32_t burstcnt,
	bool &busy,
	bool &dout_ready,
	uint64_t &dout
) {
	busy = (s.pending || s.burst_active);
	dout_ready = false;

	if (rd && !s.pending && !s.burst_active) {
		s.pending = true;
		s.addr_latched = addr;
		s.addr_curr = addr;
		s.latency = DDR_LATENCY_CYCLES;
		s.burst_remaining = burstcnt;
	}

	if (s.pending) {
		if (s.latency > 0) {
			s.latency--;
		}
		else {
			s.pending = false;
			s.burst_active = true;
		}
	}

	if (s.burst_active) {
		uint32_t byte_addr = (s.addr_curr << 3) & 0xffffff;

		uint32_t lo =
			(vram_ptr[byte_addr + 0] << 24) |
			(vram_ptr[byte_addr + 1] << 16) |
			(vram_ptr[byte_addr + 2] <<  8) |
			(vram_ptr[byte_addr + 3] <<  0);

		uint32_t hi =
			(vram_ptr[byte_addr + 4] << 24) |
			(vram_ptr[byte_addr + 5] << 16) |
			(vram_ptr[byte_addr + 6] <<  8) |
			(vram_ptr[byte_addr + 7] <<  0);

		s.dout_latched = (uint64_t(hi) << 32) | lo;

		dout = s.dout_latched;
		dout_ready = true;

		s.addr_curr++;
		if (s.burst_remaining > 0) {
			s.burst_remaining--;
		}
		if (s.burst_remaining == 0) {
			s.burst_active = false;
		}
	}
}

static uint32_t read_side_by_side_vram_32(const uint8_t *vram_ptr, uint32_t byte_addr) {
	uint32_t lane_off = (byte_addr & 0x400000) ? 4 : 0;
	uint32_t ddr_byte_addr = (((byte_addr & 0x3fffff) >> 2) << 3) + lane_off;

	return
		(vram_ptr[(ddr_byte_addr + 0) & 0x7fffff] << 24) |
		(vram_ptr[(ddr_byte_addr + 1) & 0x7fffff] << 16) |
		(vram_ptr[(ddr_byte_addr + 2) & 0x7fffff] <<  8) |
		(vram_ptr[(ddr_byte_addr + 3) & 0x7fffff] <<  0);
}

static uint32_t read_side_by_side_fb_32(const uint8_t *vram_ptr, uint32_t sof_offset, uint32_t pix_pair) {
	uint32_t lane_off = (sof_offset & 0x400000) ? 4 : 0;
	uint32_t word_addr = (((sof_offset & 0x3fffff) >> 2) + pix_pair) & 0xfffff;
	uint32_t ddr_byte_addr = (word_addr << 3) + lane_off;

	return
		(vram_ptr[(ddr_byte_addr + 0) & 0x7fffff] << 24) |
		(vram_ptr[(ddr_byte_addr + 1) & 0x7fffff] << 16) |
		(vram_ptr[(ddr_byte_addr + 2) & 0x7fffff] <<  8) |
		(vram_ptr[(ddr_byte_addr + 3) & 0x7fffff] <<  0);
}

static uint32_t read_linear_ddr_fb_32(const uint8_t *vram_ptr, uint32_t byte_addr) {
	uint32_t logical_word_addr = (byte_addr & 0x7fffff) >> 2;
	uint32_t lane_off = (logical_word_addr & 1) ? 4 : 0;
	uint32_t ddr_byte_addr = ((logical_word_addr >> 1) << 3) + lane_off;

	return
		(vram_ptr[(ddr_byte_addr + 0) & 0x7fffff] << 24) |
		(vram_ptr[(ddr_byte_addr + 1) & 0x7fffff] << 16) |
		(vram_ptr[(ddr_byte_addr + 2) & 0x7fffff] <<  8) |
		(vram_ptr[(ddr_byte_addr + 3) & 0x7fffff] <<  0);
}

static void write_disp_565(uint32_t pix_addr, uint16_t pix565);


static void write_ddr64(uint8_t *vram_ptr, uint32_t addr, uint64_t din, uint8_t be) {
	uint32_t byte_addr = (addr << 3) & 0xffffff;
	uint32_t lo = (uint32_t)(din & 0xffffffffull);
	uint32_t hi = (uint32_t)(din >> 32);

	uint8_t bytes[8] = {
		(uint8_t)(lo >> 24), (uint8_t)(lo >> 16), (uint8_t)(lo >> 8), (uint8_t)(lo >> 0),
		(uint8_t)(hi >> 24), (uint8_t)(hi >> 16), (uint8_t)(hi >> 8), (uint8_t)(hi >> 0)
	};

	for (uint32_t i = 0; i < 8; i++) {
		if (be & (1 << i)) {
			vram_ptr[(byte_addr + i) & 0xffffff] = bytes[i];
		}
	}
}


// Instantiation of module.
//Vsimtop* top = new Vsimtop;	// Verilator 4.224.
static Vsimtop* top;			// Verilator v5.002-117-g31d8b4cb8

/*
static uint16_t z_view_tag_snapshot[2][32][32];
static uint64_t z_view_z_snapshot[2][32][32];
static bool z_view_snapshot_valid[2] = {false, false};

#define Z_SNAPSHOT_COL(COL) \
	z_view_tag_snapshot[bank][row][COL] = static_cast<uint16_t>(zbuf->z_mem_inst_##COL##__DOT__tag_mem[row] & 0x0fff); \
	z_view_z_snapshot[bank][row][COL] = static_cast<uint64_t>(zbuf->z_mem_inst_##COL##__DOT__z_mem[row]) & 0x0000ffffffffffffULL

static void snapshot_z_bank_row(int bank, Vsimtop_z_buff__Ez1* zbuf, int row)
{
	if ((bank < 0) || (bank > 1) || !zbuf) return;
	row &= 31;

	Z_SNAPSHOT_COL(0);
	Z_SNAPSHOT_COL(1);
	Z_SNAPSHOT_COL(2);
	Z_SNAPSHOT_COL(3);
	Z_SNAPSHOT_COL(4);
	Z_SNAPSHOT_COL(5);
	Z_SNAPSHOT_COL(6);
	Z_SNAPSHOT_COL(7);
	Z_SNAPSHOT_COL(8);
	Z_SNAPSHOT_COL(9);
	Z_SNAPSHOT_COL(10);
	Z_SNAPSHOT_COL(11);
	Z_SNAPSHOT_COL(12);
	Z_SNAPSHOT_COL(13);
	Z_SNAPSHOT_COL(14);
	Z_SNAPSHOT_COL(15);
	Z_SNAPSHOT_COL(16);
	Z_SNAPSHOT_COL(17);
	Z_SNAPSHOT_COL(18);
	Z_SNAPSHOT_COL(19);
	Z_SNAPSHOT_COL(20);
	Z_SNAPSHOT_COL(21);
	Z_SNAPSHOT_COL(22);
	Z_SNAPSHOT_COL(23);
	Z_SNAPSHOT_COL(24);
	Z_SNAPSHOT_COL(25);
	Z_SNAPSHOT_COL(26);
	Z_SNAPSHOT_COL(27);
	Z_SNAPSHOT_COL(28);
	Z_SNAPSHOT_COL(29);
	Z_SNAPSHOT_COL(30);
	Z_SNAPSHOT_COL(31);

	z_view_snapshot_valid[bank] = true;
}

#undef Z_SNAPSHOT_COL
*/

char my_string[1024];

char serial_string[1024];
int serial_index = 0;

int str_i = 0;

unsigned int row;
unsigned int col;
unsigned int bank;
unsigned int dram_address;

int pix_count = 0;

unsigned char pix0_rgb[3];
unsigned char pix1_rgb[3];
unsigned char rgb[3];
bool prev_vsync = 0;
int frame_count = 0;

bool prev_hsync = 0;
int line_count = 0;

bool prev_sram_we_n = 0;

uint32_t inst_data_temp;

uint32_t prev_pc = 0xDEADBEEF;

unsigned int avm_byte_addr;
unsigned int avm_word_addr;

unsigned int burstcount;
unsigned int byteenable;
unsigned int writedata;

unsigned int datamux;	// What the aoR3000 core is actually reading from the bus! Only valid when avm_readdata_valid is High!
unsigned int datatemp;

unsigned int old_pc;
unsigned int inst_count = 0;

unsigned int old_hw_addr;
unsigned int hw_count = 0;

bool trigger1 = 0;
bool trigger2 = 0;

int trig_count = 0;

bool run_enable = 0;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 1024;


// Data
static IDXGISwapChain*          g_pSwapChain = NULL;
static ID3D11RenderTargetView*  g_mainRenderTargetView = NULL;

static void CreateRenderTarget()
{
	ID3D11Texture2D* pBackBuffer;
	g_pSwapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (LPVOID*)&pBackBuffer);
	if (FAILED(g_pd3dDevice->CreateRenderTargetView(pBackBuffer, NULL, &g_mainRenderTargetView))) {
		std::cerr << "Failed dx11 CreateRenderTargetView for g_mainRenderTargetView!" << std::endl;
	}
	pBackBuffer->Release();
}

static void CleanupRenderTarget()
{
	if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = NULL; }
}

HRESULT static CreateDeviceD3D(HWND hWnd)
{
	// Setup swap chain
	DXGI_SWAP_CHAIN_DESC sd;
	ZeroMemory(&sd, sizeof(sd));
	sd.BufferCount = 2;
	sd.BufferDesc.Width = 0;
	sd.BufferDesc.Height = 0;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferDesc.RefreshRate.Numerator = 60;
	sd.BufferDesc.RefreshRate.Denominator = 1;
	sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	sd.OutputWindow = hWnd;
	sd.SampleDesc.Count = 1;
	sd.SampleDesc.Quality = 0;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

	UINT createDeviceFlags = 0;
	//createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
	D3D_FEATURE_LEVEL featureLevel;
	const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0, };
	if (D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext) != S_OK)
		return E_FAIL;

	CreateRenderTarget();

	return S_OK;
}

static void CleanupDeviceD3D()
{
	CleanupRenderTarget();
	if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = NULL; }
	if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = NULL; }
	if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = NULL; }
}

extern LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
		return true;

	switch (msg)
	{
	case WM_SIZE:
		if (g_pd3dDevice != NULL && wParam != SIZE_MINIMIZED)
		{
			CleanupRenderTarget();
			g_pSwapChain->ResizeBuffers(0, (UINT)LOWORD(lParam), (UINT)HIWORD(lParam), DXGI_FORMAT_UNKNOWN, 0);
			CreateRenderTarget();
		}
		return 0;
	case WM_SYSCOMMAND:
		if ((wParam & 0xfff0) == SC_KEYMENU) // Disable ALT application menu
			return 0;
		break;
	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hWnd, msg, wParam, lParam);
}

static float values[90] = { 0 };
static int values_offset = 0;

bool dump_to_raw = 0;
int dump_cnt = 0;

vluint64_t main_time = 0;	// Current simulation time.
uint64_t bottleneck_cycles = 0;
uint64_t no_bottleneck_cycles = 0;
uint64_t isp_active_cycles = 0;
uint64_t tsp_active_cycles = 0;
uint64_t overlap_cycles = 0;
uint64_t isp_only_cycles = 0;
uint64_t tsp_only_cycles = 0;
uint64_t isp_wait_tsp_cycles = 0;
uint64_t tsp_wait_tex_cycles = 0;
uint64_t tsp_wait_cb_cycles = 0;
uint64_t bank_clear_wait_cycles = 0;

unsigned int file_size;

unsigned char buffer[16];

unsigned int rom_size = 1024 * 1024 * 4;	// 2MB. (32-bit wide).
uint32_t *rom_ptr = (uint32_t *) malloc(rom_size*4);

unsigned int ram_size = 1024 * 1024 * 16;	// 16MB. (64-bit wide).
uint64_t *ram_ptr = (uint64_t*)malloc(ram_size);

unsigned int pvr_size = 32768;				// 32K words (32-bit wide).
uint32_t *pvr_ptr = (uint32_t*)malloc(pvr_size*4);

unsigned int vram_size = 1024 * 1024 * 16;	// 16MB (8-bit wide).
uint8_t *vram_ptr = (uint8_t*)malloc(vram_size);

unsigned int z_size = 1024 * 1024 * 8;		// 4MB. (32-bit wide).
float *z_ptr = (float *)malloc(z_size*4);

unsigned int disp_size = 1024 * 1024 * 8;	// 8MB. (32-bit wide).
uint32_t *disp_ptr = (uint32_t *)malloc(disp_size);

static void sync_simtop_pvr_mirrors() {
	if (!top || !pvr_ptr) return;
	top->fb_w_sof1_mirror = pvr_ptr[0x060 >> 2];
}

static void write_disp_565(uint32_t pix_addr, uint16_t pix565) {
	uint8_t red   = ((pix565 >> 11) & 0x1f) << 3;
	uint8_t green = ((pix565 >> 5)  & 0x3f) << 2;
	uint8_t blue  = ((pix565 >> 0)  & 0x1f) << 3;
	disp_ptr[pix_addr & 0x7fffff] = 0xff << 24 | blue << 16 | green << 8 | red;
}

unsigned int tile_size = 1024 * 1024 * 8;
uint32_t *tile_ptr = (uint32_t*)malloc(tile_size);

bool tile_highlight = 0;
bool zoom = 0;
bool stop_on_last = 0;
int display_source = 1;		// 0 = direct fb_we preview, 1 = simulated DDR framebuffer.
int display_sof_select = 1;	// 0 = FB_R_SOF1, 1 = FB_W_SOF1.

static const char* vram_dump_names[] = {
	"logo",
	"doa2_kasumi",
	"menu",
	"menu2",
	"mem",
	"taxi",
	"taxi2",
	"taxi3",
	"taxi4",
	"crazy_title",
	"sonic",
	"sonic_title",
	"hydro_title",
	"looney_foghorn",
	"looney_startline",
	"sw_ep1_menu",
	"hotd2_title",
	"hotd2_zombies",
	"hotd2_selfie",
	"hotd2_car_fire",
	"hotd2_boat",
	"hotd2_gargoyle",
	"rayman_title",
	"rayman_lights",
	"rayman_level",
	"xtreme_intro",
	"daytona_intro",
	"daytona_behind",
	"daytona_front",
	"daytona_sanic",
	"toy_front",
	"18wheel_select"
};
static int vram_dump_index = 27;

static const uint32_t tile_trace_size = 64;
static uint32_t tile_trace_argb[tile_trace_size];
static uint16_t tile_trace_x[tile_trace_size];
static uint16_t tile_trace_y[tile_trace_size];
static uint32_t tile_trace_wr = 0;
static uint32_t tile_trace_count = 0;


double sc_time_stamp () {	// Called by $time in Verilog.
	return main_time;
}


uint32_t bios_word;

#define MIN(i, j) (((i) < (j)) ? (i) : (j))
#define MAX(i, j) (((i) > (j)) ? (i) : (j))

static float mmin(float a, float b, float c, float d)
{
	float rv = MIN(a, b);
	rv = MIN(c, rv);
	return MAX(d, rv);
}

static float mmax(float a, float b, float c, float d)
{
	float rv = MAX(a, b);
	rv = MAX(c, rv);
	return MIN(d, rv);
}

#define pvr_access(mod) top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__##mod;


uint32_t disp_addr;

bool ra_running = 0;


inline int32_t float_to_fixed(float d, uint32_t p)
{
	int32_t temp = d * (1<<p);
	return temp;
}

inline float fixed_to_float(int d, uint32_t p)
{
	return float(d * (1>>p));
}

inline int32_t MUL_PREC(int32_t a, int32_t b, int PREC) {
	return (((int64_t)a) * b)>>PREC;
}


int load_vram_dump(const char* name) {
	FILE* pvrfile;
	FILE* vram_file;

	sprintf(my_string, "pvr_regs_%s.bin", name); pvrfile = fopen(my_string, "rb");
	if (pvrfile != NULL) printf("\n%s dump loaded OK.\n", my_string);
	else { printf("\n%s dump file not found!\n", my_string); return 0; }
	fseek(pvrfile, 0L, SEEK_END);
	file_size = ftell(pvrfile);
	fseek(pvrfile, 0L, SEEK_SET);
	fread(pvr_ptr, 1, pvr_size, pvrfile);

	/*
	for (int i=0; i<8192; i++) {
		top->rootp->simtop__DOT__pvr_reg_cs = 1;
		top->rootp->simtop__DOT__pvr_wr = 1;
		top->rootp->simtop__DOT__dm_req_addr  = 0x005f7c00 + (i<<2);	// dm_req_addr is the BYTE address!
		top->rootp->simtop__DOT__dm_req_wdata = pvr_ptr[i];	// 32-bit WORD address!
		top->clk = 0;
		top->eval();            // Evaluate model!
		top->clk = 1;
		top->eval();            // Evaluate model!
	}
	top->rootp->simtop__DOT__pvr_reg_cs = 0;
	top->rootp->simtop__DOT__pvr_wr = 0;
	*/

	top->rootp->simtop__DOT__pvr__DOT__PARAM_BASE  = pvr_ptr[0x020 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__REGION_BASE = pvr_ptr[0x02C >> 2];
	
	top->rootp->simtop__DOT__pvr__DOT__FB_R_SOF1 = pvr_ptr[0x050 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__FB_R_SOF2 = pvr_ptr[0x054 >> 2];

	top->rootp->simtop__DOT__pvr__DOT__FB_W_SOF1 = pvr_ptr[0x060 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__FB_W_SOF2 = pvr_ptr[0x064 >> 2];
	sync_simtop_pvr_mirrors();

	top->rootp->simtop__DOT__pvr__DOT__FPU_SHAD_SCALE = pvr_ptr[0x074 >> 2];

	//top->rootp->simtop__DOT__pvr__DOT__FPU_CULL_VAL  = pvr_ptr[0x078 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__FPU_PARAM_CFG = pvr_ptr[0x07C >> 2];

	top->rootp->simtop__DOT__pvr__DOT__ISP_BACKGND_D = pvr_ptr[0x088 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__ISP_BACKGND_T = pvr_ptr[0x08C >> 2];

	top->rootp->simtop__DOT__pvr__DOT__TEXT_CONTROL  = pvr_ptr[0x0E4 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__PAL_RAM_CTRL  = pvr_ptr[0x108 >> 2];
	top->rootp->simtop__DOT__pvr__DOT__TA_ALLOC_CTRL = pvr_ptr[0x140 >> 2];

	// Copy palette RAM from pvr_regs into actual palette RAM in the Texture Address module.
	for (int i = 0; i < 1024; i++) {
		top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__pal_ram[i] = pvr_ptr[(0x1000 >> 2) + i];
	}

	sprintf(my_string, "vram_%s.bin", name); vram_file = fopen(my_string, "rb");
	if (vram_file != NULL) printf("\n%s dump loaded OK.\n", my_string);
	else { printf("\n%s dump file not found!\n", my_string); return 0; }
	fseek(vram_file, 0L, SEEK_END);
	file_size = ftell(vram_file);
	fseek(vram_file, 0L, SEEK_SET);
	uint8_t* vram_file_buf = (uint8_t*)malloc(vram_size);
	if (!vram_file_buf) {
		printf("\nFailed to allocate vram_file_buf!\n");
		fclose(pvrfile);
		fclose(vram_file);
		return 0;
	}
	memset(vram_file_buf, 0, vram_size);
	fread(vram_file_buf, 1, vram_size, vram_file);

	memset(vram_ptr, 0, vram_size);
	const size_t bank_size = 0x400000;
	const size_t lower_size = (file_size < bank_size) ? file_size : bank_size;
	const size_t upper_size = (file_size > bank_size)
		? ((file_size - bank_size < bank_size) ? (file_size - bank_size) : bank_size)
		: 0;
	const size_t max_word_bytes = (lower_size > upper_size) ? lower_size : upper_size;
	const size_t word_count = (max_word_bytes + 3) / 4;

	for (size_t word = 0; word < word_count; ++word) {
		const size_t lower_off = word * 4;
		const size_t upper_off = bank_size + (word * 4);
		const size_t out_off = word * 8;

		if (out_off + 7 >= vram_size) {
			break;
		}

		for (size_t b = 0; b < 4; ++b) {
			if (lower_off + b < lower_size) {
				vram_ptr[out_off + b] = vram_file_buf[lower_off + (3 - b)];
			}
			if (upper_off + b < bank_size + upper_size) {
				vram_ptr[out_off + 4 + b] = vram_file_buf[upper_off + (3 - b)];
			}
		}
	}

	free(vram_file_buf);

	fclose(pvrfile);
	fclose(vram_file);

	return 1;
}


/*
	Surface equation solver
*/
struct PlaneStepper3
{
	float FZ3_sub_FZ1, FY2_sub_FY1;
	float FZ2_sub_FZ1, FY3_sub_FY1;
	float Aa_mult_1, Aa_mult_2, Aa;

	float FX3_sub_FX1, FX2_sub_FX1;
	float Ba_mult_1, Ba_mult_2, Ba;

	float BIG_C, C_mult_1, C_mult_2;

	float ddx, ddy;
	float small_c;

	void Setup(float x1,float x2,float x3,float y1,float y2,float y3,float z1,float z2,float z3)
	{
		FZ3_sub_FZ1 = (z3 - z1);
		FY2_sub_FY1 = (y2 - y1);
		Aa_mult_1 = FZ3_sub_FZ1 * FY2_sub_FY1;

		FZ2_sub_FZ1 = (z2 - z1);
		FY3_sub_FY1 = (y3 - y1);
		Aa_mult_2 = FZ2_sub_FZ1 * FY3_sub_FY1;
		Aa = Aa_mult_1 - Aa_mult_2;

		FX3_sub_FX1 = (x3 - x1);
		Ba_mult_1 = FX3_sub_FX1 * FZ2_sub_FZ1;

		FX2_sub_FX1 = (x2 - x1);
		Ba_mult_2 = FX2_sub_FX1 * FZ3_sub_FZ1;
		Ba = Ba_mult_1 - Ba_mult_2;

		// Determinant of a 3x3 matrix formed by the three points (x1, y1), (x2, y2), and (x3, y3).
		C_mult_1 = FX2_sub_FX1 * FY3_sub_FY1;
		C_mult_2 = FX3_sub_FX1 * FY2_sub_FY1;
		BIG_C = C_mult_2 - C_mult_1;  // Swapped the order of subtraction, so we can ditch the neg sign on -C below...

		ddx = Aa / BIG_C;
		ddy = Ba / BIG_C;
		small_c = (z1 - ddx * x1 - ddy * y1);
	}

	__forceinline float Ip(float x, float y) const { return x * ddx + y * ddy + small_c; }
};


union mem128i {
	uint8_t m128i_u8[16];
	int8_t m128i_i8[16];
	int16_t m128i_i16[8];
	int32_t m128i_i32[4];
	uint32_t m128i_u32[4];
};

// Clamp and flip a texture coordinate
static int ClampFlip(bool pp_Clamp, bool pp_Flip, int coord, int size) {
	if (pp_Clamp) {			// clamp
		if (coord < 0) coord = 0;
		else if (coord >= size) coord = size-1;
	}
	else if (pp_Flip) {		// flip
		if ((coord &= size*2-1) & size) coord ^= size*2-1;
	}
	else coord &= size-1;

	return coord;
}


// byte offsets for mipmaps for 4bpp and 8bpp paletted textures
static unsigned const mipmap_byte_offset_pal[11] ={
	0x3, 0x4, 0x8, 0x18, 0x58, 0x158, 0x558, 0x1558, 0x5558, 0x15558, 0x55558
};

// byte offsets for mipmaps for VQ textures
static unsigned const mipmap_byte_offset_vq[11] ={
	0x0, 0x1, 0x2, 0x6, 0x16, 0x56, 0x156, 0x556, 0x1556, 0x5556, 0x15556
};

// byte offsets for mipmaps for "normal" textures
static unsigned const mipmap_byte_offset_norm[11] ={
	0x6, 0x8, 0x10, 0x30, 0xb0, 0x2b0, 0xab0, 0x2ab0, 0xaab0, 0x2aab0, 0xaaab0
};

uint32_t twiddle_slow(uint32_t x, uint32_t y, uint32_t x_sz, uint32_t y_sz)
{
	uint32_t rv=0;//low 2 bits are directly passed  -> needs some misc stuff to work.
	//However, Pvr internally maps the 64b banks "as if" they were twiddled :p

	uint32_t sh=0;
	x_sz>>=1;
	y_sz>>=1;
	while (x_sz!=0 || y_sz!=0)
	{
		if (y_sz)
		{
			uint32_t temp=y&1;
			rv|=temp<<sh;
			y_sz>>=1;
			y>>=1;
			sh++;
		}
		if (x_sz)
		{
			uint32_t temp=x&1;
			rv|=temp<<sh;
			x_sz>>=1;
			x>>=1;
			sh++;
		}
	}
	return rv;
}

uint32_t tex_addr = 0;
uint32_t texel_offs = 0;

PlaneStepper3 Z;
PlaneStepper3 U;
PlaneStepper3 V;

/*
uint32_t detwiddle[2][8][1024];
#define twop(x,y,bcx,bcy) (detwiddle[0][bcy][x]+detwiddle[1][bcx][y])

void BuildTwiddleTables()
{
	for (uint32_t s=0; s<8; s++)
	{
		uint32_t x_sz=1024;
		uint32_t y_sz=8<<s;
		for (uint32_t i=0; i<x_sz; i++)
		{
			detwiddle[0][s][i]=twiddle_slow(i, 0, x_sz, y_sz);
			detwiddle[1][s][i]=twiddle_slow(0, i, y_sz, x_sz);
		}
	}
}
*/

/*
uint32_t read_vram_32(uint32_t addr) {		// BYTE address!
	uint8_t byte0 = vram_ptr[ (addr+0)&0x7fffff ];
	uint8_t byte1 = vram_ptr[ (addr+1)&0x7fffff ];
	uint8_t byte2 = vram_ptr[ (addr+2)&0x7fffff ];
	uint8_t byte3 = vram_ptr[ (addr+3)&0x7fffff ];

	uint32_t data =  (byte3<<24) | (byte2<<16) | (byte1<<8) | byte0;

	return data;
};

QData read_vram_64(uint32_t addr) {		// BYTE address!
	uint8_t byte0 = vram_ptr[ (addr+0)&0x7fffff ];
	uint8_t byte1 = vram_ptr[ (addr+1)&0x7fffff ];
	uint8_t byte2 = vram_ptr[ (addr+2)&0x7fffff ];
	uint8_t byte3 = vram_ptr[ (addr+3)&0x7fffff ];

	uint8_t byte4 = vram_ptr[ (0x400000+addr+0)&0x7fffff ];
	uint8_t byte5 = vram_ptr[ (0x400000+addr+1)&0x7fffff ];
	uint8_t byte6 = vram_ptr[ (0x400000+addr+2)&0x7fffff ];
	uint8_t byte7 = vram_ptr[ (0x400000+addr+3)&0x7fffff ];

	QData upper_word = static_cast<QData>((byte7<<24) | (byte6<<16) | (byte5<<8) | (byte4));
	QData lower_word = static_cast<QData>((byte3<<24) | (byte2<<16) | (byte1<<8) | (byte0));

	QData data = (upper_word<<32) | lower_word;

	return data;
};
*/

static uint32_t f32(double d)
{
	float f = (float)d;
	uint32_t u;
	memcpy(&u, &f, sizeof(u));
	return u;
}

static double fixed_to_float(int64_t v, int frac_bits)
{
	return (double)v / (double)(1LL << frac_bits);
}

static inline int64_t sign_extend_48(uint64_t v)
{
	// If bit 47 is set, extend the sign
	if (v & (1ULL << 47))
		return (int64_t)(v | 0xFFFF000000000000ULL);
	else
		return (int64_t)v;
}

static void test_interp_once(
	Vsimtop* top,
	double ax, double ay, double az,
	double bx, double by, double bz,
	double cx, double cy, double cz,
	int x_ps, int y_ps
)
{
	// Enforce invariant
	top->rootp->FRAC_DIFF =
		top->rootp->Z_FRAC_BITS - top->rootp->FRAC_BITS;

	// Drive float inputs (ONLY floats)
	top->rootp->vert_a_x = f32(ax);
	top->rootp->vert_a_y = f32(ay);
	top->rootp->vert_a_z = f32(az);

	top->rootp->vert_b_x = f32(bx);
	top->rootp->vert_b_y = f32(by);
	top->rootp->vert_b_z = f32(bz);

	top->rootp->vert_c_x = f32(cx);
	top->rootp->vert_c_y = f32(cy);
	top->rootp->vert_c_z = f32(cz);

	top->rootp->x_ps = x_ps;
	top->rootp->y_ps = y_ps;

	// Combinational design ? one eval is enough
	top->eval();

	// Read back fixed-point values
	int64_t FX1 = (int64_t)top->rootp->FX1_FIXED;
	int64_t FY1 = (int64_t)top->rootp->FY1_FIXED;
	int64_t FZ1 = (int64_t)top->rootp->FZ1_FIXED;

	int64_t FX2 = (int64_t)top->rootp->FX2_FIXED;
	int64_t FY2 = (int64_t)top->rootp->FY2_FIXED;
	int64_t FZ2 = (int64_t)top->rootp->FZ2_FIXED;

	int64_t FX3 = (int64_t)top->rootp->FX3_FIXED;
	int64_t FY3 = (int64_t)top->rootp->FY3_FIXED;
	int64_t FZ3 = (int64_t)top->rootp->FZ3_FIXED;

	int64_t C   = (int64_t)top->rootp->BIG_C_z;
	int64_t IPZ = (int64_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__IP_Z_R[0];

	printf("Triangle:\n");
	printf("  A(%7.3f,%7.3f,%7.3f)\n", ax, ay, az);
	printf("  B(%7.3f,%7.3f,%7.3f)\n", bx, by, bz);
	printf("  C(%7.3f,%7.3f,%7.3f)\n", cx, cy, cz);
	printf("  Sample: x=%d y=%d\n", x_ps, y_ps);

	printf("FX1=%f FY1=%f FZ1=%f\n",
		fixed_to_float(sign_extend_48(FX1), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FY1), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FZ1), top->rootp->Z_FRAC_BITS));

	printf("FX2=%f FY2=%f FZ2=%f\n",
		fixed_to_float(sign_extend_48(FX2), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FY2), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FZ2), top->rootp->Z_FRAC_BITS));

	printf("FX3=%f FY3=%f FZ3=%f\n",
		fixed_to_float(sign_extend_48(FX3), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FY3), top->rootp->FRAC_BITS),
		fixed_to_float(sign_extend_48(FZ3), top->rootp->Z_FRAC_BITS));

	printf("BIG_C = %lld\n", (long long)C);

	printf("IP_Z_INTERP = %f\n\n",
		fixed_to_float(sign_extend_48(IPZ), top->rootp->Z_FRAC_BITS));
}


uint8_t index_byte = 0;
uint32_t vq_tex_index = 0;
uint32_t vram_word_addr;

uint32_t vq_index_addr = 0;

bool sgn = 0;

float invW = 0;

float mult1 = 0;
float mult2 = 0;
float mult3 = 0;
float mult4 = 0;
float mult5 = 0;
float mult6 = 0;
float mult7 = 0;
float mult8 = 0;

volatile float sim_ip_u;
volatile float sim_ip_v;
volatile float sim_u_divz;
volatile float sim_v_divz;

volatile uint32_t sim_ui_raw;
volatile uint32_t sim_vi_raw;

volatile uint32_t sim_ui_flipped;
volatile uint32_t sim_vi_flipped;

void rasterize_triangle_fixed(float x1, float x2, float x3, float x4,
							  float y1, float y2, float y3, float y4,
							  float z1, float z2, float z3, float z4,
							  float u1, float u2, float u3, float u4,
							  float v1, float v2, float v3, float v4) {

	// Lazy culling...
	// (now done in Verilog / isp_parser).
	//if (x1>639 || x2>639 || x3>639 || y1>479 || y2>479 || y3>479) return;
	//if (x1<0 || x2<0 || x3<0 || y1<0 || y2<0 || y3<0) return;				// Hide spikey bits / neg values.

	/*
	top->rootp->fp_x1 = (int32_t)x1;
	top->rootp->fp_y1 = (int32_t)y1;

	top->rootp->fp_x2 = (int32_t)x2;
	top->rootp->fp_y2 = (int32_t)y2;

	top->rootp->fp_x3 = (int32_t)x3;
	top->rootp->fp_y3 = (int32_t)y3;

	top->rootp->fp_x4 = (int32_t)x4;
	top->rootp->fp_y4 = (int32_t)y4;
	*/

	/*
	// Convert floats to Fixed-point coords.
	const int FX1 = float_to_fixed(x1, FRAC_BITS);
	const int FX2 = float_to_fixed(x2, FRAC_BITS);
	const int FX3 = float_to_fixed(x3, FRAC_BITS);
	const int FX4 = float_to_fixed(x4, FRAC_BITS);

	const int FY1 = float_to_fixed(y1, FRAC_BITS);
	const int FY2 = float_to_fixed(y2, FRAC_BITS);
	const int FY3 = float_to_fixed(y3, FRAC_BITS);
	const int FY4 = float_to_fixed(y4, FRAC_BITS);

	const int FZ1 = float_to_fixed(z1, FRAC_BITS);
	const int FZ2 = float_to_fixed(z2, FRAC_BITS);
	const int FZ3 = float_to_fixed(z3, FRAC_BITS);
	*/

	/*
	top->rootp->FX1 = FX1;
	top->rootp->FX2 = FX2;
	top->rootp->FX3 = FX3;
	top->rootp->FX4 = FX4;

	top->rootp->FY1 = FY1;
	top->rootp->FY2 = FY2;
	top->rootp->FY3 = FY3;
	top->rootp->FY4 = FY4;
	*/

	// Fixed-point Deltas
	/*
	const int FDX12 = sgn ? (FX2-FX1) : (FX1-FX2);
	const int FDX23 = sgn ? (FX3-FX2) : (FX2-FX3);
	const int FDX31 = sgn ? (FX1-FX3) : (FX3-FX1);
	const int FDX41 = (x4 || y4) ? sgn ? (FX1-FX4) : (FX4-FX1) : 0;
	//printf("fixed FDX12: %f  FDX23: %f  FDX31: %f\n", ((float)FDX12/1<<FRAC_BITS), ((float)FDX23/1<<FRAC_BITS), ((float)FDX31/1<<FRAC_BITS));

	const int FDY12 = sgn ? (FY2-FY1) : (FY1-FY2);
	const int FDY23 = sgn ? (FY3-FY2) : (FY2-FY3);
	const int FDY31 = sgn ? (FY1-FY3) : (FY3-FY1);
	const int FDY41 = (x4 || y4) ? sgn ? (FY1-FY4) : (FY4-FY1) : 0;
	//printf("fixed FDY12: %f  FDY23: %f  FDY31: %f\n", ((float)FDY12/1<<FRAC_BITS), ((float)FDY23/1<<FRAC_BITS), ((float)FDY31/1<<FRAC_BITS));
	*/

	uint16_t core_x_ps = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__x_ps;
	uint16_t core_y_ps = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__y_ps;

	// Half-edge constants (float version).
	/*
	float f_area = (x1-x3) * (y2-y3) - (y1-y3) * (x2-x3);
	sgn = (f_area<=0);
	*/

	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__sgn = sgn;

	/*
	bool is_quad_array = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__is_quad_array;

	const float fdx12 = (sgn) ? (x1 - x2) : (x2 - x1);
	const float fdx23 = (sgn) ? (x2 - x3) : (x3 - x2);
	const float fdx31 = (is_quad_array) ? sgn ? (x3 - x4) : (x4 - x3) : sgn ? (x3 - x1) : (x1 - x3);
	const float fdx41 = (is_quad_array) ? sgn ? (x4 - x1) : (x1 - x4) : 0;

	const float fdy12 = sgn ? (y1 - y2) : (y2 - y1);
	const float fdy23 = sgn ? (y2 - y3) : (y3 - y2);
	const float fdy31 = (is_quad_array) ? sgn ? (y3 - y4) : (y4 - y3) : sgn ? (y3 - y1) : (y1 - y3);
	const float fdy41 = (is_quad_array) ? sgn ? (y4 - y1) : (y1 - y4) : 0;
	*/

	/*
	mult1 = (fdy12 * x1);
	mult2 = (fdx12 * y1);
	float c1 = mult1 - mult2;

	mult3 = (fdy23 * x2);
	mult4 = (fdx23 * y2);
	float c2 = mult3 - mult4;

	mult5 = (fdy31 * x3);
	mult6 = (fdx31 * y3);
	float c3 = mult5 - mult6;

	mult7 = (fdy41 * x4);
	mult8 = (fdx41 * y4);
	float c4 = (is_quad_array) ? mult7 - mult8 : 1;

	float Xhs12 = c1 + (fdx12*core_y_ps) - (fdy12*core_x_ps);
	float Xhs23 = c2 + (fdx23*core_y_ps) - (fdy23*core_x_ps);
	float Xhs31 = c3 + (fdx31*core_y_ps) - (fdy31*core_x_ps);
	float Xhs41 = c4 + (fdx41*core_y_ps) - (fdy41*core_x_ps);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTriangle = (Xhs12>=0) && (Xhs23>=0) && (Xhs31>=0) && (Xhs41>=0);
	*/

	/*
	int32_t FDX12 = float_to_fixed(fdx12,FRAC_BITS);
	int32_t FDX23 = float_to_fixed(fdx23,FRAC_BITS);
	int32_t FDX31 = float_to_fixed(fdx31,FRAC_BITS);
	int32_t FDX41 = float_to_fixed(fdx41,FRAC_BITS);

	int32_t FDY12 = float_to_fixed(fdy12,FRAC_BITS);
	int32_t FDY23 = float_to_fixed(fdy23,FRAC_BITS);
	int32_t FDY31 = float_to_fixed(fdy31,FRAC_BITS);
	int32_t FDY41 = float_to_fixed(fdy41,FRAC_BITS);

	top->rootp->fp_dx12 = fdx12;
	top->rootp->fp_dx23 = fdx23;
	top->rootp->fp_dx31 = fdx31;
	top->rootp->fp_dx41 = fdx41;
	
	top->rootp->fp_dy12 = fdy12;
	top->rootp->fp_dy23 = fdy23;
	top->rootp->fp_dy31 = fdy31;
	top->rootp->fp_dy41 = fdy41;
	*/

	// Bounding rectangle
	//int minx = min(FX1,FX2,FX3)>>16;
	//int maxx = max(FX1,FX2,FX3)>>16;
	//int miny = min(FY1,FY2,FY3)>>16;
	//int maxy = max(FY1,FY2,FY3)>>16;

	// Half-edge constants
	//int C1 = FDY12 * FX1 - FDX12 * FY1;
	//int C2 = FDY23 * FX2 - FDX23 * FY2;
	//int C3 = FDY31 * FX3 - FDX31 * FY3;
	//int C4 = FDY41 * FX4 - FDX41 * FY1;
	/*
	int FDY12_MULT = MUL_PREC(FDY12, FX1, FRAC_BITS); int FDX12_MULT = MUL_PREC(FDX12, FY1, FRAC_BITS);
	int FDY23_MULT = MUL_PREC(FDY23, FX2, FRAC_BITS); int FDX23_MULT = MUL_PREC(FDX23, FY2, FRAC_BITS);
	int FDY31_MULT = MUL_PREC(FDY31, FX3, FRAC_BITS); int FDX31_MULT = MUL_PREC(FDX31, FY3, FRAC_BITS);
	int FDY41_MULT = MUL_PREC(FDY41, FX4, FRAC_BITS); int FDX41_MULT = MUL_PREC(FDX41, FY4, FRAC_BITS);
	//printf("fixed FDY12_MULT: %f  FDX12_MULT: %f\n\n", ((float)FDY12_MULT/(1<<FRAC_BITS), ((float)FDX12_MULT/1<<FRAC_BITS) );

	int C1 = FDY12_MULT - FDX12_MULT;
	int C2 = FDY23_MULT - FDX23_MULT;
	int C3 = FDY31_MULT - FDX31_MULT;
	int C4 = (x4 || y4) ? FDY41_MULT - FDX41_MULT : 1;
	*/
	//printf("fixed C1: %f  fixed C2: %f  fixed C3: %f\n\n", ((float)C1/1<<FRAC_BITS), ((float)C2/1<<FRAC_BITS), ((float)C3/1<<FRAC_BITS));

	// Correct for fill convention
	//if ((FDY12>>FRAC_BITS) < 0 || (FDY12>>FRAC_BITS) == 0 && (FDX12>>FRAC_BITS) > 0) C1=C1+(1<<FRAC_BITS);
	//if ((FDY23>>FRAC_BITS) < 0 || (FDY23>>FRAC_BITS) == 0 && (FDX23>>FRAC_BITS) > 0) C2=C2+(1<<FRAC_BITS);
	//if ((FDY31>>FRAC_BITS) < 0 || (FDY31>>FRAC_BITS) == 0 && (FDX31>>FRAC_BITS) > 0) C3=C3+(1<<FRAC_BITS);

	// Texture size values are 0=8, 1=16, 2=32, 3=64, 4=128, etc.
	//uint32_t tex_u_size_full = 8<<(top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_size&7);
	//uint32_t tex_v_size_full = 8<<(top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_v_size&7);
	uint32_t tex_u_size_full = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_size_full;
	uint32_t tex_v_size_full = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_size_full;
	

	//int halfpixel = 1<<(FRAC_BITS-1);
	//int y_ps = miny /*+ halfpixel*/;
	//int minx_ps = minx /*+ halfpixel*/;

	//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_entry_valid) {
	//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__render_poly) {
		//bool vertex_offset = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__strip_cnt&1;

		/*
		// 0=No culling, 1=Cull if Small, 2= Cull if Neg, 3=Cull if Pos.
		uint8_t cullmode   = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__culling_mode;

		// cull
		if(cullmode != 0) {
			float abs_area = fabsf(f_area);
			if (abs_area < *(float*)&top->rootp->simtop__DOT__pvr__DOT__FPU_CULL_VAL) return;

			if(cullmode >= 2) {
				//uint32_t mode = vertex_offset ^ (cullmode&1);
				uint32_t mode = (cullmode&1);
				if ((mode==0 && f_area < 0) || 
					(mode==1 && f_area > 0)) return;
			}
		}
		*/
		
		/*
		top->FDX12 = FDX12;
		top->FDY12 = FDY12;

		top->FDX23 = FDX23;
		top->FDY23 = FDY23;

		top->FDX31 = FDX31;
		top->FDY31 = FDY31;

		top->FDX41 = FDX41;
		top->FDY41 = FDY41;

		top->FZ1 = FZ1;
		top->FZ2 = FZ2;
		top->FZ3 = FZ3;
		*/

		Z.Setup(x1,x2,x3, y1,y2,y3, z1,z2,z3);

		int w = tex_u_size_full/*+1*/;
		int h = tex_v_size_full/*+1*/;
		U.Setup(x1,x2,x3, y1,y2,y3, u1*w*z1, u2*w*z2, u3*w*z3);
		V.Setup(x1,x2,x3, y1,y2,y3, v1*h*z1, v2*h*z2, v3*h*z3);
	//}

	invW       = Z.Ip((float)core_x_ps, (float)core_y_ps);	// Interpolate the Z value, based on X and Y.
	//invW       = (float)((int64_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_out) / (1 << Z_FRAC_BITS);

	sim_ip_u   = U.Ip((float)core_x_ps, (float)core_y_ps);	// Interpolate the U value, based on X and Y.
	sim_ip_v   = V.Ip((float)core_x_ps, (float)core_y_ps);	// Interpolate the V value, based on X and Y.
	sim_u_divz = sim_ip_u / invW;
	sim_v_divz = sim_ip_v / invW;

	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__IP_U_INTERP = float_to_fixed(sim_ip_u,FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__IP_V_INTERP = float_to_fixed(sim_ip_v,FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__u_div_z_fixed = float_to_fixed(sim_u_divz, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__v_div_z_fixed = float_to_fixed(sim_v_divz, FRAC_BITS);

	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__C    = float_to_fixed(U.C, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__c    = float_to_fixed(U.c, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__FDDX = float_to_fixed(U.ddx, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__FDDY = float_to_fixed(U.ddy, FRAC_BITS);
	
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_v__DOT__C    = float_to_fixed(V.C, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_v__DOT__c    = float_to_fixed(V.c, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_v__DOT__FDDX = float_to_fixed(V.ddx, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_v__DOT__FDDY = float_to_fixed(V.ddy, FRAC_BITS);

	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_z__DOT__C    = float_to_fixed(Z.C, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_z__DOT__c    = float_to_fixed(Z.c, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_z__DOT__FDDX = float_to_fixed(Z.ddx, FRAC_BITS);
	//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_z__DOT__FDDY = float_to_fixed(Z.ddy, FRAC_BITS);

	bool pp_FlipU  = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_flip;
	bool pp_FlipV  = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_v_flip;
	bool pp_ClampU = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_clamp;
	bool pp_ClampV = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_v_clamp;

	//printf("flipu: %d  flipv: %d  clampu: %d  clampv: %d\n", pp_FlipU, pp_FlipV, pp_ClampU, pp_ClampV);

	sim_ui_flipped = ClampFlip(pp_ClampU, pp_FlipU, sim_u_divz, tex_u_size_full);
	sim_vi_flipped = ClampFlip(pp_ClampV, pp_FlipV, sim_v_divz, tex_v_size_full);

	// Shove ui and vi into the core...
	top->sim_ui = sim_ui_flipped;
	top->sim_vi = sim_vi_flipped;

	vram_word_addr = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vram_word_addr << 3;

	uint8_t alpha = 0xff;

	/*
	if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture) {
		float u = U.Ip( (float)core_x_ps, (float)core_y_ps ) * 1/invW;
		float v = V.Ip( (float)core_x_ps, (float)core_y_ps ) * 1/invW;

		bool pp_FlipU  = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_flip;
		bool pp_FlipV  = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_flip;
		bool pp_ClampU = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_clamp;
		bool pp_ClampV = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_clamp;

		//printf("flipu: %d  flipv: %d  clampu: %d  clampv: %d\n", pp_FlipU, pp_FlipV, pp_ClampU, pp_ClampV);

		// Float to uint...
		uint32_t ui = u;
		uint32_t vi = v;

		ui = ClampFlip(pp_ClampU, pp_FlipU, ui, tex_u_size_full);
		vi = ClampFlip(pp_ClampV, pp_FlipV, vi, tex_v_size_full);

		bool scan_order_flag = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__scan_order;
		if (scan_order_flag==0) texel_offs = twiddle_slow(ui,vi,tex_u_size_full,tex_v_size_full);
		else texel_offs = ui + (vi * tex_u_size_full);	// Non-Twiddled..

		uint16_t tex_u_size_raw = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_size;
		uint16_t tex_v_size_raw = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_size;

		bool mipmap_flag = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__mip_map;

		// Says "64-bit word addr" on PDF page 212 of the System Architecture manual...
		// But I think they meant 64-bit DATA, and 32-bit ADDRESS, since the textures are fetched as 64-bit data on the PVR2?
		// 
		// An example tcw_word value for the "Play" texture on the Menu is 0x140C8E00.
		// The lower 21 bits masked would give 0xC8E00. This is the 32-bit WORD address of the texture...
		// 
		// NOTE: The above is kind of wrong. The "width" of the address depends on the data bus width.
		// Textures on PVR2 are (usually) read via the full 64-bit data bus, with the lower 32-bit word in the lower 4MB,
		// and the upper 32-bit word in the upper 4MB (the words are interleaved).
		// 
		// The 8MB VRAM on Dreamcast is split into two 32-bit wide banks. They each have their own address.
		// So each half of VRAM can be read as 32-bit wide (for params etc.), or combined, to read as 64-bit wide for textures etc.
		// 
		tex_addr = (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tcw_word&0x1fffff) << 3;	// BYTE addr.

		// Shove ui and vi into the core...
		top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__ui = ui;
		top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__vi = vi;

		// Read the values from the core (I realize this will be delayed by one verilog eval cycle, but it's good enough for testing).
		uint32_t tex_addr_core = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__tex_word_addr << 3; // Make BYTE addr!
		uint32_t mipmap_byte_offs_core	= top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__mipmap_byte_offs;
		uint32_t twop_core     = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__twop;

		vram_word_addr = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__vram_word_addr<<3;

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vq_comp) {
			uint32_t mipmap_vq_offs = (mipmap_flag) ? mipmap_byte_offset_vq[tex_u_size_raw+3] : 0;

			// Don't ask. lol...
			uint32_t my_addr = ((twop_core&0xffffffe0)>>1) | (twop_core&0xf);
			vq_index_addr = ((twop_core&0x10)<<18) + tex_addr_core + 1024 + (mipmap_vq_offs>>1) + (my_addr>>2);
			uint8_t index_byte = vram_ptr[ vq_index_addr & 0xffffff ];

			uint16_t texel_pix0 = 0x0000;
			uint16_t texel_pix1 = 0x0000;
			uint16_t texel_pix2 = 0x0000;
			uint16_t texel_pix3 = 0x0000;
			uint16_t texel_pix = 0x0000;

			// Group of FOUR 16-bit texels (8 CODE BOOK Bytes) per index_byte.
			// (but we only shift by <<2 here, because we read a 32-bit word from both the lower and upper 4MB VRAM.)
			switch ( my_addr&3 ) {
				case 0: texel_pix  = vram_ptr[ (tex_addr_core + (index_byte<<3) + 0) & 0xffffff ];
						texel_pix |= vram_ptr[ (tex_addr_core + (index_byte<<3) + 1) & 0xffffff ] << 8; break;
					
				case 1: texel_pix  = vram_ptr[ (tex_addr_core + (index_byte<<3) + 2) & 0xffffff ];
						texel_pix |= vram_ptr[ (tex_addr_core + (index_byte<<3) + 3) & 0xffffff ] << 8; break;
					
				case 2: texel_pix  = vram_ptr[ (tex_addr_core + (index_byte<<3) + 4) & 0xffffff ];
						texel_pix |= vram_ptr[ (tex_addr_core + (index_byte<<3) + 5) & 0xffffff ] << 8; break;
					
				case 3: texel_pix  = vram_ptr[ (tex_addr_core + (index_byte<<3) + 6) & 0xffffff ];
						texel_pix |= vram_ptr[ (tex_addr_core + (index_byte<<3) + 7) & 0xffffff ] << 8; break;
			}
		}
		else {	// Non-VQ / Uncompressed.
			// Using texel_offs here atm.
			// It's possible Uncompressed textures might use a Twiddled address (scan_order==0).
			// Some code above will use twop from the core for that. Not sure if working yet. ElectronAsh.
			uint32_t texel_word = (texel_offs >> 2);
			uint32_t texel_byte = (texel_offs & 3) << 1;
			uint32_t byte_addr = (tex_addr_core + mipmap_byte_offs_core + (texel_word << 3) + texel_byte) & 0xffffff;
			texel_pix  = vram_ptr[ byte_addr ];
			texel_pix |= vram_ptr[ (byte_addr + 1) & 0xffffff ] << 8;

			//texel_pix = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__texel_pix;
		}

		uint8_t pix_fmt = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pix_fmt;
		if (pix_fmt==0 || pix_fmt==7) {	// ARGB 1555 (Swirl logo, etc.)...
			alpha = (texel_pix&0x8000) ? 0xff : 0x00;
			rgb[0] = ((texel_pix>>7) & 0xf8) | ((texel_pix>>12) & 0x07);	// Red.
			rgb[1] = ((texel_pix>>2) & 0xf8) | ((texel_pix>>7)  & 0x07);	// Green.
			rgb[2] = ((texel_pix<<3) & 0xf8) | ((texel_pix>>2)  & 0x07);	// Blue.
		}
		else if (pix_fmt==1) {			// RGB 565...				// RGB 565...
			alpha = 0xff;
			rgb[0] = ((texel_pix>>8) & 0xf8) | (texel_pix>>13) & 0x7;	// Red.
			rgb[1] = ((texel_pix>>3) & 0xfc) | (texel_pix>>9)  & 0x3;	// Green.
			rgb[2] = ((texel_pix<<3) & 0xf8) | (texel_pix>>2)  & 0x7;	// Blue.
		}
		else if (pix_fmt==2) {			// ARGB 4444...
			alpha = (texel_pix>>8)&0xf0 | (texel_pix>>12)&0x0f;
			rgb[0] = ((texel_pix>>4) & 0xf0) | ((texel_pix>>8) & 0x0f);	// Red.
			rgb[1] = ((texel_pix>>0) & 0xf0) | ((texel_pix>>4) & 0x0f);	// Green.
			rgb[2] = ((texel_pix<<4) & 0xf0) | ((texel_pix>>0) & 0x0f);	// Blue.
		}
		else if (pix_fmt==5) {			// PAL4
			// Palette format (4BBP and 8BPP) always use a twiddled texel address.
			uint32_t my_addr = ((twop_core&0xfffffff0)>>1) | (twop_core&7);	// Ditch bit [3], so it repeats nibbles 0,1,2,3,4,5,6,7 in each 4MB half of VRAM.
			uint8_t vram_byte  = vram_ptr[ (((twop_core&8)<<19) + tex_addr_core + mipmap_byte_offs_core + (my_addr>>1)) & 0xffffff ];

			uint8_t pal_nibble = !(my_addr&1) ? (vram_byte>>0) & 0xf :
												(vram_byte>>4) & 0xf;

											// TCW bits [26:21] for pal_selector bits [5:0]. Followed by the PAL4 index nibble [3:0].
			uint16_t pal_lut = (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__pal_selector<<4) | pal_nibble;
			texel_pix = pvr_ptr[ (0x1000>>2) + pal_lut ] & 0xffff;	// Read from Palette RAM (part of the PVR regs).

			switch(pvr_ptr[(0x108>>2)]&03) {	// Read bits [1:0] from PAL_RAM_CTRL reg, to grab the palette pixel format.
				case 0:	// ARGB 1555.
					alpha = (texel_pix&0x8000) ? 0xff : 0x00;
					rgb[0] = ((texel_pix>>7) & 0xf8) | ((texel_pix>>12) & 0x07);	// Red.
					rgb[1] = ((texel_pix>>2) & 0xf8) | ((texel_pix>>7)  & 0x07);	// Green.
					rgb[2] = ((texel_pix<<3) & 0xf8) | ((texel_pix>>2)  & 0x07);	// Blue.
				break;

				case 1:	// RGB 565.
					alpha = 0xff;
					rgb[0] = ((texel_pix>>8) & 0xf8) | (texel_pix>>13) & 0x7;	// Red.
					rgb[1] = ((texel_pix>>3) & 0xfc) | (texel_pix>>9)  & 0x3;	// Green.
					rgb[2] = ((texel_pix<<3) & 0xf8) | (texel_pix>>2)  & 0x7;	// Blue.
				break;

				case 2:	// ARGB 4444.
					alpha = (texel_pix>>8)&0xf0 | (texel_pix>>12)&0x0f;
					rgb[0] = ((texel_pix>>4) & 0xf0) | ((texel_pix>>8) & 0x0f);	// Red.
					rgb[1] = ((texel_pix>>0) & 0xf0) | ((texel_pix>>4) & 0x0f);	// Green.
					rgb[2] = ((texel_pix<<4) & 0xf0) | ((texel_pix>>0) & 0x0f);	// Blue.
				break;

				case 3:	// 3 = ARGB8888
					alpha  = (texel_pix>>24) & 0xff;
					rgb[0] = (texel_pix>>16) & 0xff;	// Red.
					rgb[1] = (texel_pix>>8)  & 0xff;	// Green.
					rgb[2] = (texel_pix>>0)  & 0xff;	// Blue.
				break;
			}
		}
		else if (pix_fmt==6) {	// PAL8
			uint32_t my_addr = ((twop_core&0xfffffff8)>>1) | (twop_core&3);	// Ditch bit [2], so it repeats 0,1,2,3 in each half of VRAM.
			uint8_t vram_byte  = vram_ptr[ (((twop_core&4)<<20) + tex_addr_core + mipmap_byte_offs_core + my_addr) & 0xffffff ];

													// TCW bits [26:25] for pal_selector bits [5:4]. Followed by the PAL8 index byte [7:0].
			uint16_t pal_lut = ((top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__pal_selector&0x30)<<4) | vram_byte;
			texel_pix = pvr_ptr[ (0x1000>>2) + pal_lut ] & 0xffff;	// Read from Palette RAM (part of the PVR regs).

			switch (pvr_ptr[(0x108>>2)]&03) {	// Read bits [1:0] from PAL_RAM_CTRL reg, to grab the palette pixel format.
				case 0:	// ARGB 1555.
					alpha = (texel_pix&0x8000) ? 0xff : 0x00;
					rgb[0] = ((texel_pix>>7) & 0xf8) | ((texel_pix>>12) & 0x07);	// Red.
					rgb[1] = ((texel_pix>>2) & 0xf8) | ((texel_pix>>7)  & 0x07);	// Green.
					rgb[2] = ((texel_pix<<3) & 0xf8) | ((texel_pix>>2)  & 0x07);	// Blue.
				break;

				case 1:	// RGB 565.
					alpha = 0xff;
					rgb[0] = ((texel_pix>>8) & 0xf8) | (texel_pix>>13) & 0x7;	// Red.
					rgb[1] = ((texel_pix>>3) & 0xfc) | (texel_pix>>9)  & 0x3;	// Green.
					rgb[2] = ((texel_pix<<3) & 0xf8) | (texel_pix>>2)  & 0x7;	// Blue.
				break;

				case 2:	// ARGB 4444.
					alpha = (texel_pix>>8)&0xf0 | (texel_pix>>12)&0x0f;
					rgb[0] = ((texel_pix>>4) & 0xf0) | ((texel_pix>>8) & 0x0f);	// Red.
					rgb[1] = ((texel_pix>>0) & 0xf0) | ((texel_pix>>4) & 0x0f);	// Green.
					rgb[2] = ((texel_pix<<4) & 0xf0) | ((texel_pix>>0) & 0x0f);	// Blue.
				break;

				case 3:	// 3 = ARGB8888
					alpha  = (texel_pix>>24) & 0xff;
					rgb[0] = (texel_pix>>16) & 0xff;	// Red.
					rgb[1] = (texel_pix>>8)  & 0xff;	// Green.
					rgb[2] = (texel_pix>>0)  & 0xff;	// Blue.
				break;
			}
		}
		// TODO...
		// 3 = YUV422.
		// 4 = Bump Map.
		// 5 = 4 BPP Palette. (mostly done)
		// 6 = 8 BPP Palette. (mostly done)
		else {	// Default, to show *anything*. (until more pixel formats are handled).
			// ARGB 4444...
			alpha = (texel_pix>>8)&0xf0 | (texel_pix>>12)&0x0f;
			rgb[0] = ((texel_pix>>4) & 0xf0) | ((texel_pix>>8) & 0x0f);	// Red.
			rgb[1] = ((texel_pix>>0) & 0xf0) | ((texel_pix>>4) & 0x0f);	// Green.
			rgb[2] = ((texel_pix<<4) & 0xf0) | ((texel_pix>>0) & 0x0f);	// Blue.
		}
	}
	else {	// Non-textured, so use Flat-shaded for now. Gouraud stuff later.
		uint32_t vertex_c_col = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_base_col_0;
		alpha  = (vertex_c_col&0xff000000)>>24;
		rgb[0] = (vertex_c_col&0x00ff0000)>>16;
		rgb[1] = (vertex_c_col&0x0000ff00)>>8;
		rgb[2] = (vertex_c_col&0x000000ff);
	}
	*/

	//if (top->vram_wr) {
	if ((display_source == 0) && top->fb_we) {
		uint32_t fb_word_addr = top->fb_addr;
		uint64_t fb_data = top->fb_writedata;
		uint8_t fb_be = top->fb_byteena;

		uint32_t pix_base = fb_word_addr << 1;
		uint32_t lo = (uint32_t)(fb_data & 0xffffffffull);
		uint32_t hi = (uint32_t)(fb_data >> 32);

		if ((fb_be & 0x03) == 0x03) write_disp_565(pix_base + 0, (uint16_t)(lo >> 16));
		if ((fb_be & 0x0c) == 0x0c) write_disp_565(pix_base + 1, (uint16_t)(lo >> 0));
		if ((fb_be & 0x30) == 0x30) write_disp_565(pix_base + 2, (uint16_t)(hi >> 16));
		if ((fb_be & 0xc0) == 0xc0) write_disp_565(pix_base + 3, (uint16_t)(hi >> 0));
	}
}

int8_t vert_a_x_shift;

static void CustomImGuiCallback(const ImDrawList* parent_list, const ImDrawCmd* cmd)
{
	ID3D11DeviceContext* deviceContext = g_pd3dDeviceContext;	// Obtain your device context
	ID3D11SamplerState*  customSampler = g_pTileSampler;		// Obtain or create your custom sampler state

	// Bind the custom sampler state
	deviceContext->PSSetSamplers(0, 1, &customSampler);
}

int verilate() {
	if (!Verilated::gotFinish()) {
		if (main_time < 4) {
			top->rst = 1;   	// Assert reset (active HIGH)
		}
		if (main_time == 10) {	// Do == here, so we can still reset it in the main loop.
			top->rst = 0;		// Deassert reset./
		}

		top->rootp->simtop__DOT__pvr__DOT__ra_trig = 0;
		if (!ra_running) top->rootp->simtop__DOT__pvr__DOT__ra_trig = 1;
		if (top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_state>0) ra_running = 1;

		pix_count++;

		//top->rootp->boot_vector = 0xA0000000;
		top->rootp->boot_vector = 0x00000000;
		sync_simtop_pvr_mirrors();

		// Instruction memory...
		uint32_t im_addr = 0x00000000;
		if ( top->im_req_valid ) im_addr = top->im_req_addr;

		uint32_t dm_addr = 0x00000000;
		if ( top->dm_req_valid ) dm_addr = top->dm_req_addr;
		
		// Data memory...
		uint64_t old_dm_data = ram_ptr[ (top->dm_req_addr&0xffffff)>>3 ];

		// Handle SDRAM Write masking...
		if (top->dm_req_valid && top->dm_req_wen /*&& top->rootp->dm_req_addr>=0x0C000000 && top->rootp->dm_req_addr<=0x0FFFFFFF*/) {
			if (top->dm_req_wmask&0x80) old_dm_data = (old_dm_data&0x00ffffffffffffff) | (top->dm_req_wdata&0xff00000000000000);
			if (top->dm_req_wmask&0x40) old_dm_data = (old_dm_data&0xff00ffffffffffff) | (top->dm_req_wdata&0x00ff000000000000);
			if (top->dm_req_wmask&0x20) old_dm_data = (old_dm_data&0xffff00ffffffffff) | (top->dm_req_wdata&0x0000ff0000000000);
			if (top->dm_req_wmask&0x10) old_dm_data = (old_dm_data&0xffffff00ffffffff) | (top->dm_req_wdata&0x000000ff00000000);
			if (top->dm_req_wmask&0x08) old_dm_data = (old_dm_data&0xffffffff00ffffff) | (top->dm_req_wdata&0x00000000ff000000);
			if (top->dm_req_wmask&0x04) old_dm_data = (old_dm_data&0xffffffffff00ffff) | (top->dm_req_wdata&0x0000000000ff0000);
			if (top->dm_req_wmask&0x02) old_dm_data = (old_dm_data&0xffffffffffff00ff) | (top->dm_req_wdata&0x000000000000ff00);
			if (top->dm_req_wmask&0x01) old_dm_data = (old_dm_data&0xffffffffffffff00) | (top->dm_req_wdata&0x00000000000000ff);
			ram_ptr[ (top->dm_req_addr & 0xffffff)>>3 ] = old_dm_data;
		}

		bios_word = rom_ptr[(im_addr&0x1fffff)>>2];
		//if ( (im_addr&0x1fffff)>=0x00000000 && (im_addr&0x1fffff)<=0x03FFFFFF) top->im_resp_rdata = bios_word;
		top->im_resp_rdata = (top->rootp->simtop__DOT__bios_cs) ? bios_word : ram_ptr[ (im_addr&0xffffff)>>3 ];	// SDRAM Instruction.
		top->dm_resp_rdata = (top->rootp->simtop__DOT__bios_cs) ? bios_word : ram_ptr[ (dm_addr&0xffffff)>>3 ];	// SDRAM Data.
		
		top->im_resp_valid = 1;
		top->dm_resp_valid = 1;

		static DdramEmu ddram_isp;
		static DdramEmu ddram_ra;
		static DdramEmu ddram_tex;

		bool ddram_busy = false;
		bool ddram_ready = false;
		uint64_t ddram_dout = 0;

		// RA / ISP.
		ddram_tick(ddram_isp, vram_ptr,
			top->DDRAM_RD,
			top->DDRAM_ADDR,
			top->DDRAM_BURSTCNT,
			ddram_busy,
			ddram_ready,
			ddram_dout);
		top->DDRAM_BUSY = ddram_busy;
		top->DDRAM_DOUT_READY = ddram_ready;
		top->DDRAM_DOUT = ddram_dout;

		// TSP (Texture reads).
		ddram_tick(ddram_tex, vram_ptr,
			top->DDRAM2_RD,
			top->DDRAM2_ADDR,
			top->DDRAM2_BURSTCNT,
			ddram_busy,
			ddram_ready,
			ddram_dout);
		top->DDRAM2_BUSY = ddram_busy;
		top->DDRAM2_DOUT_READY = ddram_ready;
		top->DDRAM2_DOUT = ddram_dout;

		rgb[0] = 0xff;	// Red.
		rgb[1] = 0xff;	// Green.
		rgb[2] = 0xff;	// Blue.

		if (tile_highlight && top->rootp->simtop__DOT__pvr__DOT__ra_entry_valid) {
			uint32_t x_start = top->rootp->simtop__DOT__pvr__DOT__ra_cont_tilex * 32;
			uint32_t y_start = top->rootp->simtop__DOT__pvr__DOT__ra_cont_tiley * 32;
			// Draw a 32x32 square outline, to denote the current RA tile.
			for (uint16_t y = y_start; y < (y_start+32); y++) {
				for (uint16_t x = x_start; x < (x_start+32); x++) {
					if (x==x_start || x==x_start+31 || y==y_start || y==y_start+31) {
						rgb[0] = 0xff; rgb[1] = 0x00; rgb[2] = 0x00;
						disp_addr = (y * 640) + x;
						disp_ptr[disp_addr] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];
					}
				}
			}
		}
			
		float x1,x2,x3,x4 = 0;
		float y1,y2,y3,y4 = 0;
		float z1,z2,z3,z4 = 0;
		float u1,u2,u3,u4 = 0;
		float v1,v2,v3,v4 = 0;

		//test_float_to_fixed();

		/*
		printf("Flat Z triangle\n");
		test_interp_once(
			top,
			0.0,  0.0, 16.0,   // A
			16.0, 0.0, 16.0,   // B
			0.0, 16.0, 16.0,   // C
			8, 8
		);

		printf("Linear Z slope in X\n");
		test_interp_once(
			top,
			0.0,  0.0,  0.0,   // A
			16.0, 0.0, 16.0,   // B (higher Z at +X)
			0.0, 16.0,  0.0,   // C
			8, 8
		);

		printf("Linear Z slope in Y\n");
		test_interp_once(
			top,
			0.0,  0.0,  0.0,   // A
			16.0, 0.0,  0.0,   // B
			0.0, 16.0, 16.0,   // C (higher Z at +Y)
			8, 8
		);

		printf("Tilted Z plane\n");
		test_interp_once(
			top,
			0.0,  0.0,  0.0,   // A
			16.0, 0.0, 16.0,   // B
			0.0, 16.0, 16.0,   // C
			8, 8
		);

		printf("Precision stress triangle\n");
		test_interp_once(
			top,
			0.0,   0.0,  0.0,   // A
			1.0,  16.0, 64.0,   // B (steep Z)
			16.0,  1.0, 32.0,   // C
			4, 8
		);
		*/

		top->clk = 0;
		top->eval();            // Evaluate model!

		const bool pcache_write_0 =
			top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_write_0;
		const bool pcache_write_1 =
			top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_write_1;
		if (pcache_write_0 || pcache_write_1) {
			const uint8_t bank = pcache_write_1 ? 1 : 0;
			const uint16_t tag =
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_tag;
			ParamWriteSnapshot &snapshot = param_write_snapshots[bank][tag & 1023];
			snapshot.valid = true;
			snapshot.cycle = main_time;
			snapshot.tag = tag;
			snapshot.bank = bank;
			snapshot.tile_x = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tilex;
			snapshot.tile_y = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tiley;
			snapshot.a = {
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_y,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_z,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u0,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v0
			};
			snapshot.b = {
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_x,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_y,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_z,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u0,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v0
			};
			snapshot.c = {
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_x,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_y,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_z,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u0,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v0
			};
			snapshot.fddx_u = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDX_U;
			snapshot.fddy_u = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDY_U;
			snapshot.fddx_v = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDX_V;
			snapshot.fddy_v = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDY_V;
			snapshot.tile_start_u = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_start_u;
			snapshot.tile_start_v = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_start_v;
		}

		// Capture the parameter RAM outputs in the same combinational phase in
		// which the ISP accepts this pixel into the TSP pipeline.
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_issue_cmd) {
			last_tsp_issue.valid = true;
			last_tsp_issue.cycle = main_time;
			last_tsp_issue.tag = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_tag_out;
			last_tsp_issue.bank = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_z_bank;
			last_tsp_issue.tile_x = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tilex;
			last_tsp_issue.tile_y = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tiley;
			last_tsp_issue.x = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_x_ps;
			last_tsp_issue.y = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_y_ps;
			last_tsp_issue.isp_inst = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_inst_out;
			last_tsp_issue.tsp_inst = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_inst_out;
			last_tsp_issue.tcw_word = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tcw_word_out;
			last_tsp_issue.fddx_u = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDX_U;
			last_tsp_issue.fddy_u = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDY_U;
			last_tsp_issue.fddx_v = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDX_V;
			last_tsp_issue.fddy_v = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDY_V;
			last_tsp_issue.tile_start_u = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tile_start_u;
			last_tsp_issue.tile_start_v = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tile_start_v;
			last_tsp_issue.param_write =
				param_write_snapshots[last_tsp_issue.bank][last_tsp_issue.tag & 1023];
		}

		top->clk = 1;
		top->eval();            // Evaluate model!

		if (top->DDRAM_WE) {
			write_ddr64(vram_ptr, top->DDRAM_ADDR, top->DDRAM_DIN, top->DDRAM_BE);
		}

		//auto zbuf0 = top->__PVT__simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst_0;
		//auto zbuf1 = top->__PVT__simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst_1;
		//if (zbuf0 && (zbuf0->z_write_allow != 0)) snapshot_z_bank_row(0, zbuf0, zbuf0->row_sel_wr);
		//if (zbuf1 && (zbuf1->z_write_allow != 0)) snapshot_z_bank_row(1, zbuf1, zbuf1->row_sel_wr);

		if (main_time == 0) {
			bottleneck_cycles = 0;
			no_bottleneck_cycles = 0;
			isp_active_cycles = 0;
			tsp_active_cycles = 0;
			overlap_cycles = 0;
			isp_only_cycles = 0;
			tsp_only_cycles = 0;
			isp_wait_tsp_cycles = 0;
			tsp_wait_tex_cycles = 0;
			tsp_wait_cb_cycles = 0;
			bank_clear_wait_cycles = 0;
		}

		const uint32_t isp_state_dbg = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state;
		const uint32_t tsp_state_dbg = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_state;
		const bool isp_active = (isp_state_dbg != 0);
		const bool tsp_active = (tsp_state_dbg != 0);
		const bool isp_wait_tsp = (isp_state_dbg == 57);
		const bool tsp_wait_tex = (tsp_state_dbg == 52) || top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_waiting;
		const bool tsp_wait_cb = (tsp_state_dbg == 100 || tsp_state_dbg == 101);
		const bool bank_clear_wait = (isp_state_dbg == 56);
		const bool bottleneck = isp_wait_tsp || tsp_wait_tex || tsp_wait_cb || bank_clear_wait;

		if (isp_active) isp_active_cycles++;
		if (tsp_active) tsp_active_cycles++;
		if (isp_active && tsp_active) overlap_cycles++;
		if (isp_active && !tsp_active) isp_only_cycles++;
		if (!isp_active && tsp_active) tsp_only_cycles++;
		if (isp_wait_tsp) isp_wait_tsp_cycles++;
		if (tsp_wait_tex) tsp_wait_tex_cycles++;
		if (tsp_wait_cb) tsp_wait_cb_cycles++;
		if (bank_clear_wait) bank_clear_wait_cycles++;
		if (isp_active || tsp_active) {
			if (bottleneck) bottleneck_cycles++;
			else no_bottleneck_cycles++;
		}

		main_time++;            // Time passes...

		vert_a_x_shift = ((top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x >> 23) & 0xff) - 127;

		//X1: 43C994E8 403.163330  X2: 43C994E8 403.163330  X3: 43BC780C 376.937866  X4: 00000000 0.000000
		//Y1: 43074970 135.286865  Y2: 4391829E 291.020447  Y3: 43074970 135.286865  Y4: 00000000 0.000000

		x1 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x) / (1 << FRAC_BITS);
		x2 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_x) / (1 << FRAC_BITS);
		x3 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_x) / (1 << FRAC_BITS);
		x4 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_x)     / (1 << FRAC_BITS);
		
		y1 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_y) / (1 << FRAC_BITS);
		y2 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_y) / (1 << FRAC_BITS);
		y3 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_y) / (1 << FRAC_BITS);
		y4 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_y)     / (1 << FRAC_BITS);
		
		z1 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_z) / (1 << Z_FRAC_BITS);
		z2 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_z) / (1 << Z_FRAC_BITS);
		z3 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_z) / (1 << Z_FRAC_BITS);
		z4 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_z)     / (1 << Z_FRAC_BITS);
		
		u1 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u0) / (1 << Z_FRAC_BITS);
		u2 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u0) / (1 << Z_FRAC_BITS);
		u3 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u0) / (1 << Z_FRAC_BITS);
		u4 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_u0)     / (1 << Z_FRAC_BITS);
		
		v1 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v0) / (1 << Z_FRAC_BITS);
		v2 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v0) / (1 << Z_FRAC_BITS);
		v3 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v0) / (1 << Z_FRAC_BITS);
		v4 = (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_v0)     / (1 << Z_FRAC_BITS);

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state == 49) {
			if (fabs(x1) < fabs(x1_min)) x1_min = x1; if (fabs(x1) > fabs(x1_max)) x1_max = x1;
			if (fabs(y1) < fabs(y1_min)) y1_min = y1; if (fabs(y1) > fabs(y1_max)) y1_max = y1;
			if (fabs(z1) < fabs(z1_min)) z1_min = z1; if (fabs(z1) > fabs(z1_max)) z1_max = z1;

			if (fabs(x2) < fabs(x2_min)) x2_min = x2; if (fabs(x2) > fabs(x2_max)) x2_max = x2;
			if (fabs(y2) < fabs(y2_min)) y2_min = y2; if (fabs(y2) > fabs(y2_max)) y2_max = y2;
			if (fabs(z2) < fabs(z2_min)) z2_min = z2; if (fabs(z2) > fabs(z2_max)) z2_max = z2;

			if (fabs(x3) < fabs(x3_min)) x3_min = x3; if (fabs(x3) > fabs(x3_max)) x3_max = x3;
			if (fabs(y3) < fabs(y3_min)) y3_min = y3; if (fabs(y3) > fabs(y3_max)) y3_max = y3;
			if (fabs(z3) < fabs(z3_min)) z3_min = z3; if (fabs(z3) > fabs(z3_max)) z3_max = z3;

			if (fabs(x4) < fabs(x4_min)) x4_min = x4; if (fabs(x4) > fabs(x4_max)) x4_max = x4;
			if (fabs(y4) < fabs(y4_min)) y4_min = y4; if (fabs(y4) > fabs(y4_max)) y4_max = y4;

			// Bit-width tracking for interp internals. All signals are QData (uint64_t).
			auto& r = *top->rootp;
			rng_FZ.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ1_FIXED));
			rng_FZ.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ2_FIXED));
			rng_FZ.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ3_FIXED));
			rng_BIG_C.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__BIG_C));
			//rng_FDDX.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDX_Z));
			//rng_FDDY.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDY_Z));
			//rng_small_c.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__small_c_z));
			rng_interp_col.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__IP_Z_R[0]));
			rng_interp_col.update(sign_extend_48(r.simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__IP_Z_R[31]));
		}

		/*
		if (top->rootp->simtop__DOT__pvr__DOT__vram_rd) {
			if (top->rootp->simtop__DOT__pvr__DOT__isp_switch==0)
				printf(" ra_vram_addr: 0x%08X  top vram_addr: 0x%08X\n", top->rootp->simtop__DOT__pvr__DOT__ra_vram_addr, top->vram_addr);
			else
				printf("isp_vram_addr: 0x%08X  top vram_addr: 0x%08X\n", top->rootp->simtop__DOT__pvr__DOT__isp_vram_addr, top->vram_addr);
		}

		if (top->rootp->simtop__DOT__pvr__DOT__vram_valid) {
			if (top->rootp->simtop__DOT__pvr__DOT__isp_switch==0)
				printf("  ra_vram_din: 0x%08X\n", top->rootp->simtop__DOT__pvr__DOT__ra_vram_din);
			else 
				printf(" isp_vram_din: 0x%08X\n", top->rootp->simtop__DOT__pvr__DOT__isp_vram_din);
		}
		*/

		/*
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state == 51) {
			printf(" W1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__W1) / (1 << Z_FRAC_BITS));
			//printf("  Uw1_full: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__Uw1_full) / (1 << Z_FRAC_BITS));
			//printf("  Uw1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__Uw1) / (1 << Z_FRAC_BITS));
			printf("  FDDX_U: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDX_U) / (1 << Z_FRAC_BITS));
			printf("  FDDY_U: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__FDDY_U) / (1 << Z_FRAC_BITS));
			printf("  IP_U_INTERP: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__IP_U_INTERP) / (1 << Z_FRAC_BITS));
			//printf("  IP_U_PERSP: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__IP_U_PERSP) / (1 << Z_FRAC_BITS));
			//printf("  u_div_z: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__u_div_z) / (1 << Z_FRAC_BITS));

			int32_t u_fixed = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__u_div_z;
			printf(" u_div_z fixed=%d  U_float=%f", u_fixed, (float)u_fixed / (1 << Z_FRAC_BITS));
			printf("  u_flipped: %f\n", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__u_flipped) / (1 << Z_FRAC_BITS));
		}
		*/

		/*
		if (top->rootp->simtop__DOT__vram_read_cache_inst__DOT__filling & top->rootp->simtop__DOT__vram_read_cache_inst__DOT__DDRAM_DOUT_READY) {
			printf("rd_ptr: %02d  DDRAM_ADDR: %08X (%08X)  top vram_din: 0x%08X%08X\n", top->rootp->simtop__DOT__vram_read_cache_inst__DOT__rd_ptr, top->rootp->simtop__DOT__DDRAM_ADDR, top->rootp->simtop__DOT__DDRAM_ADDR<<3, top->rootp->simtop__DOT__vram_din>>32, top->rootp->simtop__DOT__vram_din & 0xffffffff);
		}
		*/

		//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__is_quad_array) run_enable = 0;

		//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__poly_addr==0xa9610 && top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__strip_cnt==1) run_enable = 0;

		rasterize_triangle_fixed(x1, x2, x3, x4, y1, y2, y3, y4, z1, z2, z3, z4, u1, u2, u3, u4, v1, v2, v3, v4);

		if (stop_on_last && top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_cont_last &&
							top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_state==0 ||
							top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_state==15) {
			run_enable = 0;
			stop_on_last = 0;
		}

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_start) {
			printf("RLE Start\n");
			printf("tilex: %02d  tiley : %02d  Prim Type : %d ",
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_tilex,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_tiley, 
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__type_cnt -1);

			switch (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__type_cnt - 1) {
				case 0: printf("(Opaque)\n"); break;
				case 1: printf("(Punch Through)\n"); break;
				case 2: printf("(Opaque Modifier)\n"); break;
				case 3: printf("(Translucent)\n"); break;
				case 4: printf("(Translucent Modifier)\n"); break;
			}
		}
		
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_valid) {
			printf("row: %02d  col: %02d  tag: 0x%03X  cnt: %04d\n",
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_row_start,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_col_start,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_tag,
				top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_count);
		}

		/*
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_done) {
			printf("PRIM Done !\n\n");
		}
		*/

		/*
		for (uint16_t i = 0; i < 1024; i++) {
			uint64_t word = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_argb_buffer_inst__DOT__tile_argb_mem_inst__DOT__buff[i>>1];
			uint32_t argb = (!(i&1)) ? word>>32 : word&0xffffffff;
			uint8_t red = (argb>>16) & 0xff;
			uint8_t grn = (argb>>8 ) & 0xff;
			uint8_t blu = (argb    ) & 0xff;
			tile_ptr[i] = (0xff<<24) | (blu<<16) | (grn<<8) | (red<<0);	// ABGR ?
		}
		*/

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__render_to_tile) {
			bool is_pal4 = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__is_pal4_r;
			bool is_pal8 = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__is_pal8_r;
			bool is_twid = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__is_twid;
			bool vq_comp = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vq_comp_r;
			bool scan_order = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__scan_order;
			uint32_t tex_base = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_word_addr<<3;	// shift to convert to 64-bit BYTE address.
			uint32_t mipmap_byte_offs = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__mipmap_byte_offs;
			tex_base += mipmap_byte_offs;

			uint16_t tex_u_size = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_u_size_full;
			uint16_t tex_v_size = top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__tex_v_size_full;
			if (vq_comp) {
				//tex_base += 2048;
				tex_base += 2048 * 2;
				tex_u_size = tex_u_size >>1;
				tex_v_size = tex_v_size >>1;
			}
			for (int y=0; y < tex_v_size; y++) {
				for (int x=0; x < tex_u_size; x++) {
					uint32_t offset;
					if (is_pal4 || is_pal8 || scan_order==0) {
						offset = twiddle_slow(x, y, tex_u_size, tex_v_size) * 2;
					}
					else {
						// Linear 16-bit textures in VRAM are lane-swizzled in pixel pairs.
						uint32_t sample_x = (!vq_comp && (tex_u_size > 1)) ? static_cast<uint32_t>(x ^ 1) : static_cast<uint32_t>(x);
						offset = ((y * tex_u_size) + sample_x) * 2;
					}
					uint32_t byte_addr = (tex_base + offset) & 0xffffff;
					uint8_t byte0 = vram_ptr[byte_addr];
					uint8_t byte1 = vram_ptr[(byte_addr + 1) & 0xffffff];
					uint16_t pix_16 = (byte0<<8) | byte1;
					uint8_t rgb[3];
					if (top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__pix_fmt==0) {		// ARGB 1555...
						rgb[0] = (pix_16>>7); rgb[1] = (pix_16>>2); rgb[2] = (pix_16<<3);
					}
					else if (top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__pix_fmt==2) {	// ARGB 4444...
						rgb[0] = (pix_16>>4); rgb[1] = (pix_16>>0); rgb[2] = (pix_16<<4);
					}
					else {	// 565...
						rgb[0] = (pix_16>>8); rgb[1] = (pix_16>>3); rgb[2] = (pix_16<<3);
					}
					tile_ptr[ ((y&0x3ff)*1024) + x] = (0xff<<24) | (rgb[2]<<16) | (rgb[1]<<8) | (rgb[0]<<0);
				}
			}
		}
		
		/*
		//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__render_to_tile) {
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state==90) {
			auto tag_to_argb = [](uint32_t tag) -> uint32_t {
				uint32_t idx = tag & 0xFF;
				uint8_t r = static_cast<uint8_t>(((idx >> 5) & 0x7) * 36);
				uint8_t g = static_cast<uint8_t>(((idx >> 2) & 0x7) * 36);
				uint8_t b = static_cast<uint8_t>((idx & 0x3) * 85);
				return 0xFF000000u | (static_cast<uint32_t>(r) << 16) | (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
			};
			for (int y=0; y<32; y++) {
				tile_ptr[(y*32) + 0]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_0__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 1]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_1__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 2]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_2__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 3]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_3__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 4]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_4__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 5]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_5__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 6]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_6__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 7]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_7__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 8]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_8__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 9]  = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_9__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 10] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_10__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 11] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_11__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 12] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_12__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 13] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_13__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 14] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_14__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 15] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_15__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 16] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_16__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 17] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_17__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 18] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_18__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 19] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_19__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 20] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_20__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 21] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_21__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 22] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_22__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 23] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_23__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 24] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_24__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 25] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_25__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 26] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_26__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 27] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_27__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 28] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_28__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 29] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_29__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 30] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_30__DOT__tag_mem[y]);
				tile_ptr[(y*32) + 31] = tag_to_argb(top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_31__DOT__tag_mem[y]);
			}
		}
		*/

		if (render_120 && top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_state==15 && dump_cnt<600) {
			run_enable = 0;
			/*
			uint32_t sof_offset = pvr_ptr[0x050 >> 2];
			for (uint32_t i = 0; i < (640 * 480 * 2); i += 2) {
				// Display the pre-rendered Framebuffer from the reicast VRAM dump.
				uint8_t byte0 = vram_ptr[sof_offset + i + 0];
				uint8_t byte1 = vram_ptr[sof_offset + i + 1];
				uint8_t red = (byte0 & 0xf8);
				uint8_t green = (byte0 & 7) << 5 | (byte1 & 0xC0) >> 3;
				uint8_t blue = (byte1 & 0x1F) << 3;
				disp_ptr[(i >> 1) ^ 1] = 0xff <<24 | blue <<16 | green <<8 | red;
			}
			*/
			BMP* bmp = new BMP;
			bmp->SetBitDepth(24);
			bmp->SetSize(640, 480);
			char my_string[20];
			sprintf(my_string, "frame%d.bmp", dump_cnt);
			for (int y = 0; y < 480; y++) {
				for (int x = 0; x < 640; x++) {
					uint32_t addr = x + (y * 640);
					RGBApixel pixel;
					pixel.Alpha = 0xff;
					pixel.Red = disp_ptr[addr] >> 0;
					pixel.Green = disp_ptr[addr] >> 8;
					pixel.Blue = disp_ptr[addr] >> 16;
					bmp->SetPixel(x, y, pixel);
				}
			}
			bmp->WriteToFile(my_string);

			// Clear the Z-buffer.
			for (uint32_t i = 0; i < z_size; i++) z_ptr[i] = 0;

			// Clear the DISPLAY buffer...
			uint32_t value = 0xff000000;
			for (uint32_t i = 0; i < disp_size / 4; i += 2) memcpy(((char*)disp_ptr) + i, &value, 4);

			dump_cnt++;
			char name[20];
			itoa(dump_cnt, name, 10); load_vram_dump(name);

			main_time = 0;
			top->rst = 1;   	// Assert reset (active HIGH)
			top->clk = 0;
			top->eval();            // Evaluate model!
			top->clk = 1;
			top->eval();            // Evaluate model!
			ra_running = 0;

			run_enable = 1;
		}

		/*
		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__render_poly) {
			printf("New prim...\n");
		}

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state == 50 && top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_fifo_wr) {
			uint8_t tsp_row    = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_row;
			uint8_t tsp_startx = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_startx;
			uint8_t tsp_endx   = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_endx;
			printf("row: %02d  startx: %02d  endx: %02d\n", tsp_row, tsp_startx, tsp_endx);
		}
		*/

		/*
		top->clk = 0;
		top->eval();            // Evaluate model!
		top->clk = 1;
		top->eval();            // Evaluate model!
		main_time++;            // Time passes...
		*/

		/*
		//uint16_t tex_u_size = 8<<top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_size;
		//uint16_t tex_v_size = 8<<top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_size;
		uint16_t tex_u_size = 128;
		uint16_t tex_v_size = 128;
		uint16_t texel_pix = 0xf000;

		uint32_t mipmap_offs = 0;
		bool mipmap_flag = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__mip_map;

		if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vq_comp)
			mipmap_offs = (mipmap_flag) ? mipmap_byte_offset_vq[ top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_size=3 ]>>1 : 0;

		bool pp_FlipU  = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_flip;
		bool pp_FlipV  = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_flip;
		bool pp_ClampU = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_clamp;
		bool pp_ClampV = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_clamp;

		for (int vi=0; vi<tex_v_size; vi++) {
			for (int ui=0; ui<tex_u_size; ui++) {
				//ui = ClampFlip(pp_ClampU, pp_FlipU, ui, tex_u_size);
				//vi = ClampFlip(pp_ClampV, pp_FlipV, vi, tex_v_size);

				uint32_t twop_addr = twiddle_slow(ui, vi, tex_u_size, tex_v_size);
				//uint32_t twop_addr = twop(ui, vi, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_size, 
					//top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_size);

				// Looks like twop address basically hops to each 64-bit wide word.
				// So it needs an extra shift, to address each 32-bit wide word in each half of VRAM??
				if (!(twop_addr&4)) vq_tex_index = tex_addr+mipmap_offs+1024 + (twop_addr>>3);
				else       vq_tex_index = tex_addr+mipmap_offs+0x400000+1024 + (twop_addr>>3);

				uint8_t index_byte = vram_ptr[(vq_tex_index)&0x7fffff];

				//uint8_t index_byte;
				//switch (twop_addr&7) {
					//case 0: index_byte = vram_ptr[(tex_addr+         mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 0) & 0x7fffff];
					//case 1: index_byte = vram_ptr[(tex_addr+         mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 1) & 0x7fffff];
					//case 2: index_byte = vram_ptr[(tex_addr+         mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 2) & 0x7fffff];
					//case 3: index_byte = vram_ptr[(tex_addr+         mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 3) & 0x7fffff];
					//case 4: index_byte = vram_ptr[(tex_addr+0x400000+mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 0) & 0x7fffff];
					//case 5: index_byte = vram_ptr[(tex_addr+0x400000+mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 1) & 0x7fffff];
					//case 6: index_byte = vram_ptr[(tex_addr+0x400000+mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 2) & 0x7fffff];
					//case 7: index_byte = vram_ptr[(tex_addr+0x400000+mipmap_offs+1024 + ((twop_addr&0xfffffffc)>>0) + 3) & 0x7fffff];
				//}

				// Group of FOUR 16-bit texels (8 CODE BOOK Bytes) per index_byte.
				// (but we only shift by <<2 here, because we read a 32-bit word from both the lower and upper 4MB VRAM.)
				//switch ( (twop_addr>>2)&3 ) {
				switch ((index_byte)&3) {
					case 0: texel_pix = read_vram_32(tex_addr + 0x000000 + (index_byte<<2)) >> 16; break;
					case 1: texel_pix = read_vram_32(tex_addr + 0x000000 + (index_byte<<2)) & 0xffff; break;
					case 2: texel_pix = read_vram_32(tex_addr + 0x400000 + (index_byte<<2)) >> 16; break;
					case 3: texel_pix = read_vram_32(tex_addr + 0x400000 + (index_byte<<2)) & 0xffff; break;
				}

				// ARGB 4444...
				//uint8_t alpha = (texel_pix>>8)&0xf0;
				rgb[0] = ((texel_pix>>4) & 0xf0) | ((texel_pix>>8) & 0x0f);	// Red.
				rgb[1] = ((texel_pix>>0) & 0xf0) | ((texel_pix>>4) & 0x0f);	// Green.
				rgb[2] = ((texel_pix<<4) & 0xf0) | ((texel_pix>>0) & 0x0f);	// Blue.

				// RGB 565...
				//uint8_t alpha = 0xff;
				//rgb[0] = ((texel_pix>>8) & 0xf8) | (texel_pix>>13) & 0x7;	// Red.
				//rgb[1] = ((texel_pix>>3) & 0xfc) | (texel_pix>>9)  & 0x3;	// Green.
				//rgb[2] = ((texel_pix<<3) & 0xf8) | (texel_pix>>2)  & 0x7;	// Blue.

				uint32_t disp_addr = (vi * 640) + ui;

				disp_ptr[ disp_addr&0x7fffff ] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];
			}
		}
		*/

		return 1;
	}


	// Stop Verilating...
	top->final();
	delete top;
	exit(0);
	return 0;
}

void display_sof(uint32_t sof_offset, bool linear_ddr_fb) {
	for (uint32_t pix = 0; pix < (640 * 480); pix += 2) {
		uint32_t byte_addr = sof_offset + (pix << 1);
		uint32_t word = linear_ddr_fb ? read_linear_ddr_fb_32(vram_ptr, byte_addr) :
										read_side_by_side_fb_32(vram_ptr, sof_offset, pix >> 1);

		uint16_t pix0 = word & 0xffff;
		write_disp_565(pix + 0, pix0);

		uint16_t pix1 = word >> 16;
		write_disp_565(pix + 1, pix1);
	}
}

void full_reset() {
	main_time = 0;
	top->rst = 1;   	// Assert reset (active HIGH)
	top->clk = 0;
	top->eval();            // Evaluate model!
	top->clk = 1;
	top->eval();            // Evaluate model!
	ra_running = 0;

	render_120 = 0;

	// Clear the Z-buffer.
	for (uint32_t i = 0; i < z_size; i++) {
		z_ptr[i] = 0;
	}

	for (uint32_t i = 0; i < (640*480*4); i += 2) {
		uint32_t value = 0xff000000;
		memcpy(((char*)disp_ptr) + i, &value, 4);	// Clear the DISPLAY buffer...
	}

	x1_min = 10000.0f, x1_max = 0.0f;
	y1_min = 10000.0f, y1_max = 0.0f;
	z1_min = 10000.0f, z1_max = 0.0f;

	x2_min = 10000.0f, x2_max = 0.0f;
	y2_min = 10000.0f, y2_max = 0.0f;
	z2_min = 10000.0f, z2_max = 0.0f;

	x3_min = 10000.0f, x3_max = 0.0f;
	y3_min = 10000.0f, y3_max = 0.0f;
	z3_min = 10000.0f, z3_max = 0.0f;

	x4_min = 10000.0f, x4_max = 0.0f;
	y4_min = 10000.0f, y4_max = 0.0f;

	rng_FZ.reset(); rng_Aa.reset(); rng_Ba.reset(); rng_BIG_C.reset();
	rng_FDDX.reset(); rng_FDDY.reset(); rng_small_c.reset(); rng_interp_col.reset();
}


int my_count = 0;

static MemoryEditor mem_edit_1;
static MemoryEditor mem_edit_2;
static MemoryEditor mem_edit_3;
static MemoryEditor mem_edit_4;
static MemoryEditor mem_edit_5;

uint64_t z1_highest = 0;

int main(int argc, char** argv, char** env) {

	// Create application window
	WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(NULL), NULL, NULL, NULL, NULL, _T("ImGui Example"), NULL };
	RegisterClassEx(&wc);
	HWND hwnd = CreateWindow(wc.lpszClassName, _T("Dear ImGui DirectX11 Example"), WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, NULL, NULL, wc.hInstance, NULL);

	// Initialize Direct3D
	if (CreateDeviceD3D(hwnd) < 0)
	{
		CleanupDeviceD3D();
		UnregisterClass(wc.lpszClassName, wc.hInstance);
		return 1;
	}

	// Show the window
	ShowWindow(hwnd, SW_SHOWMAXIMIZED);
	UpdateWindow(hwnd);

	// Setup Dear ImGui context
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO(); (void)io;
	//io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;  // Enable Keyboard Controls
	//io.ConfigFlags | ImGuiConfigWindowsMoveFromTitleBarOnly;

	// Setup Dear ImGui style
	ImGui::StyleColorsDark();
	//ImGui::StyleColorsClassic();

	// Setup Platform/Renderer bindings
	ImGui_ImplWin32_Init(hwnd);
	ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

	Verilated::commandArgs(argc, argv);

	top = new Vsimtop;
	top->fb_w_sof1_mirror = 0;

	//uint32_t value = 0xff222222;
	uint32_t value = 0xff000000;
	for (uint32_t i = 0; i < disp_size/2; i+=4) memcpy(((char*)disp_ptr) + i, &value, 4);
	for (uint32_t i = 0; i < z_size; i++) z_ptr[i] = 0;

	memset(ram_ptr, 0x00, ram_size);

	unsigned int file_size=0;

	/*
	FILE *biosfile;
	biosfile = fopen("mpr-21931.ic501","rb");	// Default DC BIOS in MAME v0249b, using the "dc" driver option.
	//biosfile = fopen("256b.bin","rb");
	//biosfile = fopen("roto.bin","rb");
	//biosfile = fopen("hello.bin","rb");
	if (biosfile!=NULL) printf("\nDC BIOS loaded OK.\n");
	else { printf("\nDC BIOS file not found!\n"); return 0; }
	fseek(biosfile, 0L, SEEK_END);
	file_size = ftell(biosfile);
	fseek(biosfile, 0L, SEEK_SET);
	fread(rom_ptr, 1, rom_size, biosfile);
	*/

	// Frame times below, were with a CB cache size of 512 entries (1MB!).
	// It's almost as fast as a cache size of 64 entries (128KB), or even less.
	// Still some texture corruption in places.
											
											// It's likely the FPS values below were taken when rendering ONLY Opaque objects! ElectronAsh.
											// 
	//load_vram_dump("logo");				// 460.96 FPS   146.07 FPS with CB cache??
	//load_vram_dump("doa2_kasumi");		//              45.74 FPS with CB cache
	//load_vram_dump("menu");				// 103.99 FPS   98.55 FPS with CB cache?
	//load_vram_dump("menu2");				// 104.56 FPS   98.49 FPS with CB cache?
	//load_vram_dump("mem");				// 105.83 FPS   103.05 FPS with CB cache?
	//load_vram_dump("taxi");				// 21.39 FPS    57.99 FPS with CB cache.
	//load_vram_dump("taxi2");				// 24.68 FPS    68.40 FPS with CB cache.
	//load_vram_dump("taxi3");				// 23.66 FPS    52.95 FPS with CB cache.
	//load_vram_dump("taxi4");				// 20.03 FPS    49.30 FPS with CB cache.
	//load_vram_dump("crazy_title");		// 527.72 FPS   153.62 FPS with CB cache?
	//load_vram_dump("sonic");				// 25.15 FPS    49.40 FPS with CB cache.
	//load_vram_dump("sonic_title");		// 69.96 FPS    65.91 FPS with CB cache.
	//load_vram_dump("hydro_title");		// 266.92 FPS   101.62 FPS with CB cache.
	//load_vram_dump("looney_foghorn");		// 32.01 FPS    41.94 FPS with CB cache.
	//load_vram_dump("looney_startline");	// 21.21 FPS    25.47 FPS with CB cache.
	//load_vram_dump("sw_ep1_menu");		// 56.05 FPS    71.60 FPS with CB cache.
	//load_vram_dump("hotd2_title");		// 40.62 FPS    86.18 FPS with CB cache.
	//load_vram_dump("hotd2_zombies");		// 37.25 FPS    56.97 FPS with CB cache.
	//load_vram_dump("hotd2_selfie");		// 49.18 FPS    86.91 FPS with CB cache.
	//load_vram_dump("hotd2_car_fire");		// 27.45 FPS    51.63 FPS with CB cache.
	//load_vram_dump("hotd2_boat");			// 45.87 FPS    62.08 FPS with CB cache.
	//load_vram_dump("hotd2_gargoyle");		// 28.82 FPS    52.06 FPS with CB cache.
	//load_vram_dump("rayman_title");		// 79.36 FPS    107.67 FPS with CB cache.
	//load_vram_dump("rayman_lights");		// 95.18 FPS    113.71 FPS with CB cache.
	//load_vram_dump("rayman_level");		// 112.35 FPS   112.17 FPS with CB cache.
	//load_vram_dump("xtreme_intro");		// 17.25 FPS    36.04 FPS with CB cache.
	//load_vram_dump("daytona_intro");		// 26.76 FPS    44.00 FPS with CB cache.
	load_vram_dump("daytona_behind");		// 39.46 FPS    60.52 FPS with CB cache.
	//load_vram_dump("daytona_front");		// 30.26 FPS    51.73 FPS with CB cache.
	//load_vram_dump("daytona_sanic");		// 33.93 FPS    53.88 FPS with CB cache.
	//load_vram_dump("toy_front");			// 35.46 FPS    52.90 FPS with CB cache.
	//load_vram_dump("18wheel_select");		// 22.03 FPS    33.46 FPS with CB cache.

	//char name[20];
	//itoa(dump_cnt, name, 10); load_vram_dump(name);

	ImVec4 clear_color = ImVec4(0.00f, 0.00f, 0.00f, 1.00f);

	// Build texture atlas
	int disp_tex_width  = 640;
	int disp_tex_height = 480;

	// Upload texture to graphics system
	D3D11_TEXTURE2D_DESC descDisp = {};
	descDisp.Width  = disp_tex_width;
	descDisp.Height = disp_tex_height;
	descDisp.MipLevels = 1;
	descDisp.ArraySize = 1;
	descDisp.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	descDisp.SampleDesc.Count = 1;
	descDisp.Usage = D3D11_USAGE_DEFAULT;
	descDisp.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	descDisp.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

	ID3D11Texture2D *p_disp_tex = NULL;
	D3D11_SUBRESOURCE_DATA subResource = {};
	subResource.pSysMem = disp_ptr;
	subResource.SysMemPitch = descDisp.Width * 4;
	subResource.SysMemSlicePitch = 0;
	if (FAILED(g_pd3dDevice->CreateTexture2D(&descDisp, &subResource, &p_disp_tex))) {
		std::cerr << "Failed dx11 CreateTexture2D for p_disp_tex!" << std::endl;
	}

	// Create texture view
	D3D11_SHADER_RESOURCE_VIEW_DESC srvDescDisp = {};
	srvDescDisp.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	srvDescDisp.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srvDescDisp.Texture2D.MipLevels = descDisp.MipLevels;
	srvDescDisp.Texture2D.MostDetailedMip = 0;
	if (FAILED(g_pd3dDevice->CreateShaderResourceView(p_disp_tex, &srvDescDisp, &g_pDispTextureView))) {
		std::cerr << "Failed to create dx11 Resource View for g_pDispTextureView!" << std::endl;
	}
	//p_disp_tex->Release();

	// Create texture sampler
	D3D11_SAMPLER_DESC sampDescDisp = {};
	//sampDescDisp.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
	sampDescDisp.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
	sampDescDisp.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescDisp.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescDisp.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescDisp.MipLODBias = 0.f;
	sampDescDisp.MaxAnisotropy = 1;
	sampDescDisp.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
	sampDescDisp.MinLOD = 0.f;
	sampDescDisp.MaxLOD = D3D11_FLOAT32_MAX;
	if (FAILED(g_pd3dDevice->CreateSamplerState(&sampDescDisp, &g_pDispSampler))) {
		std::cerr << "Failed to create dx11 Sampler State for g_pDispSampler!" << std::endl;
	}

	// Store our identifier
	ImTextureID disp_tex_id = (ImTextureID)g_pDispTextureView;

	
	// Build texture atlas
	int tile_tex_width  = 1024;
	int tile_tex_height = 1024;

	// Upload texture to graphics system
	D3D11_TEXTURE2D_DESC descTile = {};
	descTile.Width = tile_tex_width;
	descTile.Height = tile_tex_height;
	descTile.MipLevels = 1;
	descTile.ArraySize = 1;
	descTile.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	descTile.SampleDesc.Count = 1;
	descTile.Usage = D3D11_USAGE_DEFAULT;
	descTile.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	descTile.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

	ID3D11Texture2D* p_tile_tex = NULL;
	subResource.pSysMem = tile_ptr;
	subResource.SysMemPitch = descTile.Width * 4;
	subResource.SysMemSlicePitch = 0;
	if (FAILED(g_pd3dDevice->CreateTexture2D(&descTile, &subResource, &p_tile_tex))) {
		std::cerr << "Failed dx11 CreateTexture2D for p_tile_tex!" << std::endl;
	}
	
	// Create texture view
	D3D11_SHADER_RESOURCE_VIEW_DESC srvDescTile = {};
	srvDescTile.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	srvDescTile.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srvDescTile.Texture2D.MipLevels = descTile.MipLevels;
	srvDescTile.Texture2D.MostDetailedMip = 0;
	if (FAILED(g_pd3dDevice->CreateShaderResourceView(p_tile_tex, &srvDescTile, &g_pTileTextureView))) {
		std::cerr << "Failed dx11 CreateShaderResourceView for g_pTileTextureView!" << std::endl;
	}
	//p_tile_tex->Release();

	// Create texture sampler
	D3D11_SAMPLER_DESC sampDescTile = {};
	//sampDescTile.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
	sampDescTile.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
	sampDescTile.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescTile.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescTile.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
	sampDescTile.MipLODBias = 0.f;
	sampDescTile.MaxAnisotropy = 1;
	sampDescTile.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
	sampDescTile.MinLOD = 0.f;
	sampDescTile.MaxLOD = D3D11_FLOAT32_MAX;
	if (FAILED(g_pd3dDevice->CreateSamplerState(&sampDescTile, &g_pTileSampler))) {
		std::cerr << "Failed dx11 CreateSamplerState for g_pTileSampler!" << std::endl;
	}

	// Store our identifier
	ImTextureID tile_tex_id = (ImTextureID)g_pTileTextureView;


	bool follow_writes = 0;
	int write_address = 0;

	static bool show_app_console = true;
	
	//BuildTwiddleTables();

	// imgui Main loop stuff...
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		// Poll and handle messages (inputs, window resize, etc.)
		// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
		// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
		// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
		// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}

		// Start the Dear ImGui frame
		ImGui_ImplDX11_NewFrame();
		ImGui_ImplWin32_NewFrame();
		ImGui::NewFrame();
		ImGui::Begin("Virtual Dev Board v1.0");		// Create a window called "Virtual Dev Board v1.0" and append into it.

		//ShowMyExampleAppConsole(&show_app_console);

		bool key_f3 = ImGui::IsKeyPressed(ImGuiKey_F3);
		if (ImGui::Button("RESET") || key_f3) {
			full_reset();
		}

		ImGui::SameLine(); ImGui::RadioButton("DDR FB", &display_source, 1);
		ImGui::SameLine(); ImGui::RadioButton("Direct fb_we", &display_source, 0);
		ImGui::SameLine(); ImGui::RadioButton("FB_R_SOF1", &display_sof_select, 0);
		ImGui::SameLine(); ImGui::RadioButton("FB_W_SOF1", &display_sof_select, 1);

		force_sof1 = 0;
		if (ImGui::Combo("VRAM Dump", &vram_dump_index, vram_dump_names, IM_ARRAYSIZE(vram_dump_names), 6)) {
			full_reset();
			load_vram_dump(vram_dump_names[vram_dump_index]);
			force_sof1 = 1;
		}

		uint32_t sof_offset = (display_sof_select == 0) ? pvr_ptr[0x050 >> 2] : pvr_ptr[0x060 >> 2];
		if (display_source == 1) display_sof(sof_offset, false);
		else if (force_sof1) display_sof(sof_offset, false);

		ImGui::Text("main_time %d  (%fms @ 100MHz). Around %03.3f FPS", main_time, (float)main_time / 100000, 1000 / ((float)main_time / 100000));
		//ImGui::Text("frame_count: %d  line_count: %d", frame_count, line_count);

		ImGui::Checkbox("RUN", &run_enable);
		ImGui::SameLine(); ImGui::Checkbox("Tile Highlight", &tile_highlight);
		ImGui::SameLine(); ImGui::Checkbox("Zoom 2x", &zoom);
		//ImGui::SameLine(); ImGui::Checkbox("Stop after last tile", &stop_on_last);
		ImGui::SameLine(); ImGui::Checkbox("Save 120 Frames", &render_120);

		if (single_step == 1) single_step = 0;
		if (ImGui::Button("Single Step")) {
			run_enable = 0;
			single_step = 1;
		}
		ImGui::SameLine();  ImGui::Text(" F11=Single/Stop. F5=Run. F6=Run for 'Step amount' cycles / Stop");

		if (multi_step == 1) multi_step = 0;
		if (ImGui::Button("Multi Step")) {
			run_enable = 0;
			multi_step = 1;
		}
		ImGui::SameLine(); ImGui::SliderInt("Step amount", &multi_step_amount, 4, 1024);

		if (ImGui::Button("Dump Image")) {
			dump_to_raw = 1;
		}
		ImGui::SameLine();
		if (ImGui::SliderInt("VRAM dump frame", &dump_cnt, 0, 599)) {
			char name[20];
			itoa(dump_cnt, name, 10); load_vram_dump(name);
			uint32_t sof_offset = (display_sof_select == 0) ? pvr_ptr[0x050 >> 2] : pvr_ptr[0x060 >> 2];
			display_sof(sof_offset, false);
		}

		//g_pd3dDeviceContext->PSSetSamplers(0, 1, &g_pDispSampler);
		ImGui::Image(disp_tex_id, ImVec2(disp_tex_width <<(int)zoom, disp_tex_height <<(int)zoom), ImVec2(0, 0), ImVec2(1, 1), ImColor(255, 255, 255, 255), ImColor(255, 255, 255, 128));
		ImGui::End();

		ImGui::Begin("Texture Viewer");
		ImGui::GetBackgroundDrawList()->AddCallback(CustomImGuiCallback, nullptr);
		g_pd3dDeviceContext->PSSetSamplers(0, 1, &g_pTileSampler);
		ImGui::Image(tile_tex_id, ImVec2(tile_tex_width <<2, tile_tex_height <<2), ImVec2(0, 0), ImVec2(1, 1), ImColor(255, 255, 255, 255), ImColor(255, 255, 255, 128));
		ImGui::GetBackgroundDrawList()->AddCallback(ImDrawCallback_ResetRenderState, nullptr);
		ImGui::End();

		ImGui::Begin("RAM Editor");
		mem_edit_1.Cols = 16;
		mem_edit_1.DrawContents(ram_ptr, ram_size, 0);
		ImGui::End();

		ImGui::Begin("PVR regs dump Editor");
		mem_edit_2.Cols = 4;
		mem_edit_2.DrawContents(pvr_ptr, pvr_size, 0);
		ImGui::End();

		ImGui::Begin("VRAM dump Editor");
		mem_edit_3.Cols = 8;
		//mem_edit_3.HighlightColor = 0xFF888800;	// ABGR, probably

		//uint32_t vq_index = tex_addr + 2048 + (texel_offs>>2);

		mem_edit_3.HighlightColor = 0xFF888800;	// ABGR, probably
		mem_edit_3.HighlightMin = (top->rootp->simtop__DOT__pvr__DOT__isp_vram_addr & 0x7ffff8);
		mem_edit_3.HighlightMax = (top->rootp->simtop__DOT__pvr__DOT__isp_vram_addr & 0x7ffff8) + 8;
		//mem_edit_3.HighlightMin = vq_tex_index;
		//mem_edit_3.HighlightMax = vq_tex_index + 1;
		//mem_edit_3.HighlightMin = (vq_index) & 0x7fffff;
		//mem_edit_3.HighlightMax = (vq_index+256) & 0x7fffff;
		//mem_edit_3.HighlightMin = (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_addr_last) & 0x7fffff;
		//mem_edit_3.HighlightMax = (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_addr_last+32) & 0x7fffff;
		mem_edit_3.DrawContents(vram_ptr, vram_size, 0);
		ImGui::End();

		ImGui::Begin("BIOS Editor");
		/*
		ImGui::Checkbox("Follow Writes", &follow_writes);
		if (follow_writes) write_address = top->sd_addr << 2;
		*/
		mem_edit_4.DrawContents(rom_ptr, rom_size, 0);
		ImGui::End();

		/*
		ImGui::Begin("SH4 Regfile0");
		ImGui::Text("   if_pc_plus4: 0x%08X", top->rootp->simtop__DOT__core__DOT__if_pc_plus4);
		ImGui::Text("            PC: 0x%08X", top->rootp->simtop__DOT__core__DOT__if_reg_pc);
		ImGui::Text("  im_req_valid: %d", top->rootp->im_req_valid);
		ImGui::Text("   im_req_addr: 0x%08X", top->rootp->im_req_addr);
		ImGui::Text("     bios_word: 0x%08X", bios_word);
		ImGui::Text(" im_resp_rdata: 0x%08X", top->rootp->im_resp_rdata);
		ImGui::Separator();
		ImGui::Text("  dm_req_valid: %d", top->rootp->dm_req_valid);
		ImGui::Text("   dm_req_addr: 0x%08X", top->rootp->dm_req_addr);
		ImGui::Text(" dm_resp_rdata: 0x%08X", top->rootp->dm_resp_rdata);
		ImGui::Text("  dm_req_wdata: 0x%08X", top->rootp->dm_req_wdata);
		ImGui::Text("  dm_req_wmask: 0x%02X", top->rootp->dm_req_wmask);
		ImGui::Text("    dm_req_wen: %d", top->rootp->dm_req_wen);
		ImGui::Separator();
		ImGui::Text("e1_reg_exu_opl: 0x%08X", top->rootp->simtop__DOT__core__DOT__e1_reg_exu_opl);
		ImGui::Text("e1_reg_exu_oph: 0x%08X", top->rootp->simtop__DOT__core__DOT__e1_reg_exu_oph);
		ImGui::Text(" id_instr0_opl: 0x%08X", top->rootp->simtop__DOT__core__DOT__id_instr0_opl);
		ImGui::Text(" id_instr1_opl: 0x%08X", top->rootp->simtop__DOT__core__DOT__id_instr1_opl);
		ImGui::Separator();
		ImGui::Text("  SH4 Regfile0");
		ImGui::Text("           R0: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[0]);
		ImGui::Text("           R1: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[1]);
		ImGui::Text("           R2: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[2]);
		ImGui::Text("           R3: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[3]);
		ImGui::Text("           R4: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[4]);
		ImGui::Text("           R5: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[5]);
		ImGui::Text("           R6: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[6]);
		ImGui::Text("           R7: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[7]);
		ImGui::Text("           R8: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[8]);
		ImGui::Text("           R9: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[9]);
		ImGui::Text("          R10: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[10]);
		ImGui::Text("          R11: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[11]);
		ImGui::Text("          R12: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[12]);
		ImGui::Text("          R13: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[13]);
		ImGui::Text("          R14: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[14]);
		ImGui::Text("          R15: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b0[15]);
		ImGui::Separator();
		ImGui::Text("  SH4 Regfile1");
		ImGui::Text("           R0: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[0]);
		ImGui::Text("           R1: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[1]);
		ImGui::Text("           R2: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[2]);
		ImGui::Text("           R3: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[3]);
		ImGui::Text("           R4: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[4]);
		ImGui::Text("           R5: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[5]);
		ImGui::Text("           R6: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[6]);
		ImGui::Text("           R7: 0x%08X", top->rootp->simtop__DOT__core__DOT__rf__DOT__rf_array_b1[7]);
		ImGui::End();
		*/

		/*
		ImGui::Begin("   Trace");
		ImGui::Text(" trace_valid0: %d", top->rootp->trace_valid0);
		ImGui::Text("    trace_pc0: 0x%08X", top->rootp->trace_pc0);
		ImGui::Text(" trace_instr0: 0x%04X", top->rootp->trace_instr0);
		ImGui::Text("   trace_wen0: %d", top->rootp->trace_wen0);
		ImGui::Text("  trace_wdst0: 0x%01X", top->rootp->trace_wdst0);
		ImGui::Text(" trace_wdata0: 0x%08X", top->rootp->trace_wdata0);
		ImGui::Separator();
		ImGui::Text(" trace_valid1: %d", top->rootp->trace_valid1);
		ImGui::Text("    trace_pc1: 0x%08X", top->rootp->trace_pc1);
		ImGui::Text(" trace_instr1: 0x%04X", top->rootp->trace_instr1);
		ImGui::Text("   trace_wen1: %d", top->rootp->trace_wen1);
		ImGui::Text("  trace_wdst1: 0x%01X", top->rootp->trace_wdst1);
		ImGui::Text(" trace_wdata1: 0x%08X", top->rootp->trace_wdata1);
		ImGui::Separator();

		//ImGui::Text("   calc_state: %d", top->rootp->simtop__DOT__pvr__DOT__calc_state);

		//ImGui::Text("     a_is_nan: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__a_is_nan);
		//ImGui::Text("     b_is_nan: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__b_is_nan);
		//ImGui::Text("    a_is_zero: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__a_is_zero);
		//ImGui::Text("    b_is_zero: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__b_is_zero);
		//ImGui::Text("     a_is_inf: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__a_is_inf);
		//ImGui::Text("     b_is_inf: %d", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__b_is_inf);

		ImGui::Text("         in_e: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__A1__DOT__norm1__DOT__in_e);
		ImGui::Text("         in_m: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__A1__DOT__norm1__DOT__in_m);
		ImGui::Text("        out_e: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__A1__DOT__norm1__DOT__out_e);
		ImGui::Text("        out_m: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__my_fpu_inst__DOT__A1__DOT__norm1__DOT__out_m);

		ImGui::Text("        fpu_a: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__fpu_a, *(float*)&top->rootp->simtop__DOT__pvr__DOT__fpu_a);
		ImGui::Text("        fpu_b: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__fpu_b, *(float*)&top->rootp->simtop__DOT__pvr__DOT__fpu_b);
		ImGui::Text("      fpu_res: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__fpu_res, *(float*)&top->rootp->simtop__DOT__pvr__DOT__fpu_res);
		ImGui::Text("           x1: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x1);
		ImGui::Text("           x2: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x2, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x2);
		ImGui::Text("           x3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x3);
		ImGui::Text("           y1: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y1);
		ImGui::Text("           y2: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y2, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y2);
		ImGui::Text("           y3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y3);
		ImGui::Text("    x1_sub_x3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x1_sub_x3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x1_sub_x3);
		ImGui::Text("    y2_sub_y3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y2_sub_y3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y2_sub_y3);
		ImGui::Text("    y1_sub_y3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y1_sub_y3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y1_sub_y3);
		ImGui::Text("    x2_sub_x3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x2_sub_x3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x2_sub_x3);
		ImGui::Text("x1x3_mul_y2y3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__x1x3_mul_y2y3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__x1x3_mul_y2y3);
		ImGui::Text("y1y3_mul_x2x3: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__y1y3_mul_x2x3, *(float*)&top->rootp->simtop__DOT__pvr__DOT__y1y3_mul_x2x3);
		ImGui::Text("         area: 0x%08X  %f", top->rootp->simtop__DOT__pvr__DOT__area, *(float*)&top->rootp->simtop__DOT__pvr__DOT__area);
		ImGui::End();
		*/

		ImGui::Begin("PVR Main Regs");
		ImGui::Text("                  ID: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__ID); 				// R   Device ID
		ImGui::Text("            REVISION: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__REVISION); 			// R   Revision number
		ImGui::Text("           SOFTRESET: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SOFTRESET); 			// RW  CORE & TA software reset
		ImGui::Text("         STARTRENDER: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__STARTRENDER); 		// RW  Drawing start
		ImGui::Text("              SELECT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TEST_SELECT); 		// RW  Test - writing this register is prohibited.
		ImGui::Text("          PARAM_BASE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__PARAM_BASE); 		// RW  Base address for ISP regs
		ImGui::Text("         REGION_BASE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__REGION_BASE); 		// RW  Base address for Region Array
		ImGui::Text("       SPAN_SORT_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPAN_SORT_CFG); 		// RW  Span Sorter control
		ImGui::Text("       VO_BORDER_COL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__VO_BORDER_COL); 		// RW  Border area color
		ImGui::Text("           FB_R_CTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_R_CTRL); 			// RW  Frame buffer read control
		ImGui::Text("           FB_W_CTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_W_CTRL); 			// RW  Frame buffer write control
		ImGui::Text("     FB_W_LINESTRIDE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_W_LINESTRIDE); 	// RW  Frame buffer line stride
		ImGui::Text("           FB_R_SOF1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_R_SOF1); 			// RW  Read start address for field - 1/strip - 1
		ImGui::Text("           FB_R_SOF2: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_R_SOF2); 			// RW  Read start address for field - 2/strip - 2
		ImGui::Text("           FB_R_SIZE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_R_SIZE); 			// RW  Frame buffer XY size	
		ImGui::Text("           FB_W_SOF1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_W_SOF1); 			// RW  Write start address for field - 1/strip - 1
		ImGui::Text("           FB_W_SOF2: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_W_SOF2); 			// RW  Write start address for field - 2/strip - 2
		ImGui::Text("           FB_X_CLIP: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_X_CLIP); 			// RW  Pixel clip X coordinate
		ImGui::Text("           FB_Y_CLIP: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_Y_CLIP); 			// RW  Pixel clip Y coordinate

		ImGui::Text("      FPU_SHAD_SCALE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FPU_SHAD_SCALE); 	// RW  Intensity Volume mode
		ImGui::Text("        FPU_CULL_VAL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FPU_CULL_VAL); 		// RW  Comparison value for culling
		ImGui::Text("       FPU_PARAM_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FPU_PARAM_CFG); 		// RW  register read control
		ImGui::Text("         HALF_OFFSET: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__HALF_OFFSET); 		// RW  Pixel sampling control
		ImGui::Text("        FPU_PERP_VAL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FPU_PERP_VAL); 		// RW  Comparison value for perpendicular polygons
		ImGui::Text("       ISP_BACKGND_D: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__ISP_BACKGND_D); 		// RW  Background surface depth
		ImGui::Text("       ISP_BACKGND_T: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__ISP_BACKGND_T); 		// RW  Background surface tag

		ImGui::Text("        ISP_FEED_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__ISP_FEED_CFG); 		// RW  Translucent polygon sort mode

		ImGui::Text("       SDRAM_REFRESH: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SDRAM_REFRESH); 		// RW  Texture memory refresh counter
		ImGui::Text("       SDRAM_ARB_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SDRAM_ARB_CFG); 		// RW  Texture memory arbiter control
		ImGui::Text("           SDRAM_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SDRAM_CFG); 			// RW  Texture memory control

		ImGui::Text("         FOG_COL_RAM: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_COL_RAM); 		// RW  Color for Look Up table Fog
		ImGui::Text("        FOG_COL_VERT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_COL_VERT); 		// RW  Color for vertex Fog
		ImGui::Text("         FOG_DENSITY: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_DENSITY); 		// RW  Fog scale value
		ImGui::Text("       FOG_CLAMP_MAX: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_CLAMP_MAX); 		// RW  Color clamping maximum value
		ImGui::Text("       FOG_CLAMP_MIN: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_CLAMP_MIN); 		// RW  Color clamping minimum value
		ImGui::Text("     SPG_TRIGGER_POS: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_TRIGGER_POS); 	// RW  External trigger signal HV counter value
		ImGui::Text("      SPG_HBLANK_INT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_HBLANK_INT); 	// RW  H-blank interrupt control	
		ImGui::Text("      SPG_VBLANK_INT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_VBLANK_INT); 	// RW  V-blank interrupt control	
		ImGui::Text("         SPG_CONTROL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_CONTROL); 		// RW  Sync pulse generator control
		ImGui::Text("          SPG_HBLANK: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_HBLANK); 		// RW  H-blank control
		ImGui::Text("            SPG_LOAD: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_LOAD); 			// RW  HV counter load value
		ImGui::Text("          SPG_VBLANK: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_VBLANK); 		// RW  V-blank control
		ImGui::Text("           SPG_WIDTH: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_WIDTH); 			// RW  Sync width control
		ImGui::Text("        TEXT_CONTROL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TEXT_CONTROL); 		// RW  Texturing control
		ImGui::Text("          VO_CONTROL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__VO_CONTROL); 		// RW  Video output control
		ImGui::Text("           VO_STARTX: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__VO_STARTX); 			// RW  Video output start X position
		ImGui::Text("           VO_STARTY: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__VO_STARTY); 			// RW  Video output start Y position
		ImGui::Text("          SCALER_CTL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SCALER_CTL); 		// RW  X & Y scaler control
		ImGui::Text("        PAL_RAM_CTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__PAL_RAM_CTRL); 		// RW  Palette RAM control
		ImGui::Text("          SPG_STATUS: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__SPG_STATUS); 		// R   Sync pulse generator status
		ImGui::Text("        FB_BURSTCTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_BURSTCTRL); 		// RW  Frame buffer burst control
		ImGui::Text("            FB_C_SOF: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FB_C_SOF); 			// R   Current frame buffer start address
		ImGui::Text("             Y_COEFF: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__Y_COEFF); 			// RW  Y scaling coefficient
		ImGui::Text("        PT_ALPHA_REF: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__PT_ALPHA_REF); 		// RW  Alpha value for Punch Through polygon comparison
		ImGui::End();

		ImGui::Separator();
		ImGui::Begin("TA Regs");
		ImGui::Text("          TA_OL_BASE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_OL_BASE); 		// RW  Object list write start address
		ImGui::Text("         TA_ISP_BASE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_ISP_BASE); 		// RW  ISP/TSP register write start address
		ImGui::Text("         TA_OL_LIMIT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_OL_LIMIT); 		// RW  Start address of next Object Pointer Block
		ImGui::Text("        TA_ISP_LIMIT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_ISP_LIMIT); 		// RW  Current ISP/TSP register write address
		ImGui::Text("         TA_NEXT_OPB: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_NEXT_OPB); 		// R   Global Tile clip control
		ImGui::Text("      TA_ISP_CURRENT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_ISP_CURRENT); 	// R   Current ISP/TSP register write address
		ImGui::Text("   TA_GLOB_TILE_CLIP: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_GLOB_TILE_CLIP); 	// RW  Global Tile clip control
		ImGui::Text("       TA_ALLOC_CTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_ALLOC_CTRL); 		// RW  Object list control
		ImGui::Text("        TA_LIST_INIT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_LIST_INIT); 		// RW  TA initialization
		ImGui::Text("     TA_YUV_TEX_BASE: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_YUV_TEX_BASE); 	// RW  YUV422 texture write start address
		ImGui::Text("     TA_YUV_TEX_CTRL: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_YUV_TEX_CTRL); 	// RW  YUV converter control
		ImGui::Text("      TA_YUV_TEX_CNT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_YUV_TEX_CNT); 	// R   YUV converter macro block counter value

		ImGui::Text("        TA_LIST_CONT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_LIST_CONT); 		// RW  TA continuation processing
		ImGui::Text("    TA_NEXT_OPB_INIT: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_NEXT_OPB_INIT); 	// RW  Additional OPB starting address

		ImGui::Text("     FOG_TABLE_START: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_TABLE_START); 	// RW  Look-up table Fog data
		ImGui::Text("       FOG_TABLE_END: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__FOG_TABLE_END);

		ImGui::Text("TA_OL_POINTERS_START: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_OL_POINTERS_START); // R   TA object List Pointer data
		ImGui::Text("  TA_OL_POINTERS_END: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__TA_OL_POINTERS_END);

		ImGui::Text("   PALETTE_RAM_START: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__PALETTE_RAM_START); 	// RW  Palette RAM
		ImGui::Text("     PALETTE_RAM_END: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__pvr_regs_inst__DOT__PALETTE_RAM_END);
		ImGui::End();

		ImGui::Begin(" RA Parser");
		ImGui::Text("        ra_state: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_state);
		ImGui::Text("    ra_vram_addr: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__ra_vram_addr);
		ImGui::Text("     next_region: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__next_region);
		ImGui::Text("   ol_jump_bytes: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ol_jump_bytes);
		ImGui::Separator();
		ImGui::Text("   FPU_PARAM_CFG: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__FPU_PARAM_CFG);
		ImGui::Text("      ra_control: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_control);
		ImGui::Text("    ra_cont_last: %d", top->rootp->simtop__DOT__pvr__DOT__ra_cont_last);
		ImGui::Text("ra_cont_zclear_n: %d", top->rootp->simtop__DOT__pvr__DOT__ra_cont_zclear_n);
		ImGui::Text(" ra_cont_flush_n: %d", top->rootp->simtop__DOT__pvr__DOT__ra_cont_flush_n);
		ImGui::Text("   ra_cont_tiley: %d", top->rootp->simtop__DOT__pvr__DOT__ra_cont_tiley);
		ImGui::Text("   ra_cont_tilex: %d", top->rootp->simtop__DOT__pvr__DOT__ra_cont_tilex);
		ImGui::Separator();
		uint8_t type_cnt_minus_1 = top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__type_cnt-1;
		ImGui::Text("     type_cnt -1: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__type_cnt-1);
		if (type_cnt_minus_1==0) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("       ra_opaque: 0x%08X (0)", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_opaque); if (type_cnt_minus_1==0) ImGui::PopStyleColor();
		if (type_cnt_minus_1==1) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("       ra_puncht: 0x%08X (1)", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_puncht); if (type_cnt_minus_1==1) ImGui::PopStyleColor();
		if (type_cnt_minus_1==2) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("       ra_op_mod: 0x%08X (2)", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_op_mod); if (type_cnt_minus_1==2) ImGui::PopStyleColor();
		if (type_cnt_minus_1==3) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("        ra_trans: 0x%08X (3)", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_trans);  if (type_cnt_minus_1==3) ImGui::PopStyleColor();
		if (type_cnt_minus_1==4) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("       ra_tr_mod: 0x%08X (4)", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_tr_mod); if (type_cnt_minus_1==4) ImGui::PopStyleColor();
		ImGui::Separator();
		uint8_t s_mask = top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__strip_mask;
		ImGui::Text("        opb_word: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__opb_word);

		if ((top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__opb_word & 0x80000000) == 0)               ImGui::Text("  Triangle Strip");
		else if ((top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__opb_word & 0xE0000000) == 0x80000000) ImGui::Text("  Triangle Array");
		else if ((top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__opb_word & 0xE0000000) == 0xA0000000) ImGui::Text("      Quad Array");
		else ImGui::Text("   Unknown Prim!");

		ImGui::Text("  isp  strip_cnt: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__strip_cnt);
		ImGui::Text("      strip_mask: 0b%d%d%d%d%d%d", (s_mask & 32) >> 5, (s_mask & 16) >> 4, (s_mask & 8) >> 3, (s_mask & 4) >> 2, (s_mask & 2) >> 1, (s_mask & 1));
		ImGui::Text("       num_prims: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__num_prims);
		ImGui::Text("          shadow: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__shadow);
		ImGui::Text("            skip: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__skip);
		ImGui::Text("             eol: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__eol);
		ImGui::Separator();
		ImGui::Text("  ra_entry_valid: %d", top->rootp->simtop__DOT__pvr__DOT__ra_entry_valid);
		ImGui::Text("       poly_addr: 0x%06X", top->rootp->simtop__DOT__pvr__DOT__poly_addr);	// 24-bit VRAM addr.
		//ImGui::Text("     render_poly: %d", top->rootp->simtop__DOT__pvr__DOT__render_poly);
		//ImGui::Text("     z_buff_addr: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_addr);
		//ImGui::Text("           old_z: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__old_z);
		ImGui::Text("         clear_z: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__clear_z);
		//ImGui::Text("           z_cnt: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__clear_cnt);
		ImGui::End();

		ImGui::Begin(" ISP Parser");
		ImGui::Text("      fb_writedata: 0x%08X", top->fb_writedata);
		ImGui::Text("           fb_addr: 0x%06X", top->fb_addr);
		ImGui::Text("        fb_byteena: 0x%02X", top->fb_byteena);
		ImGui::Text("             fb_we: %d", top->fb_we);
		ImGui::Separator();
		ImGui::Text("     isp_vram_addr: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_addr);
		//ImGui::Text("         cache_hit: %d", top->rootp->simtop__DOT__vram_read_cache_inst__DOT__cache_hit);
		//ImGui::Text("           filling: %d", top->rootp->simtop__DOT__vram_read_cache_inst__DOT__filling);
		//ImGui::Text("            rd_ptr: %d", top->rootp->simtop__DOT__vram_read_cache_inst__DOT__rd_ptr);
		//ImGui::Text("          DDRAM_RD: %d", top->rootp->simtop__DOT__DDRAM_RD);
		//ImGui::Text("        DDRAM_ADDR: 0x%08X", top->rootp->simtop__DOT__DDRAM_ADDR);
		//ImGui::Text("        DDRAM_DOUT: 0x%08X", top->rootp->simtop__DOT__DDRAM_DOUT);
		//ImGui::Text("  DDRAM_DOUT_READY: %d", top->rootp->simtop__DOT__DDRAM_DOUT_READY);
		//ImGui::Text("        vram_valid: %d", top->rootp->simtop__DOT__vram_valid);
		ImGui::Text("      isp_vram_din: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_din);
		ImGui::Text("    isp vram_valid: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_valid);
		ImGui::Separator();
		ImGui::Text("         isp_state: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state);
		ImGui::Text("         vram_wait: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_wait);
		ImGui::Text("       isp_vram_rd: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_rd);
		ImGui::Text("  isp_vram_rd_pend: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_rd_pend);
		ImGui::Text("     isp_vram_addr: 0x%06X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_addr);
		//ImGui::Text("       cache_state: %d", top->rootp->simtop__DOT__pvr__DOT__simple_cache_inst__DOT__state);
		//ImGui::Text("       cache_valid: %d", top->rootp->simtop__DOT__pvr__DOT__simple_cache_inst__DOT__cache_valid_out);
		//ImGui::Text("         ddr_state: %d", top->rootp->simtop__DOT__ddr_state);
		ImGui::Text("          prim_tag: 0x%03X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_tag);
		ImGui::Text("          max_tags: 0x%03X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__max_tags);
		ImGui::SameLine(); ImGui::Text(" (%d)", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__max_tags);
		ImGui::Text("         tsp_state: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_state);
		ImGui::Text("          tsp_busy: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_state != 0);
		ImGui::Text("   total_tri_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__total_tri_count);
		ImGui::Text("   total_vis_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__total_vis_count);
		ImGui::Separator();
		ImGui::Text("      prim_tag_out: 0x%03X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_tag_out);
		ImGui::Text("         core x_ps: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__x_ps);
		ImGui::Text("         core y_ps: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__y_ps);
		ImGui::Text("    core x_ps[4:0]: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__x_ps & 0x1f);
		ImGui::Text("    core y_ps[4:0]: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__y_ps & 0x1f);
		//ImGui::Text("       tri_min_row: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tri_min_row);
		//ImGui::Text("       tri_max_row: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tri_max_row);
		/*
		ImGui::Text("           tsp_row: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_row);
		ImGui::Text("        tsp_startx: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_startx);
		ImGui::Text("          tsp_endx: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_endx);
		ImGui::Text("      tsp_fifo_din: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_fifo_din);
		*/
		ImGui::Separator();
		/*
		ImGui::Text(" TSP Tag Sorter");
		ImGui::Text("             state: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_sorter_inst__DOT__state);
		ImGui::Text("           row_sel: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_sorter_inst__DOT__row_sel);
		ImGui::Text("           col_sel: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_sorter_inst__DOT__col_sel);
		ImGui::Text("          prim_tag: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_sorter_inst__DOT__prim_tag);
		ImGui::Text("        run_active: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_sorter_inst__DOT__current_run_active);
		*/
		//ImGui::Text("         sim mult1: %f", mult1);
		//ImGui::Text("        core mult1: %i", (int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__mult1/(1<<FRAC_BITS));
		//ImGui::Text("    core mult1 raw: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__mult1);
		// Many of these should probably be cast as int64_t before casting to floats.
		// But there is an issue with it displaying a very large float value unless cast as int32_t instead?
		// ie. I can't remember what the correct casts and printf format is. ElectronAsh.

		ImGui::Text(" sim U.FZ3_sub_FZ1: %f", U.FZ3_sub_FZ1);
		//ImGui::Text("core U.FZ3_sub_FZ1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__FZ3_sub_FZ1) / (1 << Z_FRAC_BITS));
		ImGui::Text(" sim U.FY2_sub_FY1: %f", U.FY2_sub_FY1);
		//ImGui::Text("core U.FY2_sub_FY1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__FY2_sub_FY1) / (1 << FRAC_BITS));
		//ImGui::Text("   sim U.Aa_mult_1: %f", U.Aa_mult_1);
		//ImGui::Text("  core U.Aa_mult_1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Aa_mult_1)/(1<< Z_FRAC_BITS));
		//ImGui::Separator();
		//ImGui::Text("   sim U.Aa_mult_2: %f", U.Aa_mult_2);
		//ImGui::Text("  core U.Aa_mult_2: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Aa_mult_2) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		ImGui::Text("          sim U.Aa: %f", U.Aa);
		//ImGui::Text("         core U Aa: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Aa) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		//ImGui::Text("   sim U.Ba_mult_1: %f", U.Ba_mult_1);
		//ImGui::Text("  core U.Ba_mult_1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Ba_mult_1)/(1<<Z_FRAC_BITS));
		//ImGui::Separator();
		//ImGui::Text("   sim U.Ba_mult_2: %f", U.Ba_mult_2);
		//ImGui::Text("  core U.Ba_mult_2: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Ba_mult_2)/(1<<Z_FRAC_BITS));
		//ImGui::Separator();
		ImGui::Text("          sim U.Ba: %f", U.Ba);
		//ImGui::Text("         core U.Ba: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__Ba) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		ImGui::Text("       sim U.BIG_C: %f", U.BIG_C);
		//ImGui::Text("      core U.BIG_C: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__BIG_C) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		ImGui::Text("     sim U.small_c: %f", U.small_c);
		//ImGui::Text("    core U.small_c: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__small_c) / (1 << Z_FRAC_BITS));
		//ImGui::Separator();
		//ImGui::Text("  U.Aa_shifted raw: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__Aa_shifted);
		//ImGui::Text("  U.Ba_shifted raw: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__Ba_shifted);
		ImGui::Separator();
		ImGui::Text("         sim U.ddx: %f", U.ddx);
		//ImGui::Text("       core U.FDDX: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__FDDX) / (1 << Z_FRAC_BITS));
		//ImGui::Text("   core U.FDDX raw: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__FDDX);
		ImGui::Separator();
		ImGui::Text("         sim U.ddy: %f", U.ddy);
		//ImGui::Text("       core U.FDDY: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__interp_inst_u__DOT__FDDY) / (1 << Z_FRAC_BITS));
		//ImGui::Text("   core U.FDDY raw: 0x%016llX",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__FDDY);
		ImGui::Separator();

		//ImGui::Text("   core inTriangle: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTriangle);
		//ImGui::Text("  core inTriangle1: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__inTriangle1);
		//ImGui::Text("          core sgn: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__sgn);
		//ImGui::Text("          vram_din: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__vram_din);
		//ImGui::Text("      isp_vram_din: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_din);
		//ImGui::Text("          tex_wait: %d",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_wait);
		//ImGui::Text("      cb_cache_hit: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__cb_cache_hit);
		//ImGui::Text("     cb_word_index: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__cb_word_index);
		ImGui::Separator();
		
		/*
		//ImGui::Text("        sim 1/invW: %f", 1/invW);
		ImGui::Text("        core inTri: %08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri);
		ImGui::Text("         rle state: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__state);
		//ImGui::Text("      rle emit_ptr: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__emit_ptr);
		ImGui::Text("         rle_valid: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__rle_valid);
		ImGui::Text("           rle_tag: %03X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__rle_tag);
		ImGui::Text("         rle_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__rle_count);
		//ImGui::Text("     run_write_ptr: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__rle_by_tag_inst__DOT__run_write_ptr);
		*/

		//ImGui::Text("          core sgn: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__sgn);
		ImGui::Text("             sim z: %f", invW);
		ImGui::Text("  core IP_Z_INTERP: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__IP_Z_R[0]) / (1 << Z_FRAC_BITS));
		ImGui::Text("        core z_out: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__z_out) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		//ImGui::Text("  core W_interp[0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W_interp[0]) / (1 << Z_FRAC_BITS));
		//ImGui::Text("           core W1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W1) / (1 << Z_FRAC_BITS));
		//ImGui::Text("           core W2: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W2) / (1 << Z_FRAC_BITS));
		//ImGui::Text("           core W3: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W3) / (1 << Z_FRAC_BITS));
		//ImGui::Text("          core Uw1: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__Uw1) / (1 << Z_FRAC_BITS));
		//ImGui::Text("          core Uw2: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__Uw2) / (1 << Z_FRAC_BITS));
		//ImGui::Text("          core Uw3: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__Uw3) / (1 << Z_FRAC_BITS));
		//ImGui::Text("          core Uw2: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W3) / (1 << Z_FRAC_BITS));
		//ImGui::Text("          core Uw3: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__W3) / (1 << Z_FRAC_BITS));
		ImGui::Separator();
		ImGui::Text("   sim IP.U_INTERP: %f", sim_ip_u);
		ImGui::Text("  core IP_U_INTERP: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__IP_U_INTERP) / (1 << Z_FRAC_BITS));
		ImGui::Text("   pre-flip sim ui: %d 0x%03X", (uint16_t)sim_u_divz & 0x3ff, (uint16_t)sim_u_divz & 0x3ff);
		ImGui::Text("  pre-flip core ui: %d 0x%03X", (uint16_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__uv_clamp_flip_inst__DOT__u_div_z,
			(uint16_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__uv_clamp_flip_inst__DOT__u_div_z);
		ImGui::Text("(clmp/flip) sim ui: %d 0x%03X", sim_ui_flipped, sim_ui_flipped);
		ImGui::Text("(clmp/flip)core ui: %d 0x%03X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__u_flipped,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__u_flipped);
		//ImGui::Text("       tex addr ui: %d",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__ui);
		ImGui::Separator();
		ImGui::Text("   sim IP.V_INTERP: %f", sim_ip_v);
		ImGui::Text("  core IP_V_INTERP: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__IP_V_INTERP) / (1 << Z_FRAC_BITS));
		ImGui::Text("   pre-flip sim vi: %d 0x%03X", (uint16_t)sim_v_divz /*&0x3ff*/, (uint16_t)sim_v_divz /*&0x3ff*/);
		ImGui::Text("  pre-flip core vi: %d 0x%03X", (uint16_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__uv_clamp_flip_inst__DOT__v_div_z,
			(uint16_t)top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__uv_clamp_flip_inst__DOT__v_div_z);
		ImGui::Text("(clmp/flip) sim vi: %d 0x%03X", sim_vi_flipped, sim_vi_flipped);
		ImGui::Text("(clmp/flip)core vi: %d 0x%03X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__v_flipped,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__v_flipped);
		//ImGui::Text("       tex addr vi: %d",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__vi);
		ImGui::Separator();
		ImGui::Text("       core ui: 0x%03X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__ui);
		ImGui::Text("       core vi: 0x%03X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vi);
		ImGui::Text("vram_word_addr: 0x%06X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vram_word_addr);
		ImGui::Text("       tex din: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vram_din);
		//ImGui::Text("    texel_argb: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__texel_argb);
		/*
		ImGui::Text("     z_col_0[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_0[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_1[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_1[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_2[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_2[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_3[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_3[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_4[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_4[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_5[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_5[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_6[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_6[0])/(1<<FRAC_BITS));
		ImGui::Text("     z_col_7[row0]: %f", (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_7[0])/(1<<FRAC_BITS));
		ImGui::Separator();
		ImGui::Text("allow_z_write[31:0]: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__allow_z_write);
		ImGui::Separator();
		ImGui::Text("        inTri[31:0]: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri);
		ImGui::Text(" leading_zeros[4:0]: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__leading_zeros);
		ImGui::Text("trailing_zeros[4:0]: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__trailing_zeros);
		*/

		/*
		ImGui::Text("        test float: %f", *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__test_float);
		ImGui::Text("          test HEX: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__test_float);
		ImGui::Text("    core float exp: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__exp);
		ImGui::Text("core float man HEX: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__man);
		ImGui::Text("   float_shift HEX: 0x%016llX", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_shift);
		ImGui::Text("    core fixed HEX: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__test_fixed);
		ImGui::Text("  fixed (as float): %f", (float)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__test_fixed / (1<<FRAC_BITS) );
		*/

		/*
		ImGui::Text("        c float x1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x);
		ImGui::Text("    core    x1 man: 0x%016llX",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_x1__DOT__man);
		ImGui::Text("     FX1_FIXED HEX: 0x%08X",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_x1__DOT__fixed);
		ImGui::Text("   FX1_FIXED float: %f", (float)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_x1__DOT__fixed / (1<<FRAC_BITS) );
		*/

		/*
		ImGui::Text("     core fdx12_in: 0x%08X",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_dx12__DOT__float_in);
		ImGui::Text("     core fdx12_in: %f", (float)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_dx12__DOT__float_in);
		ImGui::Text("    core fdx12 man: 0x%016llX",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_dx12__DOT__man);
		ImGui::Text("   FDX12_FIXED HEX: 0x%08X",top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_dx12__DOT__fixed);
		ImGui::Text(" FDX12_FIXED float: %f", (float)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_dx12__DOT__fixed / (1<<FRAC_BITS));
		*/

		ImGui::Separator();
		ImGui::Text("           pix_fmt:");
		ImGui::SameLine();
		switch (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pix_fmt) {
			case 0: ImGui::Text("ARGB 1555 (0)"); break; // 0  1555 value: 1 bit; RGB values: 5 bits each
			case 7: ImGui::Text("Rsvd 1555 (7)"); break; // 7  Reserved        Regarded as 1555
			case 1: ImGui::Text(" RGB  565 (1)"); break; // 1  565      R value: 5 bits; G value: 6 bits; B value: 5 bits
			case 2: ImGui::Text("ARGB 4444 (2)"); break; // 2  4444 value: 4 bits; RGB values: 4 bits each
			case 3: ImGui::Text(" YUV      (3)"); break; // 3  YUV422 32 bits per 2 pixels; YUYV values: 8 bits each
			case 4: ImGui::Text("BumpMap   (4)"); break; // 4  Bump Map 	16 bits/pixel; S value: 8 bits; R value: 8 bits
			case 5: ImGui::Text("Pal4      (5)"); break; // 5  4 BPP Palette   Palette texture with 4 bits/pixel
			case 6: ImGui::Text("Pal8      (6)"); break; // 6  8 BPP Palette   Palette texture with 8 bits/pixel
		}
		ImGui::Text("      tex size u/v: %dx%d", 8 << (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_size & 7),
			8 << (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_size & 7));
		ImGui::Text("     tex_src_alpha: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_src_alpha);
		ImGui::Text("     tex_dst_alpha: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_dst_alpha);
		ImGui::Text("    tex_src_select: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_src_select);
		ImGui::Text("    tex_dst_select: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_dst_select);
		ImGui::Text("            u_flip: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_flip);
		ImGui::Text("            v_flip: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_flip);
		//ImGui::Text("          base_dx0: 0x%010X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__base_dx0);
		//ImGui::Text("          base_dx1: 0x%010X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__base_dx1);
		//ImGui::Text("          base_dx2: 0x%010X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__base_dx2);
		ImGui::Text("           u_clamp: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_u_clamp);
		ImGui::Text("           v_clamp: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_v_clamp);
		ImGui::Text("     is_quad_array: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__is_quad_array);
		ImGui::Text("           texture: %d  mipmap: %d  vq: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture,
			top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__mip_map,
			top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vq_comp);
		ImGui::SameLine();
		ImGui::Text("              twid: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__is_twid);
		ImGui::Text("            uv_16b: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__uv_16_bit);
		ImGui::SameLine();
		ImGui::Text(" offset: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__offset);
		ImGui::SameLine();
		ImGui::Text(" gour: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__gouraud);
		//ImGui::Text("       stride_flag: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__stride_flag);
		//ImGui::Text(" stride: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__stride);
		ImGui::Text("        shade_inst: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__shade_inst_r);
		ImGui::Text("        texel_argb: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__texel_argb);
		ImGui::Text("        final_argb: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__final_argb);
		//ImGui::Text("         tex_addr: 0x%08X", tex_addr);
		//ImGui::Text("       texel_offs: 0x%05X", texel_offs);
		//ImGui::Text("tex_byte_addr sim (byte): 0x%08X", tex_byte_addr<<3);
		ImGui::Text("  vram_(byte)_addr: 0x%06X", vram_word_addr);
		//ImGui::Text("     vq_index_addr: 0x%08X",vq_index_addr );
		ImGui::Text("         twop core: 0x%05X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__twop);
		ImGui::Separator();
		ImGui::Text("         strip_cnt: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__strip_cnt);
		ImGui::SameLine(); ImGui::Text(" array_cnt: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__array_cnt);
		ImGui::Text("          isp_inst: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_inst);
		ImGui::Text("          tsp_inst: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_inst);
		ImGui::Text("          tcw_word: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tcw_word);
		ImGui::Separator();

		/*
		ImGui::Text("  y1_mult_overflow: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__y1_mult_overflow);
		ImGui::Text("  y2_mult_overflow: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__y2_mult_overflow);
		ImGui::Text("  y3_mult_overflow: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__y3_mult_overflow);
		ImGui::Text("edge_eval0_overflow: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__edge_eval0_overflow);
		ImGui::Text("edge_eval1_overflow: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__edge_eval1_overflow);
		ImGui::Text("edge_eval2_overflow: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__edge_eval2_overflow);
		ImGui::Text("cross_term_overflow: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri_calc_inst__DOT__cross_term_overflow);
		*/

		ImGui::Text("        core inTri: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri);
		//ImGui::Text("       IP_G_INTERP: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__IP_G_INTERP);
		//ImGui::Text("    vert_a_x_shift: %d", vert_a_x_shift);
		ImGui::Text("          vert_a_x: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_x);
		ImGui::Text("       FX1 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX1_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX1_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_a_y: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_y,  *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_y);
		ImGui::Text("       FY1 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY1_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY1_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_a_z: 0x%010X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_z,  *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_z);
		ImGui::Text("       FZ1 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ1_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ1_FIXED) / (1 << Z_FRAC_BITS));
		ImGui::Text("         vert_a_u0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u0);
		ImGui::Text("         vert_a_v0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v0);
		//ImGui::Text("         vert_a_u1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u1);
		//ImGui::Text("         vert_a_v1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v1);
		//ImGui::Text(" vert_a_base_col_0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__vert_a_base_col_0_out);
		//ImGui::Text(" vert_a_base_col_1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_base_col_1);
		ImGui::Text("    vert_a_off_col: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_off_col);
		ImGui::Separator();
		ImGui::Text("          vert_b_x: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_x, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_x);
		ImGui::Text("       FX2 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX2_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX2_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_b_y: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_y, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_y);
		ImGui::Text("       FY2 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY2_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY2_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_b_z: 0x%010X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_z, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_z);
		ImGui::Text("       FZ2 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ2_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ2_FIXED) / (1 << Z_FRAC_BITS));
		ImGui::Text("         vert_b_u0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u0);
		ImGui::Text("         vert_b_v0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v0);
		//ImGui::Text("         vert_b_u1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u1);
		//ImGui::Text("         vert_b_v1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v1);
		//ImGui::Text(" vert_b_base_col_0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__vert_b_base_col_0_out);
		//ImGui::Text(" vert_b_base_col_1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_base_col_1);
		//ImGui::Text("    vert_b_off_col: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__vert_b_off_col_out);
		ImGui::Separator();
		ImGui::Text("          vert_c_x: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_x, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_x);
		ImGui::Text("       FX3 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX3_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FX3_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_c_y: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_y, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_y);
		ImGui::Text("       FY3 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY3_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FY3_FIXED) / (1 << FRAC_BITS));
		ImGui::Text("          vert_c_z: 0x%010X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_z, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_z);
		ImGui::Text("       FZ3 / float: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ3_FIXED, (float)((int32_t)top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FZ3_FIXED) / (1 << Z_FRAC_BITS));
		ImGui::Text("         vert_c_u0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u0);
		ImGui::Text("         vert_c_v0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v0);
		//ImGui::Text("         vert_c_u1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u1);
		//ImGui::Text("         vert_c_v1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v1);
		//ImGui::Text(" vert_c_base_col_0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__vert_c_base_col_0_out);
		//ImGui::Text(" vert_c_base_col_1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_base_col_1);
		//ImGui::Text("    vert_c_off_col: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__vert_c_off_col_out);
		ImGui::Separator();
		ImGui::Text("          vert_d_x: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_x, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_x);
		ImGui::Text("          vert_d_y: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_y, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_y);
		ImGui::Text("          vert_d_z: 0x%010X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_z, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_z);
		ImGui::Text("         vert_d_u0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_u0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_u0);
		ImGui::Text("         vert_d_v0: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_v0, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_v0);
		//ImGui::Text("         vert_d_u1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_u1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_u1);
		//ImGui::Text("         vert_d_v1: 0x%08X %+03.6f", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_v1, *(float*)&top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_v1);
		ImGui::Text(" vert_d_base_col_0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_base_col_0);
		//ImGui::Text(" vert_d_base_col_1: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_base_col_1);
		ImGui::Text("    vert_d_off_col: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_d_off_col);

		ImGui::Text("          vert_a_z: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_z);
		ImGui::Text("          vert_b_z: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_z);
		ImGui::Text("          vert_c_z: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_z);
		ImGui::Text("         vert_a_u0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_u0);
		ImGui::Text("         vert_b_u0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_u0);
		ImGui::Text("         vert_c_u0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_u0);
		ImGui::Text("         vert_a_v0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_a_v0);
		ImGui::Text("         vert_b_v0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_b_v0);
		ImGui::Text("         vert_c_v0: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__vert_c_v0);
		auto show_q17_48 = [](const char* label, uint64_t raw) {
			const uint64_t raw48 = raw & 0x0000FFFFFFFFFFFFULL;
			const int64_t value = sign_extend_48(raw48);
			ImGui::Text("%-20s 0x%012llX %+12.6f", label,
				(unsigned long long)raw48,
				(double)value / (double)(1ULL << Z_FRAC_BITS));
		};

		ImGui::Separator();
		ImGui::Text("Incoming ISP params");
		show_q17_48("FDDX_U", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDX_U);
		show_q17_48("FDDY_U", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDY_U);
		show_q17_48("FDDX_V", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDX_V);
		show_q17_48("FDDY_V", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__FDDY_V);
		show_q17_48("tile_start_u", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_start_u);
		show_q17_48("tile_start_v", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_start_v);

		ImGui::Separator();
		ImGui::Text("Last issued TSP sample");
		if (last_tsp_issue.valid) {
			ImGui::Text("cycle %-10llu bank %u tile (%u,%u) tag 0x%03X pixel (%u,%u)",
				(unsigned long long)last_tsp_issue.cycle,
				last_tsp_issue.bank,
				last_tsp_issue.tile_x,
				last_tsp_issue.tile_y,
				last_tsp_issue.tag,
				last_tsp_issue.x,
				last_tsp_issue.y);
			ImGui::Text("isp 0x%08X  tsp 0x%08X  tcw 0x%08X",
				last_tsp_issue.isp_inst,
				last_tsp_issue.tsp_inst,
				last_tsp_issue.tcw_word);
			show_q17_48("FDDX_U", last_tsp_issue.fddx_u);
			show_q17_48("FDDY_U", last_tsp_issue.fddy_u);
			show_q17_48("FDDX_V", last_tsp_issue.fddx_v);
			show_q17_48("FDDY_V", last_tsp_issue.fddy_v);
			show_q17_48("tile_start_u", last_tsp_issue.tile_start_u);
			show_q17_48("tile_start_v", last_tsp_issue.tile_start_v);

			const ParamWriteSnapshot &source = last_tsp_issue.param_write;
			if (source.valid) {
				const uint64_t mask48 = 0x0000FFFFFFFFFFFFULL;
				const bool coeff_match =
					((source.fddx_u & mask48) == (last_tsp_issue.fddx_u & mask48)) &&
					((source.fddy_u & mask48) == (last_tsp_issue.fddy_u & mask48)) &&
					((source.fddx_v & mask48) == (last_tsp_issue.fddx_v & mask48)) &&
					((source.fddy_v & mask48) == (last_tsp_issue.fddy_v & mask48)) &&
					((source.tile_start_u & mask48) == (last_tsp_issue.tile_start_u & mask48)) &&
					((source.tile_start_v & mask48) == (last_tsp_issue.tile_start_v & mask48));
				const bool tile_match =
					(source.tile_x == last_tsp_issue.tile_x) &&
					(source.tile_y == last_tsp_issue.tile_y);
				ImGui::Text("Param write: cycle %llu bank %u tile (%u,%u) tag 0x%03X",
					(unsigned long long)source.cycle,
					source.bank,
					source.tile_x,
					source.tile_y,
					source.tag);
				ImGui::Text("Readback coefficients %s, tile identity %s",
					coeff_match ? "MATCH" : "MISMATCH",
					tile_match ? "MATCH" : "STALE");

				auto bits_float = [](uint32_t bits) {
					float value;
					memcpy(&value, &bits, sizeof(value));
					return value;
				};
				auto show_vertex_uv = [&](const char *label, const VertexUvSnapshot &vertex) {
					ImGui::Text("%s: xy=(%+.4f,%+.4f) z=%+.6f uv=(%+.6f,%+.6f)",
						label,
						bits_float(vertex.x),
						bits_float(vertex.y),
						bits_float(vertex.z),
						bits_float(vertex.u),
						bits_float(vertex.v));
				};
				show_vertex_uv("A", source.a);
				show_vertex_uv("B", source.b);
				show_vertex_uv("C", source.c);
			}
			else {
				ImGui::Text("No matching parameter write was observed.");
			}
		}
		else {
			ImGui::Text("No nonzero tag has been issued yet.");
		}
		ImGui::End();

		ImGui::Begin("Min/Max values (per frame)");
		ImGui::Text("   x1_min: %08.6f   x1_max: %08.6f", x1_min, x1_max);
		ImGui::Text("   y1_min: %08.6f   y1_max: %08.6f", y1_min, y1_max);
		ImGui::Text("   z1_min: %08.6f   z1_max: %08.6f", z1_min, z1_max);
		ImGui::Separator();
		ImGui::Text("   x2_min: %08.6f   x2_max: %08.6f", x2_min, x2_max);
		ImGui::Text("   y2_min: %08.6f   y2_max: %08.6f", y2_min, y2_max);
		ImGui::Text("   z2_min: %08.6f   z2_max: %08.6f", z2_min, z2_max);
		ImGui::Separator();
		ImGui::Text("   x3_min: %08.6f   x3_max: %08.6f", x3_min, x3_max);
		ImGui::Text("   y3_min: %08.6f   y3_max: %08.6f", y3_min, y3_max);
		ImGui::Text("   z3_min: %08.6f   z3_max: %08.6f", z3_min, z3_max);
		ImGui::Separator();
		ImGui::Text("   x4_min: %08.6f   x4_max: %08.6f", x4_min, x4_max);
		ImGui::Text("   y4_min: %08.6f   y4_max: %08.6f", y4_min, y4_max);
		ImGui::End();

		ImGui::Begin("Bit-Width Analysis (interp Z, run to measure)");
		ImGui::Text("Signal             max_abs           bits needed (signed)");
		ImGui::Separator();
		auto bw = [](const char* name, const RangeTracker& r) {
			ImGui::Text("%-12s  %20lld   %d", name, (long long)r.max_abs, r.bits_signed());
		};
		bw("FZ",         rng_FZ);
		bw("BIG_C",      rng_BIG_C);
		bw("FDDX",       rng_FDDX);
		bw("FDDY",       rng_FDDY);
		bw("small_c",    rng_small_c);
		bw("interp_col", rng_interp_col);
		ImGui::Separator();
		ImGui::TextDisabled("Resets each frame. Run several frames to accumulate.");
		ImGui::End();

		ImGui::Begin(" Texture Pipeline");
		ImGui::Separator();
		/*
		ImGui::Text(" Stage 0 (latch) ");
		ImGui::Text("           ui_r: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_latch__DOT__ui_r);
		ImGui::Text("           vi_r: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_latch__DOT__vi_r);
		ImGui::Text("         x_ps_r: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_latch__DOT__x_ps_r);
		ImGui::Text("         y_ps_r: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_latch__DOT__y_ps_r);
		ImGui::Text("    tsp_valid_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_latch__DOT__tsp_valid_r);
		ImGui::Separator();
		*/
		ImGui::Text(" Stage A (texture address) ");
		ImGui::Text(" tex_addr_valid: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__tex_addr_valid);
		ImGui::Text("       trace_a: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__trace_a);
		ImGui::Text(" vram_word_addr: 0x%06X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__vram_word_addr);
		ImGui::Separator();
		ImGui::Text("      pix_fmt_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__pix_fmt_r);
		ImGui::Text("   shade_inst_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__shade_inst_r);
		ImGui::Text("   texture_en_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__texture_en_r);
		ImGui::Text("    offset_en_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__offset_en_r);
		ImGui::Separator();
		ImGui::Text("      vq_comp_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__vq_comp_r);
		ImGui::Text("      is_pal4_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__is_pal4_r);
		ImGui::Text("      is_pal8_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__is_pal8_r);
		ImGui::Separator();
		ImGui::Text("     pal8_sel_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__pal8_sel_r);
		ImGui::Text("      pix_sel_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__pix_sel_r);
		ImGui::Separator();
		ImGui::Text(" pal_selector_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__pal_selector_r);
		ImGui::Text("     prim_tag_r: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_addrgen__DOT__prim_tag_r);
		ImGui::Separator();
		ImGui::Text(" Stage B (u_fetch) ");
		ImGui::Text("        pix16_r: 0x%04X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__pix16_r);
		ImGui::Text("     x_ps_texel: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__x_ps_texel);
		ImGui::Text("     y_ps_texel: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__y_ps_texel);
		ImGui::Text("    texel_valid: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__texel_valid);
		ImGui::Text("       trace_b: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__trace_b);
		ImGui::Separator();
		ImGui::Text(" Stage C (u_shade) ");
		ImGui::Text("      pix_valid: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__pix_valid);
		ImGui::Text("        trace_c: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__trace_c);
		ImGui::Text("     final_argb: 0x%08X", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__final_argb);
		ImGui::Text("       x_ps_out: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__x_ps_out);
		ImGui::Text("       y_ps_out: %03d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_shade__DOT__y_ps_out);
		ImGui::End();
		
		/*
		ImGui::Begin("Tile (0,0) Left Column");
		ImGui::Text("last %u writes", tile_trace_count);
		for (uint32_t i = 0; i < tile_trace_count; ++i) {
			uint32_t idx = (tile_trace_wr + tile_trace_size - tile_trace_count + i) % tile_trace_size;
			ImGui::Text("%02u: x=%u y=%u argb=%08X", i, tile_trace_x[idx], tile_trace_y[idx], tile_trace_argb[idx]);
		}
		ImGui::End();
		*/

		/*
		ImGui::Begin("U Viewer");
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp0); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp1); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp2); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp3); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp4); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp5); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp6); ImGui::SameLine(0.0f, 2.0f);
		ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__interp_inst_u__DOT__interp7); ImGui::SameLine(0.0f, 2.0f);
		ImGui::End();
		*/

		/*
		ImGui::Begin("Float-To-Fixed");
		//for (uint8_t i = 0; i < 32; i++) {
		uint64_t fixed_shifted_z1 = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_z1__DOT__float_shifted;
		uint64_t new_fixed_z1 = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__float_z1__DOT__new_fixed;
		if (fixed_shifted_z1 > z1_highest) z1_highest = fixed_shifted_z1;
		ImGui::Text("  float_shifted z1: 0x%010llX    ", fixed_shifted_z1);
		ImGui::Text("        z1_highest: 0x%010llX    ", z1_highest);
		ImGui::Text("      new_fixed_z1: 0x%010llX    ", new_fixed_z1);
		ImGui::Text("   BACKGND_D_FIXED: 0x%008X      ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__BACKGND_D_FIXED);
		//}
		ImGui::End();
		*/

		//if (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__two_volume) run_enable = 0;

		//if (top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_0 > 0) run_enable = 0;
		ImGui::Begin("Z Viewer");
		ImGui::Text("isp_z_bank: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_z_bank); ImGui::SameLine(0.0f, 12.0f);
		ImGui::Text("tsp_z_bank: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_z_bank); ImGui::SameLine(0.0f, 12.0f);
		ImGui::Text("clear_busy: %d/%d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_clear_busy_0, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_clear_busy_1);

#define ZBUF_TAG(BANK, COL, ROW) top->__PVT__simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst_##BANK->z_mem_inst_##COL##__DOT__tag_mem[(ROW)]
#define ZBUF_Z(BANK, COL, ROW) top->__PVT__simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst_##BANK->z_mem_inst_##COL##__DOT__z_mem[(ROW)]
#define ZBUF_CASE_TAG(BANK, COL) case COL: return static_cast<uint16_t>(ZBUF_TAG(BANK, COL, row) & 0x0fff)
#define ZBUF_CASE_Z(BANK, COL) case COL: return static_cast<uint64_t>(ZBUF_Z(BANK, COL, row)) & 0x0000ffffffffffffULL

		/*
		auto z_tag_live = [&](int bank, int col, int row) -> uint16_t {
			if (bank == 0) {
				switch (col) {
					ZBUF_CASE_TAG(0, 0);
					ZBUF_CASE_TAG(0, 1);
					ZBUF_CASE_TAG(0, 2);
					ZBUF_CASE_TAG(0, 3);
					ZBUF_CASE_TAG(0, 4);
					ZBUF_CASE_TAG(0, 5);
					ZBUF_CASE_TAG(0, 6);
					ZBUF_CASE_TAG(0, 7);
					ZBUF_CASE_TAG(0, 8);
					ZBUF_CASE_TAG(0, 9);
					ZBUF_CASE_TAG(0, 10);
					ZBUF_CASE_TAG(0, 11);
					ZBUF_CASE_TAG(0, 12);
					ZBUF_CASE_TAG(0, 13);
					ZBUF_CASE_TAG(0, 14);
					ZBUF_CASE_TAG(0, 15);
					ZBUF_CASE_TAG(0, 16);
					ZBUF_CASE_TAG(0, 17);
					ZBUF_CASE_TAG(0, 18);
					ZBUF_CASE_TAG(0, 19);
					ZBUF_CASE_TAG(0, 20);
					ZBUF_CASE_TAG(0, 21);
					ZBUF_CASE_TAG(0, 22);
					ZBUF_CASE_TAG(0, 23);
					ZBUF_CASE_TAG(0, 24);
					ZBUF_CASE_TAG(0, 25);
					ZBUF_CASE_TAG(0, 26);
					ZBUF_CASE_TAG(0, 27);
					ZBUF_CASE_TAG(0, 28);
					ZBUF_CASE_TAG(0, 29);
					ZBUF_CASE_TAG(0, 30);
					ZBUF_CASE_TAG(0, 31);
				default: return 0;
				}
			}
			switch (col) {
					ZBUF_CASE_TAG(1, 0);
					ZBUF_CASE_TAG(1, 1);
					ZBUF_CASE_TAG(1, 2);
					ZBUF_CASE_TAG(1, 3);
					ZBUF_CASE_TAG(1, 4);
					ZBUF_CASE_TAG(1, 5);
					ZBUF_CASE_TAG(1, 6);
					ZBUF_CASE_TAG(1, 7);
					ZBUF_CASE_TAG(1, 8);
					ZBUF_CASE_TAG(1, 9);
					ZBUF_CASE_TAG(1, 10);
					ZBUF_CASE_TAG(1, 11);
					ZBUF_CASE_TAG(1, 12);
					ZBUF_CASE_TAG(1, 13);
					ZBUF_CASE_TAG(1, 14);
					ZBUF_CASE_TAG(1, 15);
					ZBUF_CASE_TAG(1, 16);
					ZBUF_CASE_TAG(1, 17);
					ZBUF_CASE_TAG(1, 18);
					ZBUF_CASE_TAG(1, 19);
					ZBUF_CASE_TAG(1, 20);
					ZBUF_CASE_TAG(1, 21);
					ZBUF_CASE_TAG(1, 22);
					ZBUF_CASE_TAG(1, 23);
					ZBUF_CASE_TAG(1, 24);
					ZBUF_CASE_TAG(1, 25);
					ZBUF_CASE_TAG(1, 26);
					ZBUF_CASE_TAG(1, 27);
					ZBUF_CASE_TAG(1, 28);
					ZBUF_CASE_TAG(1, 29);
					ZBUF_CASE_TAG(1, 30);
					ZBUF_CASE_TAG(1, 31);
			default: return 0;
			}
		};

		auto z_value_live = [&](int bank, int col, int row) -> uint64_t {
			if (bank == 0) {
				switch (col) {
					ZBUF_CASE_Z(0, 0);
					ZBUF_CASE_Z(0, 1);
					ZBUF_CASE_Z(0, 2);
					ZBUF_CASE_Z(0, 3);
					ZBUF_CASE_Z(0, 4);
					ZBUF_CASE_Z(0, 5);
					ZBUF_CASE_Z(0, 6);
					ZBUF_CASE_Z(0, 7);
					ZBUF_CASE_Z(0, 8);
					ZBUF_CASE_Z(0, 9);
					ZBUF_CASE_Z(0, 10);
					ZBUF_CASE_Z(0, 11);
					ZBUF_CASE_Z(0, 12);
					ZBUF_CASE_Z(0, 13);
					ZBUF_CASE_Z(0, 14);
					ZBUF_CASE_Z(0, 15);
					ZBUF_CASE_Z(0, 16);
					ZBUF_CASE_Z(0, 17);
					ZBUF_CASE_Z(0, 18);
					ZBUF_CASE_Z(0, 19);
					ZBUF_CASE_Z(0, 20);
					ZBUF_CASE_Z(0, 21);
					ZBUF_CASE_Z(0, 22);
					ZBUF_CASE_Z(0, 23);
					ZBUF_CASE_Z(0, 24);
					ZBUF_CASE_Z(0, 25);
					ZBUF_CASE_Z(0, 26);
					ZBUF_CASE_Z(0, 27);
					ZBUF_CASE_Z(0, 28);
					ZBUF_CASE_Z(0, 29);
					ZBUF_CASE_Z(0, 30);
					ZBUF_CASE_Z(0, 31);
				default: return 0;
				}
			}
			switch (col) {
					ZBUF_CASE_Z(1, 0);
					ZBUF_CASE_Z(1, 1);
					ZBUF_CASE_Z(1, 2);
					ZBUF_CASE_Z(1, 3);
					ZBUF_CASE_Z(1, 4);
					ZBUF_CASE_Z(1, 5);
					ZBUF_CASE_Z(1, 6);
					ZBUF_CASE_Z(1, 7);
					ZBUF_CASE_Z(1, 8);
					ZBUF_CASE_Z(1, 9);
					ZBUF_CASE_Z(1, 10);
					ZBUF_CASE_Z(1, 11);
					ZBUF_CASE_Z(1, 12);
					ZBUF_CASE_Z(1, 13);
					ZBUF_CASE_Z(1, 14);
					ZBUF_CASE_Z(1, 15);
					ZBUF_CASE_Z(1, 16);
					ZBUF_CASE_Z(1, 17);
					ZBUF_CASE_Z(1, 18);
					ZBUF_CASE_Z(1, 19);
					ZBUF_CASE_Z(1, 20);
					ZBUF_CASE_Z(1, 21);
					ZBUF_CASE_Z(1, 22);
					ZBUF_CASE_Z(1, 23);
					ZBUF_CASE_Z(1, 24);
					ZBUF_CASE_Z(1, 25);
					ZBUF_CASE_Z(1, 26);
					ZBUF_CASE_Z(1, 27);
					ZBUF_CASE_Z(1, 28);
					ZBUF_CASE_Z(1, 29);
					ZBUF_CASE_Z(1, 30);
					ZBUF_CASE_Z(1, 31);
			default: return 0;
			}
		};*/

		static int z_view_mode = 0;
		ImGui::RadioButton("Tag", &z_view_mode, 0); ImGui::SameLine();
		ImGui::RadioButton("Z hi", &z_view_mode, 1); ImGui::SameLine();
		ImGui::RadioButton("Z lo", &z_view_mode, 2);

		static int z_view_bank = 0;
		ImGui::RadioButton("Bank 0", &z_view_bank, 0); ImGui::SameLine();
		ImGui::RadioButton("Bank 1", &z_view_bank, 1);
		static bool z_view_live = false;
		ImGui::Checkbox("Live RAM", &z_view_live);

		/*
		auto z_tag = [&](int bank, int col, int row) -> uint16_t {
			if (!z_view_live && z_view_snapshot_valid[bank]) return z_view_tag_snapshot[bank][row][col];
			return z_tag_live(bank, col, row);
		};

		auto z_value = [&](int bank, int col, int row) -> uint64_t {
			if (!z_view_live && z_view_snapshot_valid[bank]) return z_view_z_snapshot[bank][row][col];
			return z_value_live(bank, col, row);
		};
		*/

		/*
		int bank_nonzero_tags[2] = {0, 0};
		int bank_nonzero_z[2] = {0, 0};
		for (int summary_bank = 0; summary_bank < 2; summary_bank++) {
			for (int row = 0; row < 32; row++) {
				for (int col = 0; col < 32; col++) {
					if (z_tag(summary_bank, col, row) != 0) bank_nonzero_tags[summary_bank]++;
					if (z_value(summary_bank, col, row) != 0) bank_nonzero_z[summary_bank]++;
				}
			}
		}
		ImGui::Text("nonzero cells: bank0 tag=%d z=%d, bank1 tag=%d z=%d",
			bank_nonzero_tags[0], bank_nonzero_z[0], bank_nonzero_tags[1], bank_nonzero_z[1]);

		const int bank = z_view_bank ? 1 : 0;
		ImGui::Text("Z bank %d (%s%s)", bank, z_view_live ? "live" : "write snapshot",
			(!z_view_live && !z_view_snapshot_valid[bank]) ? ", no snapshot yet" : "");
		ImGui::Text("grid shows selected field; hover a cell for full Tag/Z");
		for (int row = 0; row < 32; row++) {
			for (int col = 0; col < 32; col++) {
				const uint16_t tag = z_tag(bank, col, row);
				const uint64_t z = z_value(bank, col, row);
				if (z_view_mode == 1) {
					ImGui::Text("%03X", (unsigned int)((z >> 36) & 0x0fff));
				}
				else if (z_view_mode == 2) {
					ImGui::Text("%03X", (unsigned int)(z & 0x0fff));
				}
				else {
					ImGui::Text("%03X", tag);
				}
				if (ImGui::IsItemHovered()) {
					ImGui::SetTooltip("bank=%d x=%02d y=%02d tag=%03X z=%012llX", bank, col, row, tag, (unsigned long long)z);
				}
				if (col < 31) ImGui::SameLine(0.0f, 2.0f);
			}
		}

#undef ZBUF_TAG
#undef ZBUF_Z
#undef ZBUF_CASE_TAG
#undef ZBUF_CASE_Z
*/
		ImGui::End();

		ImGui::Begin("ISP Cache Viewer");
		ImGui::Text("  isp_ddram_dout_ready: %d", top->DDRAM_DOUT_READY);
		ImGui::Text(" isp_ddram_addr (word): %08X", top->DDRAM_ADDR);
		ImGui::Text(" isp_ddram_addr (byte): %08X", top->DDRAM_ADDR <<3);
		ImGui::Text("        isp_ddram_dout: %08X%08X", top->DDRAM_DOUT>>32, top->DDRAM_DOUT);
		ImGui::Separator();
		ImGui::Text("RA+ISP now share one uncached DDR lane (arbiter step 1).");
		ImGui::End();

		ImGui::Begin("RA Cache Stats");
		ImGui::Text("  ra_vram_rd_count: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_vram_rd_count);
		ImGui::Text("   arb_req_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_req_count);
		ImGui::Text("  arb_resp_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_resp_count);
		ImGui::Text("  arb_drop_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_drop_count);
		ImGui::Text("     arb_pending: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_pend_valid);
		ImGui::Text("    cache hits: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_cache_hit_count);
		ImGui::Text("  cache misses: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_cache_miss_count);
		ImGui::Text("       refills: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__a_refill_count);
		ImGui::End();

		ImGui::Begin("ISP Cache Stats");
		ImGui::Text(" isp_vram_rd_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_vram_rd_count);
		ImGui::Text("   arb_req_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_req_count);
		ImGui::Text("  arb_resp_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_resp_count);
		ImGui::Text("  arb_drop_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_drop_count);
		ImGui::Text("     arb_pending: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_pend_valid);
		ImGui::Text("    cache hits: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_cache_hit_count);
		ImGui::Text("  cache misses: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_cache_miss_count);
		ImGui::Text("       refills: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__b_refill_count);
		ImGui::Separator();
		ImGui::Text("param win hits: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__param_window_hit_count);
		ImGui::Text("param win misses: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__param_window_miss_count);
		ImGui::Text("param prefetch: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__param_window_prefetch_count);
		ImGui::Text("param fills: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__param_window_fill_count);
		ImGui::Text("param overlap starts: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__param_window_overlap_start_count);
		ImGui::Text("ra pfetch rdy !at11: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_prefetch_ready_not_at_11);
		ImGui::Text(" ra pfetch rdy at11: %d", top->rootp->simtop__DOT__pvr__DOT__ra_parser_inst__DOT__ra_prefetch_ready_at_11);
		ImGui::Text("    isp st56 cycles: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state56_cycles);
		ImGui::Text("    isp st57 cycles: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__isp_state57_cycles);
		ImGui::Text("        tile count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_count);
		ImGui::Separator();
		ImGui::Text("ddr_issue_count: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__ddr_issue_count);
		ImGui::Text("     inflight: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__inflight);
		ImGui::Text("inflight_owner: %d", top->rootp->simtop__DOT__vram_read_arbiter_geo__DOT__inflight_owner);
		ImGui::Separator();
		const uint64_t classified_cycles = bottleneck_cycles + no_bottleneck_cycles;
		const double stat_total = (classified_cycles > 0) ? (double)classified_cycles : 1.0;
		ImGui::Text("   bottleneck: %llu (%.1f%%)", (unsigned long long)bottleneck_cycles, 100.0 * (double)bottleneck_cycles / stat_total);
		ImGui::Text("no bottleneck: %llu (%.1f%%)", (unsigned long long)no_bottleneck_cycles, 100.0 * (double)no_bottleneck_cycles / stat_total);
		ImGui::Text("     overlap: %llu (%.1f%%)", (unsigned long long)overlap_cycles, 100.0 * (double)overlap_cycles / stat_total);
		ImGui::Text("    ISP only: %llu (%.1f%%)", (unsigned long long)isp_only_cycles, 100.0 * (double)isp_only_cycles / stat_total);
		ImGui::Text("    TSP only: %llu (%.1f%%)", (unsigned long long)tsp_only_cycles, 100.0 * (double)tsp_only_cycles / stat_total);
		ImGui::Separator();
		ImGui::Text("ISP wait TSP: %llu", (unsigned long long)isp_wait_tsp_cycles);
		ImGui::Text("TSP wait tex: %llu", (unsigned long long)tsp_wait_tex_cycles);
		ImGui::Text(" TSP codebk: %llu", (unsigned long long)tsp_wait_cb_cycles);
		ImGui::Text(" bank clear: %llu", (unsigned long long)bank_clear_wait_cycles);
		ImGui::Separator();
		ImGui::Text("tsp wait starts: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_wait_start_count);
		ImGui::Text("tsp wait cycles: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_wait_cycle_count);
		ImGui::Text("tsp wait next: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_wait_next_count);
		ImGui::Text("tsp wait >1: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_wait_long_count);
		ImGui::Text("tsp init skips: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_initial_skip_count);
		ImGui::Text("tex cache hit skips: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_tex_cache_hit_skip_count);
		ImGui::Text("empty tile skips: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tsp_empty_tile_skip_count);
		ImGui::Separator();
		ImGui::Text("tag pixels: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_visible_pixel_count);
		ImGui::Text("tag switches: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_switch_count);
		ImGui::Text("tag settle stalls: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_switch_stall_count);
		ImGui::Text("same-tag pixels: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__same_tag_pixel_count);
		ImGui::Text("tag runs: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_count);
		ImGui::Text("run len 1: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_len_1_count);
		ImGui::Text("run len 2-3: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_len_2_3_count);
		ImGui::Text("run len 4-7: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_len_4_7_count);
		ImGui::Text("run len 8-15: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_len_8_15_count);
		ImGui::Text("run len 16+: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_run_len_16p_count);
		ImGui::Text("tag switches textured: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_switch_textured_count);
		ImGui::Text("tag tex-base changes: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_switch_tex_base_change_count);
		ImGui::Text("tag codebk changes: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_switch_codebook_base_change_count);
		ImGui::End();

		ImGui::Begin("Tex Cache Stats");
		ImGui::Text("      hit_count: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__hit_count);
		ImGui::Text("     line hits: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__line_hit_count);
		ImGui::Text("      hot hits: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__hot_hit_count);
		ImGui::Text("    hot evicts: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__hot_evict_count);
		ImGui::Text("     miss_count: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__miss_count);
		ImGui::Text(" prefetch starts: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__prefetch_start_count);
		ImGui::Text("  prefetch fills: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__prefetch_fill_count);
		ImGui::Text("   prefetch hits: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__prefetch_hit_count);
		ImGui::Text(" hit-under-miss: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__hit_under_miss_count);
		ImGui::Text(" tex_vram_rd_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tex_vram_rd_count);
		ImGui::Text("     cb_word_count: %d", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__cb_word_count);
		ImGui::Separator();
		ImGui::Text("    cb_base_hits: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_base_hit_count);
		ImGui::Text("  cb_base_misses: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_base_miss_count);
		ImGui::Text("    cb_fill_count: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_fill_count);
		ImGui::Text("   cb_evict_count: %d", top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_evict_count);
		ImGui::Text(" cb_slot_hits 0/1: %d / %d",
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot0_hit_count,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot1_hit_count);
		ImGui::Text(" cb_slot_hits 2/3: %d / %d",
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot2_hit_count,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot3_hit_count);
		ImGui::Text(" cb_slot_hits 4/5: %d / %d",
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot4_hit_count,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot5_hit_count);
		ImGui::Text(" cb_slot_hits 6/7: %d / %d",
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot6_hit_count,
			top->rootp->simtop__DOT__pvr__DOT__tsp_top__DOT__texture_address_inst__DOT__u_fetch__DOT__u_codebook_cache__DOT__cb_slot7_hit_count);
		ImGui::Separator();
		ImGui::Text("        delta_0: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_0);
		ImGui::Text("        delta_1: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_1);
		ImGui::Text("      delta_2_3: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_2_3);
		ImGui::Text("      delta_4_7: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_4_7);
		ImGui::Text("     delta_8_15: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_8_15);
		ImGui::Text("      delta_16p: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__delta_16p);
		ImGui::Text(" last_word_addr: %d", top->rootp->simtop__DOT__vram_read_cache_tex__DOT__last_word_addr);
		ImGui::End();
				
		/*
		ImGui::Begin("Prim-Tag Viewer");
		uint32_t inTri = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__hsr_core_inst__DOT__inTri;
		uint32_t depth_allow = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__depth_allow;
		uint32_t z_allow = inTri & depth_allow;
		for (uint8_t i = 0; i < 32; i++) {
			bool row_active = (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__y_ps&0x1f) == i;
			if (row_active) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 0, 0, 255));	// RGBA.
			if (row_active && (z_allow & 0x00000001)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_0__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000001)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000002)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_1__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000002)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000004)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_2__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000004)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000008)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_3__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000008)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000010)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_4__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000010)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000020)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_5__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000020)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000040)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_6__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000040)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000080)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_7__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000080)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000100)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_8__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000100)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000200)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_9__DOT__tag_mem[i] )&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000200)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000400)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_10__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000400)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00000800)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_11__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00000800)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00001000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_12__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00001000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00002000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_13__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00002000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00004000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_14__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00004000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00008000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_15__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00008000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00010000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_16__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00010000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00020000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_17__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00020000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00040000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_18__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00040000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00080000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_19__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00080000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00100000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_20__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00100000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00200000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_21__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00200000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00400000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_22__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00400000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x00800000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_23__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x00800000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x01000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_24__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x01000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x02000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_25__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x02000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x04000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_26__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x04000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x08000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_27__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x08000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x10000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_28__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x10000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x20000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_29__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x20000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x40000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_30__DOT__tag_mem[i])&0xff ); ImGui::SameLine(0.0f, 2.0f); if (row_active && (z_allow & 0x40000000)) ImGui::PopStyleColor();
			if (row_active && (z_allow & 0x80000000)) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(0, 255, 0, 255)); ImGui::Text("%02X", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_buff_inst__DOT__z_mem_inst_31__DOT__tag_mem[i])&0xff ); if (row_active && (z_allow & 0x80000000)) ImGui::PopStyleColor();
			if (row_active) ImGui::PopStyleColor();
		}
		ImGui::End();
		*/
	
		/*
		ImGui::Begin("Tile ARGB Buffer viewer");
		for (uint8_t i = 0; i < 31; i++) {
			//ImGui::Text("%06X ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_argb_buffer_inst__DOT__buff[i]&0xffffff); ImGui::SameLine(0.0f, 1.0f);
			uint32_t argb = top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tile_argb_buffer_inst__DOT__buff[i];
			ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(argb>>16, argb>>8, argb>>0, 255)); ImGui::Text("H"); ImGui::SameLine(0.0f, 1.0f);
			ImGui::PopStyleColor();
		}
		ImGui::End();
		*/

		/*
		ImGui::Begin("CB Cache Viewer. Row 0");
		//for (uint8_t i = 0; i < 31; i++) {
			ImGui::Text("%010X ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__texture_address_inst__DOT__codebook_cache_inst__DOT__cache_valid); //ImGui::SameLine(0.0f, 1.0f);
		//}
		ImGui::End();
		*/

		/*
		ImGui::Begin("Tag-Stack Viewer. Row 0");
		ImGui::Text("Index:   %0d ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_stack_index[0]);
		for (uint8_t i = 0; i < 31; i++) {
			ImGui::Text("Tag:   %03X ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_stack[0][i]); ImGui::SameLine(0.0f, 1.0f);
			ImGui::Text("inTri: %08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_stack[0][i] );
		}
		ImGui::End();

		ImGui::Begin("Tag-Stack Viewer. Row 1");
		ImGui::Text("Index:   %0d ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_stack_index[1]);
		for (uint8_t i = 0; i < 31; i++) {
			ImGui::Text("Tag:   %03X ", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__prim_stack[1][i]); ImGui::SameLine(0.0f, 1.0f);
			ImGui::Text("inTri: %08X",  top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__tag_stack[1][i]);
		}
		ImGui::End();
		*/

		/*
		ImGui::Begin("Parameter Cache Viewer");
		//ImGui::Text(" pcache_rd_addr: %08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_rd_addr);
		for (uint8_t i = 0; i < 8; i++) {
			//ImGui::Text("%08X", top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_dout[i]>>(32*20)); //ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("FX1[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_a_x[i]); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("FY1[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_a_y[i]); ImGui::SameLine(0.0f, 2.0f);
			
			ImGui::Text("FX2[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_b_x[i]); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("FY2[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_b_y[i]); ImGui::SameLine(0.0f, 2.0f);
			
			ImGui::Text("FX3[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_c_x[i]); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("FY3[%d]: %08X ", i, top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__pcache_vert_c_y[i]);
		}
		ImGui::End();
		*/

		/*
		ImGui::Begin("span_last_pixel Viewer");
		for (uint8_t i = 0; i < 32; i++) {
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_0[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_1[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_2[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_3[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_4[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_5[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_6[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_7[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_8[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_9[i]  >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_10[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_11[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_12[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_13[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_14[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_15[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_16[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_17[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_18[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_19[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_20[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_21[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_22[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_23[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_24[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_25[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_26[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_27[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_28[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_29[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_30[i] >> 40) & 0x1f); ImGui::SameLine(0.0f, 2.0f);
			ImGui::Text("%02d", (top->rootp->simtop__DOT__pvr__DOT__isp_parser_inst__DOT__z_col_31[i] >> 40) & 0x1f); //ImGui::SameLine(0.0f, 2.0f);
		}
		ImGui::End();
		*/

		if (dump_to_raw) {
			dump_to_raw = 0;
			BMP *bmp = new BMP;
			bmp->SetBitDepth(24);
			bmp->SetSize(640,480);
			char my_string [20];
			sprintf(my_string, "frame%d.bmp", dump_cnt);
			for (int y=0; y<480; y++) {
				for (int x=0; x<640; x++) {
					uint32_t addr = x + (y * 640);
					RGBApixel pixel;
					pixel.Alpha = 0xff;
					pixel.Red   = disp_ptr[addr] >> 0;
					pixel.Green = disp_ptr[addr] >> 8;
					pixel.Blue  = disp_ptr[addr] >> 16;
					bmp->SetPixel(x, y, pixel);
				}
			}
			bmp->WriteToFile(my_string);
		}

		// Update the texture for disp_ptr!
		// D3D11_USAGE_DEFAULT MUST be set in the texture description (somewhere above) for this to work.
		// (D3D11_USAGE_DYNAMIC is for use with map / unmap.) ElectronAsh.
		g_pd3dDeviceContext->UpdateSubresource(p_disp_tex, 0, NULL, disp_ptr, disp_tex_width*4, 0);
		g_pd3dDeviceContext->UpdateSubresource(p_tile_tex, 0, NULL, tile_ptr, tile_tex_width*4, 0);

		// Rendering
		ImGui::Render();
		g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, NULL);
		g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, (float*)&clear_color);
		ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

		g_pSwapChain->Present(1, 0); // Present with vsync
		//g_pSwapChain->Present(0, 0); // Present without vsync

		if (run_enable) for (int step = 0; step < 16384; step++) {	// Simulates MUCH faster if it's done in batches.
			bool key_f6 = ImGui::IsKeyPressed(ImGuiKey_F6);
			bool key_f11 = ImGui::IsKeyPressed(ImGuiKey_F11);
			if (key_f6 || key_f11) run_enable = 0;
			if (run_enable) verilate(); else break;
		}
		else {														// But, that will affect the GUI update rate / value fetch.
			bool key_f5 = ImGui::IsKeyPressed(ImGuiKey_F5);
			if (key_f5) run_enable = 1;

			bool key_f6 = ImGui::IsKeyPressed(ImGuiKey_F6);
			bool key_f11 = ImGui::IsKeyPressed(ImGuiKey_F11);
			if (key_f6 || key_f11) run_enable = 0;

			if (single_step || key_f11) verilate();
			if (multi_step || key_f6) for (int step = 0; step < multi_step_amount; step++) verilate();
		}
	}
	// Close imgui stuff properly...
	ImGui_ImplDX11_Shutdown();
	ImGui_ImplWin32_Shutdown();
	ImGui::DestroyContext();

	CleanupDeviceD3D();
	DestroyWindow(hwnd);
	UnregisterClass(wc.lpszClassName, wc.hInstance);

	return 0;
}
