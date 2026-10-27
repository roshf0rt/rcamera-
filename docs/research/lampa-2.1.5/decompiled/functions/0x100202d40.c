// rea decompile_all
// name: _$s10CaptureLib0A4LensV4hash4intoys6HasherVz_tF
// address: 0x100202d40
// body: available
// range: 0x100202d40-0x100202dbb inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib0A4LensV4hash4intoys6HasherVz_tF(undefined8 param_1)

{
  undefined8 *unaff_x20;
  float fVar1;
  
  __sSS4hash4intoys6HasherVz_tF(param_1,*unaff_x20,unaff_x20[1]);
  __sSo8NSObjectC10ObjectiveCE4hash4intoys6HasherVz_tF(param_1);
  fVar1 = 0.0;
  if (*(float *)(unaff_x20 + 3) != 0.0) {
    fVar1 = *(float *)(unaff_x20 + 3);
  }
  __ss6HasherV8_combineyys6UInt32VF(fVar1);
  fVar1 = 0.0;
  if (*(float *)((long)unaff_x20 + 0x1c) != 0.0) {
    fVar1 = *(float *)((long)unaff_x20 + 0x1c);
  }
  __ss6HasherV8_combineyys6UInt32VF(fVar1);
  __ss6HasherV8_combineyySuF(*(undefined1 *)(unaff_x20 + 4));
  return;
}

