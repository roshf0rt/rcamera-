// rea decompile_all
// name: _$s10CaptureLib20CameraEffectExecutorC23didFinishVideoRecordingyyFytSgyYacfU_TY0_
// address: 0x1002021c0
// body: available
// range: 0x1002021c0-0x10020224b inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100202228 to 0x100201164 _$s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKF (external=false, thunk=false, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib20CameraEffectExecutorC23didFinishVideoRecordingyyFytSgyYacfU_TY0_(void)

{
  long lVar1;
  long *plVar2;
  long unaff_x22;
  
  lVar1 = *(long *)(unaff_x22 + 0x18) + 0x10;
  _swift_weakLoadStrong();
  *(long *)(unaff_x22 + 0x20) = lVar1;
  if (lVar1 != 0) {
    plVar2 = (long *)0x200;
    _swift_task_alloc();
    *(long **)(unaff_x22 + 0x28) = plVar2;
    *plVar2 = unaff_x22;
    plVar2[1] = (long)
                __s10CaptureLib20CameraEffectExecutorC23didFinishVideoRecordingyyFytSgyYacfU_TQ1_;
    __s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKF(5,0,0,0xc0);
    return;
  }
  **(undefined1 **)(unaff_x22 + 0x10) = 1;
                    /* WARNING: Could not recover jumptable at 0x000100202248. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (**(code **)(unaff_x22 + 8))();
  return;
}

