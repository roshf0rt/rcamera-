// rea decompile_all
// name: _$s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY1_
// address: 0x100201210
// body: available
// range: 0x100201210-0x10020129b inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100201298 to 0x10040ecbc _swift_task_switch (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


/* WARNING: Removing unreachable block (ram,0x000100201248) */

void __s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY1_(void)

{
  undefined8 uVar1;
  long unaff_x22;
  
  uVar1 = *(undefined8 *)(unaff_x22 + 400);
  __s10CaptureLib18CameraStateMachineC10transition5eventSayAC6EffectOGAC5EventO_tKF
            (uVar1,*(undefined8 *)(unaff_x22 + 0x198),*(undefined8 *)(unaff_x22 + 0x1a0),
             *(undefined1 *)(unaff_x22 + 0x13c));
  *(undefined8 *)(unaff_x22 + 0x1e8) = uVar1;
  *(undefined8 *)(unaff_x22 + 0x1f0) = 0;
  _swift_task_switch(__s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY2_
                     ,0,0);
  return;
}

