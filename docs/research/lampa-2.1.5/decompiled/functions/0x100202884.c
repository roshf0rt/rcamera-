// rea decompile_all
// name: _$s10CaptureLib17StateMachineErrorOwst
// address: 0x100202884
// body: available
// range: 0x100202884-0x1002028d7 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib17StateMachineErrorOwst(ulong *param_1,uint param_2,int param_3)

{
  if ((int)param_2 < 0) {
    param_1[1] = 0;
    param_1[2] = 0;
    *(undefined1 *)((long)param_1 + 0x1c) = 0;
    *(undefined4 *)(param_1 + 3) = 0;
    *param_1 = (ulong)(param_2 & 0x7fffffff);
    if (param_3 < 0) {
      *(undefined1 *)((long)param_1 + 0x1d) = 1;
      return;
    }
  }
  else {
    if (param_3 < 0) {
      *(undefined1 *)((long)param_1 + 0x1d) = 0;
    }
    if (param_2 != 0) {
      *param_1 = 0;
      param_1[1] = (ulong)-param_2 << 0x20;
      param_1[2] = 0;
      *(undefined1 *)(param_1 + 3) = 0;
      return;
    }
  }
  return;
}

