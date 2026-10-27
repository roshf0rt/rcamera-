// rea decompile_all
// name: _$s10CaptureLib18CameraStateMachineC13observeStatesScSyAC0D0OGyFyScS12ContinuationVyAF_GXEfU_
// address: 0x100200564
// body: available
// range: 0x100200564-0x1002007c3 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib18CameraStateMachineC13observeStatesScSyAC0D0OGyFyScS12ContinuationVyAF_GXEfU_
               (undefined8 param_1,long param_2)

{
  bool bVar1;
  undefined *puVar2;
  undefined *puVar3;
  long lVar4;
  long extraout_x8;
  long extraout_x8_00;
  long extraout_x8_01;
  long extraout_x12;
  long lVar5;
  undefined1 *puVar6;
  long lVar7;
  long lVar8;
  long lVar9;
  code *pcVar10;
  undefined1 auStack_80 [8];
  undefined4 local_78 [6];
  
  puVar2 = &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMd,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMR);
  lVar9 = *(long *)(puVar2 + -8);
  (*(code *)PTR____chkstk_darwin_10055a820)(*(long *)(lVar9 + 0x40) + 0xfU & 0xfffffffffffffff0);
  puVar6 = auStack_80 + -extraout_x8;
  puVar3 = &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd,
             &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMR);
  (*(code *)PTR____chkstk_darwin_10055a820)
            (*(long *)(*(long *)(puVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  lVar5 = (long)puVar6 - extraout_x8_00;
  puVar3 = &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
  (*(code *)PTR____chkstk_darwin_10055a820)(*(undefined8 *)(*(long *)(puVar3 + -8) + 0x40));
  lVar7 = lVar5 - (extraout_x8_01 + 0xfU & 0xfffffffffffffff0);
  (*(code *)PTR____chkstk_darwin_10055a820)();
  lVar8 = lVar7 - extraout_x12;
  pcVar10 = *(code **)(lVar9 + 0x10);
  (*pcVar10)(lVar8,param_1,puVar2);
  (**(code **)(lVar9 + 0x38))(lVar8,0,1,puVar2);
  lVar4 = _TtC10CaptureLib18CameraStateMachine::continuation;
  _swift_beginAccess(param_2 + _TtC10CaptureLib18CameraStateMachine::continuation,local_78,0x21,0);
  __sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgWOd(lVar8,param_2 + lVar4);
  _swift_endAccess(local_78);
  __sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgWOc(param_2 + lVar4,lVar7);
  lVar4 = lVar7;
  (**(code **)(lVar9 + 0x30))(lVar7,1,puVar2);
  bVar1 = (int)lVar4 == 0;
  if (bVar1) {
    (*pcVar10)(puVar6,lVar7,puVar2);
    __s10Foundation4DateVSg_ADtWOhTm
              (lVar7,&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
               &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
    local_78[0] = *(undefined4 *)(param_2 + 0x70);
    __sScS12ContinuationV5yieldyAB11YieldResultOyx__GxnF(lVar5,local_78,puVar2);
    (**(code **)(lVar9 + 8))(puVar6,puVar2);
  }
  else {
    __s10Foundation4DateVSg_ADtWOhTm
              (lVar7,&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
               &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
  }
  puVar2 = &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMd,
             &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMR);
  (**(code **)(*(long *)(puVar2 + -8) + 0x38))(lVar5,!bVar1,1,puVar2);
  __s10Foundation4DateVSg_ADtWOhTm
            (lVar5,&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd
             ,&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMR);
  return;
}

