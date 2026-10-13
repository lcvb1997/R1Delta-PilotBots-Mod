// pbinject - adds an import of pilotbots.dll!PilotBots_Init to a PE32+ DLL (R1Delta's tier0.dll),
// so Windows loads pilotbots.dll together with it. The original import table is left in place;
// a new section holds a copy of the descriptors plus the new one.
//
//   pbinject <in.dll> <out.dll>     inject (out may equal in); exit 0 also when already injected
//   pbinject --check <dll>          exit 0 if injected, 1 if not
//
// Exit codes: 0 ok, 1 not injected (--check), 2 usage, 3 io error, 4 unsupported PE.

#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static const char* kDll = "pilotbots.dll";
static const char* kFunc = "PilotBots_Init";

static DWORD AlignUp(DWORD v, DWORD a) { return (v + a - 1) / a * a; }

static bool ReadAll(const char* path, std::vector<unsigned char>& out)
{
	FILE* f = nullptr;
	if (fopen_s(&f, path, "rb") != 0 || !f)
		return false;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	out.resize(n);
	bool ok = fread(out.data(), 1, n, f) == (size_t)n;
	fclose(f);
	return ok;
}

static bool WriteAll(const char* path, const std::vector<unsigned char>& data)
{
	std::string tmp = std::string(path) + ".pbtmp";
	FILE* f = nullptr;
	if (fopen_s(&f, tmp.c_str(), "wb") != 0 || !f)
		return false;
	bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
	ok = (fclose(f) == 0) && ok;
	if (!ok || !MoveFileExA(tmp.c_str(), path, MOVEFILE_REPLACE_EXISTING)) {
		DeleteFileA(tmp.c_str());
		return false;
	}
	return true;
}

struct Pe {
	std::vector<unsigned char>& d;
	IMAGE_NT_HEADERS64* nt = nullptr;
	IMAGE_SECTION_HEADER* sec = nullptr;

	explicit Pe(std::vector<unsigned char>& data) : d(data) {}

	bool Parse()
	{
		if (d.size() < sizeof(IMAGE_DOS_HEADER))
			return false;
		auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(d.data());
		if (dos->e_magic != IMAGE_DOS_SIGNATURE || (size_t)dos->e_lfanew + sizeof(IMAGE_NT_HEADERS64) > d.size())
			return false;
		nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(d.data() + dos->e_lfanew);
		if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
			return false;
		sec = IMAGE_FIRST_SECTION(nt);
		return true;
	}

	// File offset of an RVA, or -1.
	long long Off(DWORD rva) const
	{
		for (WORD i = 0; i < nt->FileHeader.NumberOfSections; i++) {
			const IMAGE_SECTION_HEADER& s = sec[i];
			DWORD size = s.Misc.VirtualSize ? s.Misc.VirtualSize : s.SizeOfRawData;
			if (rva >= s.VirtualAddress && rva < s.VirtualAddress + size && rva - s.VirtualAddress < s.SizeOfRawData)
				return (long long)s.PointerToRawData + (rva - s.VirtualAddress);
		}
		return -1;
	}

	const char* Str(DWORD rva) const
	{
		long long o = Off(rva);
		return o < 0 ? nullptr : reinterpret_cast<const char*>(d.data() + o);
	}
};

static bool IsInjected(Pe& pe, std::vector<IMAGE_IMPORT_DESCRIPTOR>& descs)
{
	const IMAGE_DATA_DIRECTORY& dir = pe.nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
	long long o = pe.Off(dir.VirtualAddress);
	if (o < 0)
		return false;
	bool found = false;
	for (;; o += sizeof(IMAGE_IMPORT_DESCRIPTOR)) {
		if (o + (long long)sizeof(IMAGE_IMPORT_DESCRIPTOR) > (long long)pe.d.size())
			break;
		IMAGE_IMPORT_DESCRIPTOR desc;
		memcpy(&desc, pe.d.data() + o, sizeof(desc));
		if (desc.Name == 0 && desc.FirstThunk == 0)
			break;
		descs.push_back(desc);
		const char* name = pe.Str(desc.Name);
		if (name && _stricmp(name, kDll) == 0)
			found = true;
	}
	return found;
}

int main(int argc, char** argv)
{
	bool check = argc == 3 && strcmp(argv[1], "--check") == 0;
	if (!check && argc != 3) {
		fprintf(stderr, "usage: pbinject <in.dll> <out.dll> | pbinject --check <dll>\n");
		return 2;
	}
	const char* in = check ? argv[2] : argv[1];

	std::vector<unsigned char> data;
	if (!ReadAll(in, data)) {
		fprintf(stderr, "cannot read %s\n", in);
		return 3;
	}
	Pe pe(data);
	if (!pe.Parse()) {
		fprintf(stderr, "%s: not a PE32+ image\n", in);
		return 4;
	}
	std::vector<IMAGE_IMPORT_DESCRIPTOR> descs;
	bool injected = IsInjected(pe, descs);
	if (check) {
		printf("%s\n", injected ? "injected" : "not injected");
		return injected ? 0 : 1;
	}
	if (injected) {
		printf("already injected\n");
		return WriteAll(argv[2], data) ? 0 : 3;
	}
	if (descs.empty()) {
		fprintf(stderr, "no import table\n");
		return 4;
	}
	if (pe.nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress != 0) {
		// Signed images keep the certificate at the end of the file; not handled.
		fprintf(stderr, "signed image not supported\n");
		return 4;
	}

	IMAGE_OPTIONAL_HEADER64& opt = pe.nt->OptionalHeader;
	WORD n = pe.nt->FileHeader.NumberOfSections;
	DWORD hdrEnd = (DWORD)((unsigned char*)&pe.sec[n + 1] - data.data());
	DWORD firstRaw = MAXDWORD;
	for (WORD i = 0; i < n; i++)
		if (pe.sec[i].PointerToRawData && pe.sec[i].PointerToRawData < firstRaw)
			firstRaw = pe.sec[i].PointerToRawData;
	if (hdrEnd > opt.SizeOfHeaders || hdrEnd > firstRaw) {
		fprintf(stderr, "no room for another section header\n");
		return 4;
	}

	// New section layout (offsets inside the section):
	//   descriptors (old + new + null) | INT[2] | IAT[2] | hint/name | dll name
	const IMAGE_SECTION_HEADER& last = pe.sec[n - 1];
	DWORD secRva = AlignUp(last.VirtualAddress + max(last.Misc.VirtualSize, last.SizeOfRawData), opt.SectionAlignment);
	DWORD secRaw = AlignUp((DWORD)data.size(), opt.FileAlignment);

	DWORD descSize = (DWORD)((descs.size() + 2) * sizeof(IMAGE_IMPORT_DESCRIPTOR));
	DWORD intOff = AlignUp(descSize, 8);
	DWORD iatOff = intOff + 16;
	DWORD hintOff = iatOff + 16;
	DWORD nameOff = AlignUp(hintOff + 2 + (DWORD)strlen(kFunc) + 1, 2);
	DWORD contentSize = nameOff + (DWORD)strlen(kDll) + 1;

	std::vector<unsigned char> secData(AlignUp(contentSize, opt.FileAlignment), 0);
	IMAGE_IMPORT_DESCRIPTOR mine = {};
	mine.OriginalFirstThunk = secRva + intOff;
	mine.FirstThunk = secRva + iatOff;
	mine.Name = secRva + nameOff;
	descs.push_back(mine);
	memcpy(secData.data(), descs.data(), descs.size() * sizeof(IMAGE_IMPORT_DESCRIPTOR));
	ULONGLONG thunk = secRva + hintOff;
	memcpy(secData.data() + intOff, &thunk, 8);
	memcpy(secData.data() + iatOff, &thunk, 8);
	memcpy(secData.data() + hintOff + 2, kFunc, strlen(kFunc));
	memcpy(secData.data() + nameOff, kDll, strlen(kDll));

	IMAGE_SECTION_HEADER sh = {};
	memcpy(sh.Name, ".pbimp", 6);
	sh.Misc.VirtualSize = contentSize;
	sh.VirtualAddress = secRva;
	sh.SizeOfRawData = (DWORD)secData.size();
	sh.PointerToRawData = secRaw;
	sh.Characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE;
	pe.sec[n] = sh;

	pe.nt->FileHeader.NumberOfSections = n + 1;
	opt.SizeOfImage = AlignUp(secRva + contentSize, opt.SectionAlignment);
	opt.SizeOfInitializedData += sh.SizeOfRawData;
	opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress = secRva;
	opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].Size = descSize;
	opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT].VirtualAddress = 0;
	opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT].Size = 0;
	opt.CheckSum = 0;

	data.resize(secRaw, 0);
	data.insert(data.end(), secData.begin(), secData.end());
	if (!WriteAll(argv[2], data)) {
		fprintf(stderr, "cannot write %s\n", argv[2]);
		return 3;
	}
	printf("injected %s!%s into %s\n", kDll, kFunc, argv[2]);
	return 0;
}
