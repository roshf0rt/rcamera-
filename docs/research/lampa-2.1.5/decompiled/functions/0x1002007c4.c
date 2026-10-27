// rea decompile_all
// name: _$s10CaptureLib18CameraStateMachineC10transition5eventSayAC6EffectOGAC5EventO_tKF
// address: 0x1002007c4
// body: available
// range: 0x1002007c4-0x100200deb inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


/* WARNING: Function: _objc_retain_x22 replaced with injection: _objc_retain_fixup */

void __s10CaptureLib18CameraStateMachineC10transition5eventSayAC6EffectOGAC5EventO_tKF
               (ulong param_1,ulong param_2,ulong param_3,uint param_4)

{
  byte bVar1;
  byte bVar2;
  uint3 uVar3;
  ulong *puVar4;
  undefined *puVar5;
  uint uVar6;
  long unaff_x20;
  uint uVar7;
  ulong local_90;
  ulong uStack_88;
  ulong local_80;
  byte local_78;
  ulong local_70;
  ulong uStack_68;
  
  puVar4 = (ulong *)&__ss23_ContiguousArrayStorageCyypGMd;
  ___swift_instantiateConcreteTypeFromMangledNameV2
            (&__ss23_ContiguousArrayStorageCyypGMd,&__ss23_ContiguousArrayStorageCyypGMR);
  _swift_allocObject();
  puVar4[3] = 2;
  puVar4[2] = 1;
  local_90 = 0;
  uStack_88 = 0xe000000000000000;
  __ss11_StringGutsV4growyySiF(0x1f);
  local_70 = local_90;
  uStack_68 = uStack_88;
  __sSS6appendyySSF(0x100000000000001d,0x80000001004a7d50);
  bVar2 = (byte)param_4;
  local_90 = param_1;
  uStack_88 = param_2;
  local_80 = param_3;
  local_78 = bVar2;
  __ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF
            (&local_90,&local_70,&__s10CaptureLib18CameraStateMachineC5EventON,
             PTR___ss26DefaultStringInterpolationVN_10055c398,
             PTR___ss26DefaultStringInterpolationVs16TextOutputStreamsWP_10055c3a8);
  puVar4[7] = (ulong)PTR___sSSN_10055bb18;
  puVar4[4] = local_70;
  puVar4[5] = uStack_68;
  __ss5print_9separator10terminatoryypd_S2StF(puVar4,0x20,0xe100000000000000,10,0xe100000000000000);
  _swift_release();
  uVar6 = param_4 >> 6 & 3;
  uVar7 = (uint)param_1;
  if (uVar6 < 2) {
    if (uVar6 != 0) {
      uVar3 = *(uint3 *)(unaff_x20 + 0x70);
      uVar6 = (uint)uVar3;
      bVar1 = *(byte *)(unaff_x20 + 0x73);
      if (bVar1 < 2) {
        uVar6 = uVar6 | 0x3000000;
LAB_100200afc:
        __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                  (uVar6);
        puVar5 = &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd;
        ___swift_instantiateConcreteTypeFromMangledNameV2
                  (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                   &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
        _swift_allocObject();
        *(undefined8 *)(puVar5 + 0x18) = 2;
        *(undefined8 *)(puVar5 + 0x10) = 1;
        *(ulong *)(puVar5 + 0x20) = param_1;
        *(ulong *)(puVar5 + 0x28) = param_2 & 0xffffffff;
        *(ulong *)(puVar5 + 0x30) = param_3;
        puVar5[0x38] = bVar2 & 0x3f | 0x80;
        return;
      }
      if ((bVar1 != 2) && (bVar1 != 3)) {
        if (uVar6 - 1 < 2) {
          __s10CaptureLib17StateMachineErrorOACs0E0AAWl();
          _swift_allocError(&__s10CaptureLib17StateMachineErrorON,puVar4,0,0);
          *puVar4 = param_1;
          puVar4[1] = param_2;
          puVar4[2] = param_3;
          *(byte *)(puVar4 + 3) = bVar2;
          *(char *)((long)puVar4 + 0x1b) = (char)(uVar3 >> 0x10);
          *(short *)((long)puVar4 + 0x19) = (short)uVar3;
          *(undefined1 *)((long)puVar4 + 0x1c) = 4;
          goto LAB_100200cb4;
        }
        if (uVar6 != 0) {
          uVar6 = 0x4000000;
          goto LAB_100200afc;
        }
      }
      puVar5 = &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd;
      ___swift_instantiateConcreteTypeFromMangledNameV2
                (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                 &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
      _swift_allocObject();
      *(undefined8 *)(puVar5 + 0x18) = 2;
      *(undefined8 *)(puVar5 + 0x10) = 1;
      *(ulong *)(puVar5 + 0x20) = param_1;
      *(ulong *)(puVar5 + 0x28) = param_2 & 0xffffffff;
      *(ulong *)(puVar5 + 0x30) = param_3;
      puVar5[0x38] = bVar2 & 0x3f | 0x80;
      return;
    }
    uVar3 = *(uint3 *)(unaff_x20 + 0x70);
    uVar6 = (uint)uVar3;
    bVar1 = *(byte *)(unaff_x20 + 0x73);
    if (bVar1 < 2) {
      if ((uVar6 & 0xff00) == 0x200) {
        if ((uVar7 & 0xff00) == 0x200) {
          return;
        }
      }
      else if (((((uVar7 & 0xff00) != 0x200) && ((ulong)(uVar6 & 0xff) == (param_1 & 0xff))) &&
               ((param_1 >> 8 & 0xff) == (ulong)(uVar3 >> 8 & 0xff))) &&
              ((param_1 >> 0x10 & 0xff) == (ulong)(uVar3 >> 0x10))) {
        return;
      }
LAB_100200cc8:
      __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                (uVar7 & 0xffffff | 0x1000000);
      puVar5 = &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd;
      ___swift_instantiateConcreteTypeFromMangledNameV2
                (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                 &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
      _swift_allocObject();
      *(undefined8 *)(puVar5 + 0x18) = 2;
      *(undefined8 *)(puVar5 + 0x10) = 1;
      *(undefined8 *)(puVar5 + 0x28) = 0;
      *(undefined8 *)(puVar5 + 0x30) = 0;
      *(ulong *)(puVar5 + 0x20) = param_1 & 0xffffffff00ffffff;
      puVar5[0x38] = 0;
      return;
    }
    if ((bVar1 == 2) || (bVar1 == 3)) goto LAB_100200cc8;
    if (uVar6 < 2) {
      if (uVar6 == 0) goto LAB_100200cc8;
    }
    else if (uVar6 == 2) goto LAB_100200cc8;
    __s10CaptureLib17StateMachineErrorOACs0E0AAWl();
    _swift_allocError(&__s10CaptureLib17StateMachineErrorON,puVar4,0,0);
    *puVar4 = param_1;
    puVar4[1] = param_2;
    puVar4[2] = param_3;
    *(byte *)(puVar4 + 3) = bVar2;
    *(char *)((long)puVar4 + 0x1b) = (char)(uVar3 >> 0x10);
    *(short *)((long)puVar4 + 0x19) = (short)uVar3;
    *(undefined1 *)((long)puVar4 + 0x1c) = 4;
  }
  else {
    if (uVar6 == 2) {
      __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                (uVar7 & 0xffffff | 0x2000000);
      puVar5 = &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd;
      ___swift_instantiateConcreteTypeFromMangledNameV2
                (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                 &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
      _swift_allocObject();
      *(undefined8 *)(puVar5 + 0x18) = 2;
      *(undefined8 *)(puVar5 + 0x10) = 1;
      *(undefined8 *)(puVar5 + 0x28) = 0;
      *(undefined8 *)(puVar5 + 0x30) = 0;
      *(ulong *)(puVar5 + 0x20) = param_1 & 0xffffff;
      puVar5[0x38] = 0x40;
      return;
    }
    if (((param_3 == 0 && param_2 == 0) && param_1 == 0) && ((param_4 & 0xff) == 0xc0)) {
      uVar6 = (uint)*(uint3 *)(unaff_x20 + 0x70);
      bVar2 = *(byte *)(unaff_x20 + 0x73);
      if (((1 << (ulong)(bVar2 & 0x1f) & 0xbU) != 0) && ((uVar6 & 0xff00) != 0x200)) {
        __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                  (0x4000001);
        ___swift_instantiateConcreteTypeFromMangledNameV2
                  (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                   &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
LAB_100200c64:
        _swift_initStaticObject();
        return;
      }
      __s10CaptureLib17StateMachineErrorOACs0E0AAWl();
      _swift_allocError(&__s10CaptureLib17StateMachineErrorON,puVar4,0,0);
      puVar4[2] = 0;
      *puVar4 = 0;
    }
    else {
      if (((param_4 & 0xff) != 0xc0) || ((param_1 != 1 || (param_3 != 0 || param_2 != 0)))) {
        if (((param_4 & 0xff) == 0xc0) && ((param_1 == 2 && (param_3 == 0 && param_2 == 0)))) {
          return;
        }
        if ((((param_4 & 0xff) == 0xc0) && (param_1 == 3)) && (param_3 == 0 && param_2 == 0)) {
          uVar6 = (uint)*(uint3 *)(unaff_x20 + 0x70);
          bVar2 = *(byte *)(unaff_x20 + 0x73);
          if (bVar2 < 2) {
            if (bVar2 == 0) {
              return;
            }
            goto LAB_100200db8;
          }
          if ((bVar2 == 2) || (bVar2 == 3)) goto LAB_100200db8;
          if (uVar6 != 0) {
            return;
          }
        }
        else if ((((param_4 & 0xff) != 0xc0) || (param_1 != 4)) || (param_3 != 0 || param_2 != 0)) {
          if (*(byte *)(unaff_x20 + 0x73) < 4) {
            return;
          }
          if (*(int3 *)(unaff_x20 + 0x70) == 0) {
            return;
          }
          __s10CaptureLib0A4ModeO04lastC0ACyFZTf4d_n();
          uVar6 = (uint)puVar4 & 0xffffff;
          goto LAB_100200db8;
        }
        uVar6 = 0x4000003;
LAB_100200db8:
        __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                  (uVar6);
        return;
      }
      uVar6 = (uint)*(uint3 *)(unaff_x20 + 0x70);
      bVar2 = *(byte *)(unaff_x20 + 0x73);
      if ((bVar2 == 4) && (uVar6 == 3)) {
        __s10CaptureLib18CameraStateMachineC03setD033_E04B6484BE9B2243961B97F9CF2069C2LLyyAC0D0OF
                  (0x4000002);
        ___swift_instantiateConcreteTypeFromMangledNameV2
                  (&__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMd,
                   &__ss23_ContiguousArrayStorageCy10CaptureLib18CameraStateMachineC6EffectOGMR);
        goto LAB_100200c64;
      }
      __s10CaptureLib17StateMachineErrorOACs0E0AAWl();
      _swift_allocError(&__s10CaptureLib17StateMachineErrorON,puVar4,0,0);
      puVar4[2] = 0;
      *puVar4 = 1;
    }
    puVar4[1] = 0;
    *(undefined1 *)(puVar4 + 3) = 0xc0;
    *(char *)((long)puVar4 + 0x1b) = (char)(uVar6 >> 0x10);
    *(short *)((long)puVar4 + 0x19) = (short)uVar6;
    *(byte *)((long)puVar4 + 0x1c) = bVar2;
  }
LAB_100200cb4:
  _swift_willThrow();
  return;
}

