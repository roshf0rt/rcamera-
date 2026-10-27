// rea decompile_all
// name: _$s10CaptureLib0A4LensV23__derived_struct_equalsySbAC_ACtFZTf4nnd_n
// address: 0x100202e7c
// body: available
// range: 0x100202e7c-0x100202f27 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


bool __s10CaptureLib0A4LensV23__derived_struct_equalsySbAC_ACtFZTf4nnd_n
               (ulong *param_1,ulong *param_2)

{
  ulong uVar1;
  undefined8 uVar2;
  ulong uVar3;
  
  uVar1 = *param_1;
  if ((uVar1 == *param_2 && param_1[1] == param_2[1]) ||
     (__ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF(),
     (uVar1 & 1) != 0)) {
    uVar1 = param_1[2];
    uVar3 = param_2[2];
    uVar2 = 0;
    __sSo8NSObjectCMa(0);
    __sSo8NSObjectC10ObjectiveCE2eeoiySbAB_ABtFZ(uVar1,uVar3,uVar2);
    if (((uVar1 & 1) != 0) &&
       ((*(float *)(param_1 + 3) == *(float *)(param_2 + 3) &&
        (*(float *)((long)param_1 + 0x1c) == *(float *)((long)param_2 + 0x1c))))) {
      return (char)param_1[4] == (char)param_2[4];
    }
  }
  return false;
}

