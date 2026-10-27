// rea decompile_all
// name: FUN_100202ae0
// address: 0x100202ae0
// body: available
// range: 0x100202ae0-0x100202afb inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


uint FUN_100202ae0(int *param_1)

{
  uint uVar1;
  
  uVar1 = *param_1 + 3;
  if (*(byte *)(param_1 + 6) >> 6 != 3) {
    uVar1 = (uint)(*(byte *)(param_1 + 6) >> 6);
  }
  return uVar1;
}

