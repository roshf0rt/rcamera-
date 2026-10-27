// rea decompile_all
// name: _$s10CaptureLib20CameraEffectExecutorC22didStartVideoRecordingyyFytSgyYacfU_TQ1_
// address: 0x100202110
// body: available
// range: 0x100202110-0x100202183 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100202180 to 0x10040ecbc _swift_task_switch (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib20CameraEffectExecutorC22didStartVideoRecordingyyFytSgyYacfU_TQ1_(void)

{
  code *pcVar1;
  long lVar2;
  undefined8 uVar3;
  long unaff_x20;
  long *unaff_x22;
  
  lVar2 = *unaff_x22;
  _swift_task_dealloc(*(undefined8 *)(lVar2 + 0x28));
  uVar3 = *(undefined8 *)(lVar2 + 0x20);
  if (unaff_x20 == 0) {
    _swift_release(uVar3);
    pcVar1 = __s10CaptureLib19CameraViewModelImplC07onFrontC3Tap10isSelectedySb_tFytSgyYacfU_TY1_;
  }
  else {
    _swift_errorRelease();
    _swift_release(uVar3);
    pcVar1 = __s10CaptureLib19CameraViewModelImplC07onFrontC3Tap10isSelectedySb_tFytSgyYacfU_TY2_;
  }
  _swift_task_switch(pcVar1,0,0);
  return;
}

