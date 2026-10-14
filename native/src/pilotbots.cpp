// pilotbots.dll - native side of Pilot Bots, loaded next to the official R1Delta tier0.dll.
//
// The installer adds this DLL to tier0.dll's import table, so Windows loads it before tier0's own
// DllMain runs. Nothing here links against R1Delta: everything goes straight to the game binaries
// (launcher.dll hosts vscript, plus server.dll and engine.dll), which never change. Port of
// R1Delta's server/ai/bot_control.cpp, CreateDummyBot, the bot branch of PlayerMoveRunCommand
// and the CL_CopyExistingEntity guard.
//
// Listen server / client only: in the dedicated server (no launcher.dll) the DLL does nothing.
//
// Hook order matters where R1Delta hooks the same function:
// - launcher CreateNewVM: ours must be the INNER hook (R1Delta's returns a fake server VM), so it
//   is installed when engine.dll loads, before R1Delta's hook at server.dll load.
// - server PlayerMoveRunCommand: R1Delta skips all its usercmd hooks if the prologue was changed,
//   so ours must be the OUTER hook, installed after R1Delta's (see InstallLateHooks).

#include <windows.h>
#include <winternl.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <functional>
#include <queue>
#include <vector>
#include "MinHook.h"

#define PILOTBOTS_VERSION "2.1.1"

//=============================================================================
// Log: pilotbots.log next to this DLL (r1delta\bin_delta). The launcher starts the game with the
// Titanfall install as working directory, so relative paths don't point at the R1Delta folder.
//=============================================================================
static char g_logPath[MAX_PATH];

static void InitLogPath(HMODULE module)
{
	DWORD n = GetModuleFileNameA(module, g_logPath, MAX_PATH);
	char* slash = n ? strrchr(g_logPath, '\\') : nullptr;
	if (slash && (size_t)(slash - g_logPath) + sizeof("\\pilotbots.log") <= MAX_PATH)
		strcpy_s(slash, MAX_PATH - (slash - g_logPath), "\\pilotbots.log");
	else
		strcpy_s(g_logPath, "pilotbots.log");
}

static void Log(const char* fmt, ...)
{
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	FILE* f = nullptr;
	if (fopen_s(&f, g_logPath, "a") == 0 && f) {
		SYSTEMTIME t;
		GetLocalTime(&t);
		fprintf(f, "[%02d:%02d:%02d] %s\n", t.wHour, t.wMinute, t.wSecond, buf);
		fclose(f);
	}
}

//=============================================================================
// Game binaries
//=============================================================================
static uintptr_t g_launcher;
static uintptr_t g_engine;
static uintptr_t g_server;

static bool Matches(uintptr_t addr, const unsigned char* sig, size_t len)
{
	return memcmp(reinterpret_cast<const void*>(addr), sig, len) == 0;
}

static bool IsJmp(uintptr_t addr)
{
	return *reinterpret_cast<const unsigned char*>(addr) == 0xE9;
}

// launcher.dll (vscript)
static const uintptr_t kCreateNewVM = 0x1210;
static const uintptr_t kAddSquirrelReg = 0x8E50;
static const uintptr_t kSqGetString = 0x16880;
static const uintptr_t kSqGetInteger = 0xE740;
static const uintptr_t kSqGetFloat = 0xE6F0;
static const uintptr_t kSqGetStackObj = 0xE7F0;
static const uintptr_t kSqPushString = 0x14C30;
static const uintptr_t kSqPushInteger = 0xEA10;
static const uintptr_t kSqPushFloat = 0xE9B0;
static const uintptr_t kSqNewArray = 0x14FB0;
static const uintptr_t kSqArrayAppend = 0x152A0;
static const uintptr_t kSqThrowError = 0x18930;
static const uintptr_t kServerPrint = 0xB640;		// server VM print function (R1Delta replaces it)

// server.dll
static const uintptr_t kGpGlobals = 0xC310C0;		// CServerGameDLL::DLLInit stores pGlobals here
static const uintptr_t kPlayerMoveRunCommand = 0x514F00;
static const uintptr_t kChangeTeam = 0x554660;		// CPortal_Player::ChangeTeam
static const uintptr_t kClientFullyConnected = 0x1499E0;
static const uintptr_t kEntityConstant = 0xD42040;	// CBaseEntity script class, for entity args
static const uintptr_t kAINetworkManager = 0xC31898;
static const uintptr_t kClampPlayerFrameTimeParent = 0xB5A980;
static const uintptr_t kClampFrameTimeBase = 0xC310F8;
static const uintptr_t kClampFrameTimeOffset = 0xC31100;

// engine.dll
static const uintptr_t kCLCopyExistingEntity = 0x536F0;
static const uintptr_t kHostError = 0x130510;
static const uintptr_t kConVarCtor = 0x481AF0;

// Original first bytes (a hook by R1Delta replaces them with a JMP, which is accepted too).
static const unsigned char kSigCreateNewVM[] = { 0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x83, 0xEC, 0x30 };
static const unsigned char kSigAddSquirrelReg[] = { 0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83, 0xEC, 0x20 };
static const unsigned char kSigSqPushString[] = { 0x40, 0x56, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xF1 };
static const unsigned char kSigSqPushFloat[] = { 0x48, 0x83, 0xEC, 0x38, 0x8B, 0x4A, 0x50 };
static const unsigned char kSigRunCommand[] = { 0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x48, 0x89, 0x70, 0x10, 0x48 };
static const unsigned char kSigChangeTeam[] = { 0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x6C, 0x24, 0x18, 0x57, 0x48 };
static const unsigned char kSigClientFullyConnected[] = { 0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0xF6, 0x02, 0x04 };
static const unsigned char kSigCLCopyExistingEntity[] = { 0x40, 0x53, 0x55, 0x57, 0x41, 0x55, 0x41, 0x56, 0x48, 0x83, 0xEC, 0x70 };
static const unsigned char kSigHostError[] = { 0x48, 0x89, 0x4C, 0x24, 0x08, 0x48, 0x89, 0x54, 0x24, 0x10 };
static const unsigned char kSigConVarCtor[] = { 0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x6C, 0x24, 0x10 };
static const unsigned char kSigServerPrint[] = { 0x48, 0x8B, 0xC4, 0x48, 0x89, 0x50, 0x10, 0x4C, 0x89, 0x40, 0x18 };

#define SIG_OK(base, off, sig) Matches((base) + (off), sig, sizeof(sig))
#define SIG_OR_JMP(base, off, sig) (SIG_OK(base, off, sig) || IsJmp((base) + (off)))

//=============================================================================
// Squirrel API (launcher.dll). The R1SquirrelVM* first argument of some calls is unused.
//=============================================================================
typedef long SQInteger;
typedef SQInteger SQRESULT;
typedef float SQFloat;
typedef struct SQVM* HSQUIRRELVM;
typedef SQInteger (*SQFUNCTION)(HSQUIRRELVM);
#define SQ_FAILED(r) ((r) < 0)

struct SQObject {
	unsigned int type;
	unsigned int pad;
	void* value;
};

static SQRESULT (*sq_getstring)(HSQUIRRELVM, SQInteger, const char**);
static SQRESULT (*sq_getinteger)(void*, HSQUIRRELVM, SQInteger, SQInteger*);
static SQRESULT (*sq_getfloat)(void*, HSQUIRRELVM, SQInteger, SQFloat*);
static SQRESULT (*sq_getstackobj)(void*, HSQUIRRELVM, SQInteger, SQObject*);
static void (*sq_pushstring)(HSQUIRRELVM, const char*, SQInteger);
static void (*sq_pushinteger)(void*, HSQUIRRELVM, SQInteger);
static void (*sq_pushfloat)(void*, HSQUIRRELVM, SQFloat);
static void (*sq_newarray)(HSQUIRRELVM, SQInteger);
static SQRESULT (*sq_arrayappend)(HSQUIRRELVM, SQInteger);
static SQRESULT (*sq_throwerror)(HSQUIRRELVM, const char*);

// Same layout R1Delta uses (squirrel.h, SQFuncRegistrationInternal).
struct SQFuncReg {
	const char* squirrelFuncName;
	const char* cppFuncName;
	const char* helpText;
	const char* szTypeMask;
	__int64 nparamscheck;
	const char* returnValueTypeText;
	const char* argNamesText;
	__int64 unk32;
	char pad[0x20];
	void* pfnBinding;
	void* pFunction;
	__int64 flags;
};
static_assert(sizeof(SQFuncReg) == 0x78, "SQFuncReg layout");

typedef __int64 (*AddSquirrelReg_t)(void* vm, SQFuncReg* reg);
static AddSquirrelReg_t g_addSquirrelReg;

static __int64 __fastcall SQFuncBindingFn(__int64(__fastcall* a1)(const char*), __int64, const char** a3, __int64, __int64 a5)
{
	static const char* empty = "";
	__int64 result = a1(*a3 ? *a3 : empty);
	*(unsigned short*)(a5 + 8) = 32;
	*(__int64*)a5 = result;
	return result;
}

// Entity argument: same as R1Delta's CSquirrelVM__GetEntityFromInstance_Rebuild.
static void* GetEntityArg(HSQUIRRELVM v, SQInteger index)
{
	SQObject obj = {};
	if (SQ_FAILED(sq_getstackobj(nullptr, v, index, &obj)))
		return nullptr;
	if (obj.type != 0xA008000 || !obj.value)	// OT_INSTANCE
		return nullptr;
	const uintptr_t inst = reinterpret_cast<uintptr_t>(obj.value);
	const uintptr_t ctx = *reinterpret_cast<uintptr_t*>(inst + 64);
	if (!ctx)
		return nullptr;
	const uintptr_t wanted = g_server + kEntityConstant;
	const uintptr_t cls = *reinterpret_cast<uintptr_t*>(*reinterpret_cast<uintptr_t*>(inst + 56) + 128);
	if (cls != wanted) {
		if (cls < 2)
			return nullptr;
		uintptr_t base = *reinterpret_cast<uintptr_t*>(cls + 24);
		while (base && base != wanted)
			base = *reinterpret_cast<uintptr_t*>(base + 24);
		if (!base)
			return nullptr;
	}
	return *reinterpret_cast<void**>(ctx);
}

static bool GetFloatArg(HSQUIRRELVM v, SQInteger index, float& out)
{
	SQFloat value = 0.0f;
	if (SQ_FAILED(sq_getfloat(nullptr, v, index, &value)))
		return false;
	out = value;
	return true;
}

static bool GetIntArg(HSQUIRRELVM v, SQInteger index, int& out)
{
	SQInteger value = 0;
	if (SQ_FAILED(sq_getinteger(nullptr, v, index, &value)))
		return false;
	out = static_cast<int>(value);
	return true;
}

static void PushFloatArray(HSQUIRRELVM v, const std::vector<float>& values)
{
	sq_newarray(v, 0);
	for (float value : values) {
		sq_pushfloat(nullptr, v, value);
		sq_arrayappend(v, -2);
	}
}

//=============================================================================
// Server globals and players
//=============================================================================
struct CGlobalVars {
	char pad0[0x28];
	float interval_per_tick;	// 0x28
	char pad1[0x78 - 0x2C];
	void* pEdicts;				// 0x78
};

static CGlobalVars* Globals()
{
	return g_server ? *reinterpret_cast<CGlobalVars**>(g_server + kGpGlobals) : nullptr;
}

constexpr int kMaxBotSlots = 128;
constexpr size_t kPlayerEdictOffset = 64;
constexpr size_t kEdictSize = 56;
constexpr size_t kPlayerFlagsOffset = 0x168;
constexpr unsigned int kFlAtControls = 0x40;
constexpr unsigned int kFlFakeClient = 0x100;
constexpr size_t kPlayerAccumulatedFrameTime = 7036;
constexpr size_t kPlayerFrameTimeReference = 7040;
constexpr size_t kPlayerPaused = 7052;

static int GetPlayerSlot(uintptr_t player)
{
	CGlobalVars* globals = Globals();
	if (!player || !globals || !globals->pEdicts)
		return -1;
	const __int64 edict = *reinterpret_cast<__int64*>(player + kPlayerEdictOffset);
	const __int64 index = (edict - reinterpret_cast<__int64>(globals->pEdicts)) / static_cast<__int64>(kEdictSize);
	if (index < 0 || index >= kMaxBotSlots)
		return -1;
	return static_cast<int>(index);
}

static bool IsFakeClient(uintptr_t player)
{
	return (*reinterpret_cast<unsigned int*>(player + kPlayerFlagsOffset) & kFlFakeClient) != 0;
}

//=============================================================================
// Bot input (BotSetInput/BotPressButtons -> written into the bot's usercmd)
//=============================================================================
namespace BotUserCmd {
	constexpr size_t kWorldViewAngles = 0x0C;
	constexpr size_t kLocalViewAngles = 0x1C;
	constexpr size_t kForwardMove = 52;
	constexpr size_t kSideMove = 56;
	constexpr size_t kUpMove = 60;
	constexpr size_t kButtons = 64;
	constexpr size_t kFrameTime = 160;
}

namespace BotButtons {
	constexpr int kForward = 0x8;
	constexpr int kBack = 0x10;
	constexpr int kMoveLeft = 0x200;
	constexpr int kMoveRight = 0x400;
}

struct BotInput {
	float forward = 0.0f;
	float side = 0.0f;
	float up = 0.0f;
	float pitch = 0.0f;
	float yaw = 0.0f;
	int heldButtons = 0;
	int pulseButtons = 0;	// applied to exactly one usercmd, so jump/melee get a fresh press edge
	bool active = false;
};

struct BotCmdStats {
	unsigned int seen = 0;
	unsigned int applied = 0;
	float lastForward = 0.0f;
	int lastButtons = 0;
	float lastFrameTime = 0.0f;
	float effFrameTimeBefore = 0.0f;
	float effFrameTime = 0.0f;
	unsigned int clampFixes = 0;
	unsigned int playerFlags = 0;
	int paused = 0;
	float accumulated = 0.0f;
	float reference = 0.0f;
};

static BotInput s_botInputs[kMaxBotSlots];
static BotCmdStats s_botCmdStats[kMaxBotSlots];

static BotInput* GetBotInputArg(HSQUIRRELVM v)
{
	const int slot = GetPlayerSlot(reinterpret_cast<uintptr_t>(GetEntityArg(v, 2)));
	return slot < 0 ? nullptr : &s_botInputs[slot];
}

static void WriteVector(uintptr_t address, float x, float y, float z)
{
	auto* vec = reinterpret_cast<float*>(address);
	vec[0] = x;
	vec[1] = y;
	vec[2] = z;
}

static void ApplyToUserCmd(uintptr_t player, uintptr_t userCmd)
{
	const int slot = GetPlayerSlot(player);
	if (slot < 0)
		return;

	BotCmdStats& stats = s_botCmdStats[slot];
	++stats.seen;
	stats.lastFrameTime = *reinterpret_cast<const float*>(userCmd + BotUserCmd::kFrameTime);

	BotInput& input = s_botInputs[slot];
	if (!input.active)
		return;
	++stats.applied;

	// Bots are left with FL_ATCONTROLS after the match intro (humans get it cleared per player),
	// and CPlayerMove::SetupMove drops forward/side/up while it is set.
	*reinterpret_cast<unsigned int*>(player + kPlayerFlagsOffset) &= ~kFlAtControls;
	stats.lastForward = input.forward;

	int buttons = input.heldButtons | input.pulseButtons;
	input.pulseButtons = 0;
	if (input.forward > 0.0f)
		buttons |= BotButtons::kForward;
	else if (input.forward < 0.0f)
		buttons |= BotButtons::kBack;
	if (input.side > 0.0f)
		buttons |= BotButtons::kMoveRight;
	else if (input.side < 0.0f)
		buttons |= BotButtons::kMoveLeft;

	WriteVector(userCmd + BotUserCmd::kWorldViewAngles, input.pitch, input.yaw, 0.0f);
	WriteVector(userCmd + BotUserCmd::kLocalViewAngles, input.pitch, input.yaw, 0.0f);
	*reinterpret_cast<float*>(userCmd + BotUserCmd::kForwardMove) = input.forward;
	*reinterpret_cast<float*>(userCmd + BotUserCmd::kSideMove) = input.side;
	*reinterpret_cast<float*>(userCmd + BotUserCmd::kUpMove) = input.up;
	*reinterpret_cast<int*>(userCmd + BotUserCmd::kButtons) = buttons;
	stats.lastButtons = buttons;
}

// Movement frame time retail RunCommand will use for a non-paused player (0 = the command can't
// move). Same as R1Delta's GetEffectiveUserCmdFrameTime without the paused/noclip branch.
static float EffectiveFrameTime(uintptr_t player, uintptr_t userCmd, float intervalPerTick)
{
	float frameTime = intervalPerTick;
	const float commandFrameTime = *reinterpret_cast<float*>(userCmd + BotUserCmd::kFrameTime);
	if (commandFrameTime != 0.0f)
		frameTime = commandFrameTime;

	const uintptr_t clampParent = *reinterpret_cast<uintptr_t*>(g_server + kClampPlayerFrameTimeParent);
	if (clampParent && *reinterpret_cast<int*>(clampParent + 0x64) != 0) {
		const float baseTime = *reinterpret_cast<float*>(g_server + kClampFrameTimeBase);
		float slack = (baseTime - *reinterpret_cast<float*>(player + kPlayerFrameTimeReference)) * 0.016669999808073044f;
		slack = std::fmin(std::fmax(slack, 3.0f), 10.0f);
		const float limit = *reinterpret_cast<float*>(g_server + kClampFrameTimeOffset) + baseTime + slack;
		const float accumulated = *reinterpret_cast<float*>(player + kPlayerAccumulatedFrameTime);
		if (!(limit >= accumulated))
			frameTime = 0.0f;
	}
	return frameTime;
}

typedef __int64 (__fastcall* RunCommand_t)(uintptr_t, uintptr_t, uintptr_t, uintptr_t);
static RunCommand_t g_runCommandOriginal;

static __int64 __fastcall Hook_PlayerMoveRunCommand(uintptr_t playerMove, uintptr_t player, uintptr_t userCmd, uintptr_t moveHelper)
{
	CGlobalVars* globals = Globals();
	if (!player || !userCmd || !globals || !IsFakeClient(player))
		return g_runCommandOriginal(playerMove, player, userCmd, moveHelper);

	ApplyToUserCmd(player, userCmd);

	// Bots get their commands from the server itself, so their accumulated command time can run
	// ahead of the frame time clamp's clock and every command ends up with zero movement time.
	// Pull it back to the clamp clock so the command moves.
	const bool paused = *reinterpret_cast<unsigned char*>(player + kPlayerPaused) != 0;
	const float before = paused ? 0.0f : EffectiveFrameTime(player, userCmd, globals->interval_per_tick);
	float after = before;
	if (before == 0.0f && !paused) {
		const float baseTime = *reinterpret_cast<float*>(g_server + kClampFrameTimeBase);
		float& accumulated = *reinterpret_cast<float*>(player + kPlayerAccumulatedFrameTime);
		if (accumulated > baseTime)
			accumulated = baseTime;
		after = EffectiveFrameTime(player, userCmd, globals->interval_per_tick);
	}

	const int slot = GetPlayerSlot(player);
	if (slot >= 0) {
		BotCmdStats& stats = s_botCmdStats[slot];
		stats.effFrameTimeBefore = before;
		stats.effFrameTime = after;
		if (before == 0.0f)
			++stats.clampFixes;
		stats.playerFlags = *reinterpret_cast<unsigned int*>(player + kPlayerFlagsOffset);
		stats.paused = paused;
		stats.accumulated = *reinterpret_cast<float*>(player + kPlayerAccumulatedFrameTime);
		stats.reference = *reinterpret_cast<float*>(player + kPlayerFrameTimeReference);
	}
	return g_runCommandOriginal(playerMove, player, userCmd, moveHelper);
}

//=============================================================================
// Bot creation
//=============================================================================
class CPluginBotManager {
public:
	virtual void* GetBotController(uint16_t* pEdict);
	virtual __int64 CreateBot(const char* botname);
};

static bool s_creatingBot;
static int s_botTeam;
static int s_botCounter = 1;

typedef __int64 (__fastcall* ChangeTeam_t)(__int64, unsigned int);
static ChangeTeam_t g_changeTeamOriginal;

static __int64 __fastcall Hook_ChangeTeam(__int64 thisptr, unsigned int index)
{
	if (s_creatingBot)
		index = s_botTeam;
	return g_changeTeamOriginal(thisptr, index);
}

static bool CreateBot(int team, const char* name, char* outName, size_t outNameSize)
{
	if (!g_changeTeamOriginal)
		return false;	// without the team hook the bot would join the wrong team

	char botName[32];
	if (name && name[0])
		snprintf(botName, sizeof(botName), "%s", name);
	else
		snprintf(botName, sizeof(botName), "Bot%02d", s_botCounter);

	typedef CPluginBotManager* (*CreateInterfaceFn)(const char*, int*);
	auto createInterface = reinterpret_cast<CreateInterfaceFn>(
		GetProcAddress(reinterpret_cast<HMODULE>(g_server), "CreateInterface"));
	if (!createInterface)
		return false;
	int rc = 0;
	CPluginBotManager* manager = createInterface("BotManager001", &rc);
	if (!manager)
		return false;

	s_botTeam = team;
	s_creatingBot = true;
	__int64 bot = manager->CreateBot(botName);
	s_creatingBot = false;
	if (!bot) {
		Log("CreateBot('%s') failed", botName);
		return false;
	}
	s_botCounter++;

	typedef void (*ClientFullyConnectedFn)(__int64, __int64);
	reinterpret_cast<ClientFullyConnectedFn>(g_server + kClientFullyConnected)(0, bot);
	if (outName && outNameSize)
		snprintf(outName, outNameSize, "%s", botName);
	return true;
}

//=============================================================================
// Navigation (A* over the loaded CAI_Network)
//=============================================================================
constexpr int MAX_HULLS = 5;
constexpr size_t kManagerNetworkOffset = 1600;
constexpr unsigned char kWalkableLinkMask = 0x61;	// same mask the AIN builder uses for traversable links
constexpr unsigned char kWalkLinkBit = 0x01;

#pragma pack(push, 1)
struct CAI_NodeLink {
	short srcId;
	short destId;
	uint8_t hulls[MAX_HULLS];
	char unk0;
	char unk1;
	char unk2[5];
	int64_t flags;
};
struct Vector3f {
	float x, y, z;
};
struct CAI_Node {
	int index;
	Vector3f position;
	float hulls[5];
	float yaw;
	int unk0;
	int flags;
	int unk2[5];
	char unk3[5];
	char pad[3];
	float unk4[5];
	CAI_NodeLink** links;
	char unk5[16];
	int linkcount;
	int unk11;
	short unk6;
	char unk7[16];
	short unk8;
	char unk9[8];
	char scriptdata[8];
};
struct CAI_NetworkHullBitVec {
	uint16_t size;
	uint16_t numInts;
	uint32_t inlineData;
	uint32_t* pData;
};
struct CAI_Network {
	char unk0[8];
	int linkcount;
	int unk1;
	CAI_NetworkHullBitVec hullZoneBits[MAX_HULLS];
	int zonecount[MAX_HULLS];
	int scriptVersion;
	int nodecount;
	int unk5_fake;
	CAI_Node** nodes;
};
#pragma pack(pop)
static_assert(offsetof(CAI_Node, links) == 96, "CAI_Node layout");
static_assert(offsetof(CAI_Node, linkcount) == 120, "CAI_Node layout");
static_assert(offsetof(CAI_Node, scriptdata) == 156, "CAI_Node layout");
static_assert(offsetof(CAI_Network, nodecount) == 120, "CAI_Network layout");
static_assert(offsetof(CAI_Network, nodes) == 128, "CAI_Network layout");

static CAI_Network* GetAINetwork()
{
	if (!g_server)
		return nullptr;
	const uintptr_t manager = *reinterpret_cast<uintptr_t*>(g_server + kAINetworkManager);
	if (!manager)
		return nullptr;
	CAI_Network* network = *reinterpret_cast<CAI_Network**>(manager + kManagerNetworkOffset);
	if (!network || !network->nodes || network->nodecount <= 0)
		return nullptr;
	return network;
}

static float DistanceSquared(const Vector3f& a, const Vector3f& b)
{
	const float dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
	return dx * dx + dy * dy + dz * dz;
}

static int FindNearestNode(const CAI_Network* network, const Vector3f& origin)
{
	int best = -1;
	float bestDistance = 3.402823466e+38F;
	for (int i = 0; i < network->nodecount; ++i) {
		const CAI_Node* node = network->nodes[i];
		if (!node)
			continue;
		const float distance = DistanceSquared(node->position, origin);
		if (distance < bestDistance) {
			bestDistance = distance;
			best = i;
		}
	}
	return best;
}

// Links that are only NPC traverses (0x20/0x40 without the walk bit 0x01): vaults, jump-ups,
// jump-downs, wall climbs and long jumps played as animations by grunts/spectres. A pilot can only
// repeat some of them, so when limits are active a traverse link is usable only up to maxRise of
// climb and maxGap of horizontal distance (going down is always fine), and costs more than walking.
struct TraverseLimits {
	bool active = false;
	float maxRise = 0.0f;
	float maxGap = 0.0f;
	float costScale = 2.0f;
};

static bool TraverseLinkAllowed(const CAI_NodeLink* link, int hull, const Vector3f& from, const Vector3f& to,
	const TraverseLimits& limits, float& costScale)
{
	costScale = 1.0f;
	if (!limits.active || (link->hulls[hull] & kWalkLinkBit) != 0)
		return true;
	const float rise = to.z - from.z;
	const float dx = to.x - from.x, dy = to.y - from.y;
	const float gap = std::sqrt(dx * dx + dy * dy);
	if (rise > limits.maxRise || gap > limits.maxGap)
		return false;
	costScale = limits.costScale;
	return true;
}

static std::vector<int> FindPathNodes(const CAI_Network* network, int startNode, int goalNode, int hull, const TraverseLimits& limits)
{
	std::vector<int> path;
	const int nodeCount = network->nodecount;
	if (startNode < 0 || goalNode < 0 || startNode >= nodeCount || goalNode >= nodeCount)
		return path;

	std::vector<float> gScore(nodeCount, 3.402823466e+38F);
	std::vector<int> cameFrom(nodeCount, -1);
	std::vector<bool> closed(nodeCount, false);
	using QueueEntry = std::pair<float, int>;
	std::priority_queue<QueueEntry, std::vector<QueueEntry>, std::greater<QueueEntry>> open;

	const Vector3f goalPosition = network->nodes[goalNode]->position;
	gScore[startNode] = 0.0f;
	open.push({ std::sqrt(DistanceSquared(network->nodes[startNode]->position, goalPosition)), startNode });

	while (!open.empty()) {
		const int current = open.top().second;
		open.pop();
		if (closed[current])
			continue;
		if (current == goalNode)
			break;
		closed[current] = true;

		const CAI_Node* node = network->nodes[current];
		if (!node || !node->links)
			continue;
		for (int i = 0; i < node->linkcount; ++i) {
			const CAI_NodeLink* link = node->links[i];
			if (!link || (link->hulls[hull] & kWalkableLinkMask) == 0)
				continue;
			const int neighbor = (link->srcId == current) ? link->destId : link->srcId;
			if (neighbor < 0 || neighbor >= nodeCount || closed[neighbor] || !network->nodes[neighbor])
				continue;
			const Vector3f& neighborPosition = network->nodes[neighbor]->position;
			float costScale = 1.0f;
			if (!TraverseLinkAllowed(link, hull, node->position, neighborPosition, limits, costScale))
				continue;
			const float tentative = gScore[current] + costScale * std::sqrt(DistanceSquared(node->position, neighborPosition));
			if (tentative >= gScore[neighbor])
				continue;
			gScore[neighbor] = tentative;
			cameFrom[neighbor] = current;
			open.push({ tentative + std::sqrt(DistanceSquared(neighborPosition, goalPosition)), neighbor });
		}
	}

	if (startNode != goalNode && cameFrom[goalNode] == -1)
		return path;
	for (int node = goalNode; node != -1; node = cameFrom[node])
		path.push_back(node);
	std::reverse(path.begin(), path.end());
	return path;
}

// A* from the node nearest start to the node nearest goal, pushed as a flat [x0, y0, z0, x1, ...]
// array (empty when no path exists).
static void PushPath(HSQUIRRELVM v, const Vector3f& start, const Vector3f& goal, int hull, const TraverseLimits& limits)
{
	std::vector<float> flat;
	const CAI_Network* network = GetAINetwork();
	if (network) {
		const std::vector<int> nodes = FindPathNodes(network, FindNearestNode(network, start), FindNearestNode(network, goal), hull, limits);
		flat.reserve(nodes.size() * 3);
		for (int nodeIndex : nodes) {
			const Vector3f& p = network->nodes[nodeIndex]->position;
			flat.push_back(p.x);
			flat.push_back(p.y);
			flat.push_back(p.z);
		}
	}
	PushFloatArray(v, flat);
}

//=============================================================================
// Script functions
//=============================================================================
static bool s_lateHooksOk;

static SQInteger Script_PilotBotsPing(HSQUIRRELVM v)
{
	char msg[160];
	snprintf(msg, sizeof(msg), "pilotbots.dll %s - hooks %s", PILOTBOTS_VERSION, s_lateHooksOk ? "ok" : "FALHARAM");
	sq_pushstring(v, msg, -1);
	return 1;
}

// Script-side progress and errors go to pilotbots.log too, since the game writes no console log.
static SQInteger Script_PilotBotsLog(HSQUIRRELVM v)
{
	const char* text = nullptr;
	if (SQ_FAILED(sq_getstring(v, 2, &text)) || !text)
		return sq_throwerror(v, "text must be a string");
	Log("script: %s", text);
	return 0;
}

static SQInteger Script_BotSetInput(HSQUIRRELVM v)
{
	BotInput* input = GetBotInputArg(v);
	if (!input)
		return sq_throwerror(v, "invalid bot player");
	float forward, side, pitch, yaw;
	int buttons;
	if (!GetFloatArg(v, 3, forward) || !GetFloatArg(v, 4, side) || !GetFloatArg(v, 5, pitch)
		|| !GetFloatArg(v, 6, yaw) || !GetIntArg(v, 7, buttons))
		return sq_throwerror(v, "expected (entity, float forward, float side, float pitch, float yaw, int buttons)");
	input->forward = std::clamp(forward, -1.0f, 1.0f);
	input->side = std::clamp(side, -1.0f, 1.0f);
	input->pitch = std::clamp(pitch, -89.0f, 89.0f);
	input->yaw = yaw;
	input->heldButtons = buttons;
	input->active = true;
	return 0;
}

static SQInteger Script_BotPressButtons(HSQUIRRELVM v)
{
	BotInput* input = GetBotInputArg(v);
	if (!input)
		return sq_throwerror(v, "invalid bot player");
	int buttons;
	if (!GetIntArg(v, 3, buttons))
		return sq_throwerror(v, "buttons must be an integer");
	input->pulseButtons |= buttons;
	input->active = true;
	return 0;
}

static SQInteger Script_BotClearInput(HSQUIRRELVM v)
{
	BotInput* input = GetBotInputArg(v);
	if (!input)
		return sq_throwerror(v, "invalid bot player");
	*input = {};
	return 0;
}

static SQInteger Script_BotCreate(HSQUIRRELVM v)
{
	int team;
	if (!GetIntArg(v, 2, team))
		return sq_throwerror(v, "team must be an integer");
	const char* requestedName = nullptr;
	if (SQ_FAILED(sq_getstring(v, 3, &requestedName)))
		return sq_throwerror(v, "name must be a string");
	char botName[32] = {};
	if (!CreateBot(team, requestedName, botName, sizeof(botName)))
		botName[0] = '\0';
	sq_pushstring(v, botName, -1);
	return 1;
}

static SQInteger Script_BotGetDebugInfo(HSQUIRRELVM v)
{
	void* player = GetEntityArg(v, 2);
	const int slot = GetPlayerSlot(reinterpret_cast<uintptr_t>(player));
	char text[256];
	if (slot < 0) {
		snprintf(text, sizeof(text), "slot invalido (ent=%p)", player);
	}
	else {
		const BotCmdStats& stats = s_botCmdStats[slot];
		// Short lines: the HUD message gets cut off around 70 characters.
		snprintf(text, sizeof(text),
			"cmds=%u aplic=%u fwd=%.2f btn=0x%X\n"
			"ft_cmd=%.4f ft_antes=%.4f ft_mov=%.4f\n"
			"zerados=%u pausa=%d flags=0x%X\n"
			"acum=%.2f ref=%.2f",
			stats.seen, stats.applied, stats.lastForward, stats.lastButtons,
			stats.lastFrameTime, stats.effFrameTimeBefore, stats.effFrameTime,
			stats.clampFixes, stats.paused, stats.playerFlags,
			stats.accumulated, stats.reference);
	}
	sq_pushstring(v, text, -1);
	return 1;
}

static SQInteger Script_NavGetNodeCount(HSQUIRRELVM v)
{
	const CAI_Network* network = GetAINetwork();
	sq_pushinteger(nullptr, v, network ? network->nodecount : 0);
	return 1;
}

static SQInteger Script_NavGetNodePosition(HSQUIRRELVM v)
{
	int index;
	if (!GetIntArg(v, 2, index))
		return sq_throwerror(v, "index must be an integer");
	const CAI_Network* network = GetAINetwork();
	if (!network || index < 0 || index >= network->nodecount || !network->nodes[index])
		return sq_throwerror(v, "invalid node index");
	const Vector3f& p = network->nodes[index]->position;
	PushFloatArray(v, { p.x, p.y, p.z });
	return 1;
}

static SQInteger Script_NavFindPath(HSQUIRRELVM v)
{
	float sx, sy, sz, ex, ey, ez;
	int hull;
	if (!GetFloatArg(v, 2, sx) || !GetFloatArg(v, 3, sy) || !GetFloatArg(v, 4, sz)
		|| !GetFloatArg(v, 5, ex) || !GetFloatArg(v, 6, ey) || !GetFloatArg(v, 7, ez) || !GetIntArg(v, 8, hull))
		return sq_throwerror(v, "expected (float sx, float sy, float sz, float ex, float ey, float ez, int hull)");
	if (hull < 0 || hull >= MAX_HULLS)
		return sq_throwerror(v, "invalid hull");
	PushPath(v, { sx, sy, sz }, { ex, ey, ez }, hull, TraverseLimits());
	return 1;
}

static SQInteger Script_NavFindPathPilot(HSQUIRRELVM v)
{
	float sx, sy, sz, ex, ey, ez, maxRise, maxGap;
	int hull;
	if (!GetFloatArg(v, 2, sx) || !GetFloatArg(v, 3, sy) || !GetFloatArg(v, 4, sz)
		|| !GetFloatArg(v, 5, ex) || !GetFloatArg(v, 6, ey) || !GetFloatArg(v, 7, ez) || !GetIntArg(v, 8, hull)
		|| !GetFloatArg(v, 9, maxRise) || !GetFloatArg(v, 10, maxGap))
		return sq_throwerror(v, "expected (float sx, float sy, float sz, float ex, float ey, float ez, int hull, float maxRise, float maxGap)");
	if (hull < 0 || hull >= MAX_HULLS)
		return sq_throwerror(v, "invalid hull");
	TraverseLimits limits;
	limits.active = true;
	limits.maxRise = maxRise;
	limits.maxGap = maxGap;
	PushPath(v, { sx, sy, sz }, { ex, ey, ez }, hull, limits);
	return 1;
}

static SQFuncReg MakeReg(const char* name, SQFUNCTION fn, const char* typeMask, int nparams, const char* ret, const char* args, const char* help)
{
	SQFuncReg r;
	memset(&r, 0, sizeof(r));
	r.squirrelFuncName = r.cppFuncName = name;
	r.helpText = help;
	r.szTypeMask = typeMask;
	r.nparamscheck = nparams;
	r.returnValueTypeText = ret;
	r.argNamesText = args;
	r.unk32 = 32;
	r.pfnBinding = reinterpret_cast<void*>(&SQFuncBindingFn);
	r.pFunction = reinterpret_cast<void*>(fn);
	r.flags = 2;
	return r;
}

// AddSquirrelReg keeps the pointer, so the registrations live for the whole process.
static SQFuncReg g_serverRegs[] = {
	MakeReg("PilotBotsPing", Script_PilotBotsPing, ".", 1, "string", "", "pilotbots.dll status"),
	MakeReg("PilotBotsLog", Script_PilotBotsLog, ".s", 2, "void", "string text", "Append a line to pilotbots.log"),
	MakeReg("BotSetInput", Script_BotSetInput, ".Iffffi", 7, "void",
		"entity bot, float forward, float side, float pitch, float yaw, int buttons",
		"Set the movement, view angles and held buttons written into a bot's usercmds."),
	MakeReg("BotPressButtons", Script_BotPressButtons, ".Ii", 3, "void", "entity bot, int buttons",
		"Press buttons for a single usercmd (jump, melee, offhands)."),
	MakeReg("BotClearInput", Script_BotClearInput, ".I", 2, "void", "entity bot", "Stop overriding a bot's usercmds."),
	MakeReg("BotCreate", Script_BotCreate, ".is", 3, "string", "int team, string name",
		"Create a bot player on a team with the given name (empty = BotNN). Returns its name, or an empty string on failure."),
	MakeReg("BotGetDebugInfo", Script_BotGetDebugInfo, ".I", 2, "string", "entity bot", "Usercmd injection counters for a bot (debugging)."),
	MakeReg("NavGetNodeCount", Script_NavGetNodeCount, ".", 1, "int", "", "Number of nodes in the loaded AI node graph."),
	MakeReg("NavGetNodePosition", Script_NavGetNodePosition, ".i", 2, "array", "int index", "Position of an AI node as [x, y, z]."),
	MakeReg("NavFindPath", Script_NavFindPath, ".ffffffi", 8, "array",
		"float sx, float sy, float sz, float ex, float ey, float ez, int hull",
		"A* path over the AI node graph as a flat [x0, y0, z0, x1, ...] array (empty if unreachable)."),
	MakeReg("NavFindPathPilot", Script_NavFindPathPilot, ".ffffffiff", 10, "array",
		"float sx, float sy, float sz, float ex, float ey, float ez, int hull, float maxRise, float maxGap",
		"Like NavFindPath, but NPC traverse links are only used where a pilot can follow: at most maxRise up and maxGap across."),
};

//=============================================================================
// Client crash guard: CL_CopyExistingEntity
//=============================================================================
// The frame the entity is delta'd from (info + 0x10) keeps per entity an offset into the client's
// packed-entity buffer at +0x3C. -1 means no stored state: the original reads buffer + 0xFFFFFFFF
// and crashes in engine+0x1D6F60 (seen while a dead human spectates bots). Disconnect instead.
typedef void (*CLCopyExistingEntity_t)(uintptr_t info);
static CLCopyExistingEntity_t g_clCopyOriginal;

static void Hook_CL_CopyExistingEntity(uintptr_t info)
{
	const int newEntity = *reinterpret_cast<int*>(info + 0x28);
	const uintptr_t fromFrame = *reinterpret_cast<uintptr_t*>(info + 0x10);
	if (fromFrame && newEntity >= 0 && newEntity < 2048) {
		const int packedOffset = *reinterpret_cast<const int*>(fromFrame + 0x3C + newEntity * 4);
		if (packedOffset < 0) {
			Log("CL_CopyExistingEntity: entity %d has no stored state; disconnecting instead of crashing", newEntity);
			reinterpret_cast<void(__cdecl*)(const char*, ...)>(g_engine + kHostError)(
				"CL_CopyExistingEntity: entity %d has no stored state.\n", newEntity);
			return;
		}
	}
	g_clCopyOriginal(info);
}

//=============================================================================
// Console variables used by the bot scripts and the private match menu
//=============================================================================
constexpr int FCVAR_GAMEDLL = 1 << 2;
constexpr int FCVAR_HIDDEN = 1 << 4;

static void RegisterConVars()
{
	static bool done;
	if (done || !g_engine || !SIG_OK(g_engine, kConVarCtor, kSigConVarCtor))
		return;
	done = true;

	struct Def { const char* name; const char* value; int flags; const char* help; };
	static const Def defs[] = {
		{ "pm_bot_count", "0", FCVAR_HIDDEN, "Private match: number of pilot bots (0-10). Managed by script" },
		{ "pm_bot_lethality", "0", FCVAR_HIDDEN, "Private match: pilot bot lethality setting index. Managed by script" },
		{ "delta_bot_fill_target", "0", FCVAR_GAMEDLL, "Fill the match with script-driven bots until humans + bots reach this count (0 = off). Managed by script" },
		{ "delta_bot_difficulty", "1", FCVAR_GAMEDLL, "Bot skill from 0 (easy) to 3 (hard). Managed by script" },
	};
	// ConVar objects live for the whole process (sizeof(ConVarR1) is 0x88).
	static __declspec(align(16)) unsigned char storage[sizeof(defs) / sizeof(defs[0])][0x100];
	typedef void (*ConVarCtor_t)(void*, const char*, const char*, int, const char*);
	auto ctor = reinterpret_cast<ConVarCtor_t>(g_engine + kConVarCtor);
	for (size_t i = 0; i < sizeof(defs) / sizeof(defs[0]); i++)
		ctor(storage[i], defs[i].name, defs[i].value, defs[i].flags, defs[i].help);
	Log("convars registered");
}

//=============================================================================
// Hooks
//=============================================================================
typedef void* (*CreateNewVM_t)(__int64, int, unsigned int);
static CreateNewVM_t g_createNewVMOriginal;

static bool HookOne(const char* name, uintptr_t target, void* detour, void** original)
{
	MH_STATUS s = MH_CreateHook(reinterpret_cast<void*>(target), detour, original);
	if (s == MH_OK)
		s = MH_EnableHook(reinterpret_cast<void*>(target));
	Log("hook %s: %s (%d)", name, s == MH_OK ? "ok" : "FAILED", s);
	return s == MH_OK;
}

// Server script errors ("SCRIPT ERROR: ..." + "CALLSTACK" + frames) only reach the console and
// R1Delta's telemetry; the game writes no console log. Copy them to pilotbots.log. Hooked on top
// of R1Delta's replacement of the VM print function (installed late, see InstallLateHooks).
typedef void (*ServerPrint_t)(void*, const char*, ...);
static ServerPrint_t g_serverPrintOriginal;
static int s_errorLinesLeft;
static int s_errorBudget = 400;	// lines per session, in case something errors every frame

static void Hook_ServerPrint(void* vm, const char* fmt, ...)
{
	char text[2048];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(text, sizeof(text), fmt ? fmt : "", ap);
	va_end(ap);

	if (strstr(text, "SCRIPT ERROR"))
		s_errorLinesLeft = 24;
	if (s_errorLinesLeft > 0 && s_errorBudget > 0) {
		s_errorLinesLeft--;
		s_errorBudget--;
		size_t len = strlen(text);
		while (len && (text[len - 1] == '\n' || text[len - 1] == '\r'))
			text[--len] = '\0';
		if (len)
			Log("server: %s", text);
		text[len] = '\n';	// restore for the original print
		text[len + 1 < sizeof(text) ? len + 1 : len] = '\0';
	}
	g_serverPrintOriginal(vm, "%s", text);
}

// server.dll/engine.dll hooks, installed after R1Delta's own (R1Delta hooks server.dll when it
// loads; the first script VM is created later). PlayerMoveRunCommand waits for R1Delta's JMP so
// R1Delta's prologue check still passes; once the server VM exists R1Delta had its chance.
static void InstallLateHooks(bool serverVM)
{
	static bool done;
	if (done)
		return;
	g_server = reinterpret_cast<uintptr_t>(GetModuleHandleA("server.dll"));
	g_engine = reinterpret_cast<uintptr_t>(GetModuleHandleA("engine.dll"));
	if (!g_server || !g_engine)
		return;
	const uintptr_t runCommand = g_server + kPlayerMoveRunCommand;
	if (!IsJmp(runCommand) && !serverVM)
		return;	// R1Delta has not hooked it yet; try again on the next VM
	done = true;

	if (!SIG_OR_JMP(g_server, kPlayerMoveRunCommand, kSigRunCommand)
		|| !SIG_OR_JMP(g_server, kChangeTeam, kSigChangeTeam)
		|| !SIG_OK(g_server, kClientFullyConnected, kSigClientFullyConnected)) {
		Log("server.dll bytes do not match; bot hooks NOT installed");
		return;
	}
	bool ok = HookOne("PlayerMoveRunCommand", runCommand, reinterpret_cast<void*>(&Hook_PlayerMoveRunCommand), reinterpret_cast<void**>(&g_runCommandOriginal));
	ok = HookOne("ChangeTeam", g_server + kChangeTeam, reinterpret_cast<void*>(&Hook_ChangeTeam), reinterpret_cast<void**>(&g_changeTeamOriginal)) && ok;
	if (SIG_OR_JMP(g_engine, kCLCopyExistingEntity, kSigCLCopyExistingEntity) && SIG_OK(g_engine, kHostError, kSigHostError))
		HookOne("CL_CopyExistingEntity", g_engine + kCLCopyExistingEntity, reinterpret_cast<void*>(&Hook_CL_CopyExistingEntity), reinterpret_cast<void**>(&g_clCopyOriginal));
	else
		Log("engine.dll bytes do not match; CL_CopyExistingEntity guard NOT installed");
	if (SIG_OR_JMP(g_launcher, kServerPrint, kSigServerPrint))
		HookOne("server script print", g_launcher + kServerPrint, reinterpret_cast<void*>(&Hook_ServerPrint), reinterpret_cast<void**>(&g_serverPrintOriginal));
	s_lateHooksOk = ok;
}

static bool AddressInModule(uintptr_t addr, const char* module)
{
	HMODULE m = GetModuleHandleA(module);
	if (!m)
		return false;
	auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(m);
	auto nt = reinterpret_cast<IMAGE_NT_HEADERS*>(reinterpret_cast<uintptr_t>(m) + dos->e_lfanew);
	uintptr_t base = reinterpret_cast<uintptr_t>(m);
	return addr >= base && addr < base + nt->OptionalHeader.SizeOfImage;
}

// Our menu strings live in resource/pilotbots_<language>.txt rather than in R1Delta's
// delta_<language>.txt, which other mods ship their own copy of (an addon's copy wins and drops
// ours). Added on every UI VM, before its menus load; adding the same file again just refreshes it.
static void LoadLocalization()
{
	HMODULE localize = GetModuleHandleA("localize.dll");
	if (!localize)
		return;
	typedef void* (*CreateInterfaceFn)(const char*, int*);
	auto createInterface = reinterpret_cast<CreateInterfaceFn>(GetProcAddress(localize, "CreateInterface"));
	void* iface = createInterface ? createInterface("Localize_001", nullptr) : nullptr;
	if (!iface)
		return;
	// ILocalize::AddFile (vtable slot 8, the call R1Delta uses for delta_%language%.txt)
	typedef bool (__fastcall* AddFile_t)(void*, const char*, const char*, bool);
	auto addFile = (*reinterpret_cast<AddFile_t**>(iface))[8];
	const bool ok = addFile(iface, "resource/pilotbots_%language%.txt", "GAME", false);
	static bool logged;
	if (!logged) {
		logged = true;
		Log("localization resource/pilotbots_%%language%%.txt: %s", ok ? "ok" : "NOT FOUND");
	}
}

static void* Hook_CreateNewVM(__int64 a1, int a2, unsigned int context)
{
	void* vm = g_createNewVMOriginal(a1, a2, context);
	InstallLateHooks(context == 0);
	if (vm && context == 2)	// 2 = UI VM
		LoadLocalization();
	if (!vm || context != 0)	// 0 = server VM
		return vm;

	// R1Delta replaces the server VM with a static stand-in inside tier0.dll. If we got that one,
	// our hook is the outer one and registering into it would corrupt R1Delta's object.
	if (AddressInModule(reinterpret_cast<uintptr_t>(vm), "tier0.dll")) {
		Log("CreateNewVM: got R1Delta's fake server VM %p; hook order wrong, natives NOT registered", vm);
		return vm;
	}
	for (SQFuncReg& r : g_serverRegs)
		g_addSquirrelReg(vm, &r);
	Log("CreateNewVM: server VM %p, %d natives registered", vm, (int)(sizeof(g_serverRegs) / sizeof(g_serverRegs[0])));
	return vm;
}

static void InstallVMHook()
{
	static bool done;
	if (done)
		return;
	done = true;

	g_launcher = reinterpret_cast<uintptr_t>(GetModuleHandleA("launcher.dll"));
	if (!g_launcher) {
		Log("launcher.dll not loaded (dedicated server?); doing nothing");
		return;
	}
	if (!SIG_OK(g_launcher, kCreateNewVM, kSigCreateNewVM) || !SIG_OK(g_launcher, kAddSquirrelReg, kSigAddSquirrelReg)
		|| !SIG_OK(g_launcher, kSqPushString, kSigSqPushString) || !SIG_OK(g_launcher, kSqPushFloat, kSigSqPushFloat)) {
		Log("launcher.dll bytes do not match (already hooked or unknown build); doing nothing");
		return;
	}
	g_addSquirrelReg = reinterpret_cast<AddSquirrelReg_t>(g_launcher + kAddSquirrelReg);
	sq_getstring = reinterpret_cast<decltype(sq_getstring)>(g_launcher + kSqGetString);
	sq_getinteger = reinterpret_cast<decltype(sq_getinteger)>(g_launcher + kSqGetInteger);
	sq_getfloat = reinterpret_cast<decltype(sq_getfloat)>(g_launcher + kSqGetFloat);
	sq_getstackobj = reinterpret_cast<decltype(sq_getstackobj)>(g_launcher + kSqGetStackObj);
	sq_pushstring = reinterpret_cast<decltype(sq_pushstring)>(g_launcher + kSqPushString);
	sq_pushinteger = reinterpret_cast<decltype(sq_pushinteger)>(g_launcher + kSqPushInteger);
	sq_pushfloat = reinterpret_cast<decltype(sq_pushfloat)>(g_launcher + kSqPushFloat);
	sq_newarray = reinterpret_cast<decltype(sq_newarray)>(g_launcher + kSqNewArray);
	sq_arrayappend = reinterpret_cast<decltype(sq_arrayappend)>(g_launcher + kSqArrayAppend);
	sq_throwerror = reinterpret_cast<decltype(sq_throwerror)>(g_launcher + kSqThrowError);

	MH_STATUS s = MH_Initialize();
	if (s != MH_OK && s != MH_ERROR_ALREADY_INITIALIZED) {
		Log("MH_Initialize failed: %d", s);
		return;
	}
	HookOne("CreateNewVM", g_launcher + kCreateNewVM, reinterpret_cast<void*>(&Hook_CreateNewVM), reinterpret_cast<void**>(&g_createNewVMOriginal));
}

//=============================================================================
// Loader notifications
//=============================================================================
// engine.dll load: after R1Delta's tier0 DllMain (which binary-patches launcher.dll), before
// server.dll, where R1Delta hooks CreateNewVM on top of ours.
// server.dll load: the engine is initialized by then, so its ConVar constructor can run (R1Delta
// registers its own convars at the same point).
struct LdrDllLoadedData {
	ULONG Flags;
	PCUNICODE_STRING FullDllName;
	PCUNICODE_STRING BaseDllName;
	PVOID DllBase;
	ULONG SizeOfImage;
};
typedef VOID(CALLBACK* LdrNotificationFn)(ULONG, const LdrDllLoadedData*, PVOID);
typedef NTSTATUS(NTAPI* LdrRegisterDllNotification_t)(ULONG, LdrNotificationFn, PVOID, PVOID*);
static PVOID g_notifyCookie;

static bool NameIs(const UNICODE_STRING* name, const wchar_t* expected)
{
	const size_t len = wcslen(expected);
	return name->Length == len * sizeof(wchar_t) && _wcsnicmp(name->Buffer, expected, len) == 0;
}

static VOID CALLBACK OnDllNotification(ULONG reason, const LdrDllLoadedData* data, PVOID)
{
	if (reason != 1 || !data || !data->BaseDllName || !data->BaseDllName->Buffer)	// 1 = loaded
		return;
	if (NameIs(data->BaseDllName, L"engine.dll")) {
		InstallVMHook();
	}
	else if (NameIs(data->BaseDllName, L"server.dll") && g_launcher) {
		g_engine = reinterpret_cast<uintptr_t>(GetModuleHandleA("engine.dll"));
		RegisterConVars();
	}
}

extern "C" __declspec(dllexport) int PilotBots_Init()
{
	// Exported so tier0.dll's injected import entry has something to bind to.
	return 1;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH) {
		DisableThreadLibraryCalls(module);
		InitLogPath(module);
		char exe[MAX_PATH] = {};
		GetModuleFileNameA(nullptr, exe, MAX_PATH);
		Log("loaded, version %s, process %s", PILOTBOTS_VERSION, exe);
		auto reg = reinterpret_cast<LdrRegisterDllNotification_t>(
			GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "LdrRegisterDllNotification"));
		if (reg)
			reg(0, &OnDllNotification, nullptr, &g_notifyCookie);
	}
	return TRUE;
}
