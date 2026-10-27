// rea decompile_all
// name: _$s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
// address: 0x100200dec
// body: available
// range: 0x100200dec-0x100201007 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
               (ulong param_1)

{
  bool bVar1;
  undefined *puVar2;
  undefined *puVar3;
  ulong uVar4;
  long lVar5;
  long extraout_x8;
  long extraout_x8_00;
  long extraout_x8_01;
  long unaff_x20;
  long lVar6;
  undefined1 *puVar7;
  long lVar8;
  long lVar9;
  undefined1 auStack_70 [4];
  undefined4 local_6c;
  undefined1 auStack_68 [24];
  
  puVar2 = &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMd,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GMR);
  lVar9 = *(long *)(puVar2 + -8);
  (*(code *)PTR____chkstk_darwin_10055a820)(*(long *)(lVar9 + 0x40) + 0xfU & 0xfffffffffffffff0);
  puVar7 = auStack_70 + -extraout_x8;
  puVar3 = &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
  (*(code *)PTR____chkstk_darwin_10055a820)
            (*(long *)(*(long *)(puVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  lVar8 = (long)puVar7 - extraout_x8_00;
  puVar3 = &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd,
             &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMR);
  (*(code *)PTR____chkstk_darwin_10055a820)
            (*(long *)(*(long *)(puVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  lVar6 = lVar8 - extraout_x8_01;
  uVar4 = param_1;
  __s10CaptureLib18CameraStateMachineC0D0O21__derived_enum_equalsySbAE_AEtFZTf4nnd_n
            (param_1,*(undefined4 *)(unaff_x20 + 0x70));
  if ((uVar4 & 1) == 0) {
    *(short *)(unaff_x20 + 0x70) = (short)param_1;
    *(char *)(unaff_x20 + 0x72) = (char)(param_1 >> 0x10);
    *(char *)(unaff_x20 + 0x73) = (char)(param_1 >> 0x18);
    lVar5 = _TtC10CaptureLib18CameraStateMachine::continuation;
    _swift_beginAccess(unaff_x20 + _TtC10CaptureLib18CameraStateMachine::continuation,auStack_68,0,0
                      );
    __sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgWOc(unaff_x20 + lVar5,lVar8);
    lVar5 = lVar8;
    (**(code **)(lVar9 + 0x30))(lVar8,1,puVar2);
    bVar1 = (int)lVar5 == 0;
    if (bVar1) {
      (**(code **)(lVar9 + 0x10))(puVar7,lVar8,puVar2);
      __s10Foundation4DateVSg_ADtWOhTm
                (lVar8,&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
                 &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
      local_6c = *(undefined4 *)(unaff_x20 + 0x70);
      __sScS12ContinuationV5yieldyAB11YieldResultOyx__GxnF(lVar6,&local_6c,puVar2);
      (**(code **)(lVar9 + 8))(puVar7,puVar2);
    }
    else {
      __s10Foundation4DateVSg_ADtWOhTm
                (lVar8,&__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
                 &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
    }
    puVar2 = &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMd;
    ___swift_instantiateConcreteTypeFromMangledNameV2
              (&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMd,
               &__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GMR);
    (**(code **)(*(long *)(puVar2 + -8) + 0x38))(lVar6,!bVar1,1,puVar2);
    __s10Foundation4DateVSg_ADtWOhTm
              (lVar6,&
                     __sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMd
               ,&__sScS12ContinuationV11YieldResultOy10CaptureLib18CameraStateMachineC0G0O__GSgMR);
  }
  return;
}

