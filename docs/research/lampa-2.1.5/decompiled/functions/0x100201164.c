// rea decompile_all
// name: _$s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKF
// address: 0x100201164
// body: available
// range: 0x100201164-0x1002011f3 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x1002011f0 to 0x10040ecbc _swift_task_switch (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKF
               (undefined8 param_1,undefined8 param_2,undefined8 param_3,undefined1 param_4)

{
  long lVar1;
  ulong uVar2;
  undefined8 unaff_x20;
  long unaff_x22;
  
  *(undefined1 *)(unaff_x22 + 0x13c) = param_4;
  *(undefined8 *)(unaff_x22 + 0x1a0) = param_3;
  *(undefined8 *)(unaff_x22 + 0x1a8) = unaff_x20;
  *(undefined8 *)(unaff_x22 + 400) = param_1;
  *(undefined8 *)(unaff_x22 + 0x198) = param_2;
  lVar1 = 0;
  __s8Dispatch0A13WorkItemFlagsVMa();
  *(long *)(unaff_x22 + 0x1b0) = lVar1;
  lVar1 = *(long *)(lVar1 + -8);
  *(long *)(unaff_x22 + 0x1b8) = lVar1;
  uVar2 = *(long *)(lVar1 + 0x40) + 0xfU & 0xfffffffffffffff0;
  _swift_task_alloc();
  *(ulong *)(unaff_x22 + 0x1c0) = uVar2;
  lVar1 = 0;
  __s8Dispatch0A3QoSVMa();
  *(long *)(unaff_x22 + 0x1c8) = lVar1;
  lVar1 = *(long *)(lVar1 + -8);
  *(long *)(unaff_x22 + 0x1d0) = lVar1;
  uVar2 = *(long *)(lVar1 + 0x40) + 0xfU & 0xfffffffffffffff0;
  _swift_task_alloc();
  *(ulong *)(unaff_x22 + 0x1d8) = uVar2;
  _swift_task_switch(__s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY0_
                     ,0,0);
  return;
}

