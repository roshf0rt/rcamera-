// rea decompile_all
// name: _$s10CaptureLib0A4LensV11focalLengthSivg
// address: 0x100202bd8
// body: available
// range: 0x100202bd8-0x100202c53 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib0A4LensV11focalLengthSivg(void)

{
  char cVar1;
  code *pcVar2;
  long lVar3;
  long unaff_x20;
  float fVar4;
  
  cVar1 = *(char *)(unaff_x20 + 0x20);
  lVar3 = *(long *)(unaff_x20 + 0x10);
  __s10CaptureLib0A6DeviceV11focalLengthSivg();
  if (cVar1 == '\x01') {
    fVar4 = *(float *)(unaff_x20 + 0x1c) * (float)lVar3;
    if (0x7f7fffff < (uint)ABS(fVar4)) {
                    /* WARNING: Does not return */
      pcVar2 = (code *)SoftwareBreakpoint(1,0x100202c4c);
      (*pcVar2)();
    }
    if (fVar4 <= -9.223373e+18) {
                    /* WARNING: Does not return */
      pcVar2 = (code *)SoftwareBreakpoint(1,0x100202c50);
      (*pcVar2)();
    }
    if (9.223372e+18 <= fVar4) {
                    /* WARNING: Does not return */
      pcVar2 = (code *)SoftwareBreakpoint(1,0x100202c54);
      (*pcVar2)();
    }
  }
  return;
}

