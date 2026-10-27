// rea decompile_all
// name: _$s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY2_
// address: 0x10020129c
// body: available
// range: 0x10020129c-0x100201dc3 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib22CameraStateCoordinatorC6handle5eventyAA0cD7MachineC5EventO_tYaKFTY2_(void)

{
  long lVar1;
  long lVar2;
  byte bVar3;
  undefined1 uVar4;
  byte bVar5;
  undefined8 *puVar6;
  undefined *puVar7;
  undefined *puVar8;
  void *pvVar9;
  undefined *puVar10;
  undefined *puVar11;
  undefined *puVar12;
  undefined *puVar13;
  code *UNRECOVERED_JUMPTABLE;
  undefined8 *puVar14;
  long *plVar15;
  ulong uVar16;
  long lVar17;
  long lVar18;
  long lVar19;
  long lVar20;
  undefined8 uVar21;
  undefined8 uVar22;
  undefined8 uVar23;
  undefined8 uVar24;
  long lVar25;
  undefined8 uVar26;
  long lVar27;
  long unaff_x22;
  ulong uVar28;
  long lVar29;
  byte *pbVar30;
  undefined4 uVar31;
  long local_100;
  
  lVar25 = *(long *)(unaff_x22 + 0x1e8);
  uVar16 = *(ulong *)(lVar25 + 0x10);
  if (uVar16 != 0) {
    uVar28 = 0;
    pbVar30 = (byte *)(lVar25 + 0x38);
    lVar20 = *(long *)(unaff_x22 + 0x1d0);
    lVar17 = *(long *)(unaff_x22 + 0x1b8);
    lVar18 = *(long *)(*(long *)(unaff_x22 + 0x1a8) + 0x18);
    local_100 = *(long *)(unaff_x22 + 0x1f0);
    do {
      if (*(ulong *)(lVar25 + 0x10) <= uVar28) {
                    /* WARNING: Does not return */
        UNRECOVERED_JUMPTABLE = (code *)SoftwareBreakpoint(1,0x100201dc4);
        (*UNRECOVERED_JUMPTABLE)();
      }
      lVar1 = *(long *)(pbVar30 + -0x18);
      lVar2 = *(long *)(pbVar30 + -0x10);
      lVar29 = *(long *)(pbVar30 + -8);
      bVar3 = *pbVar30;
      __s10CaptureLib18CameraStateMachineC6EffectOWOy(lVar1,lVar2,lVar29,bVar3);
      bVar5 = bVar3 >> 6;
      if (bVar5 < 2) {
        uVar4 = (undefined1)((ulong)lVar1 >> 0x10);
        if (bVar5 == 0) {
          lVar27 = *(long *)(lVar18 + 0x18);
          puVar7 = &DAT_100574ab8;
          puVar14 = (undefined8 *)&DAT_00000024;
          _swift_allocObject(&DAT_100574ab8,0x24,7);
          uVar26 = *(undefined8 *)
                    (lVar27 + _TtC10CaptureLib18CaptureServiceImpl::_currentSessionConfig);
          _swift_retain(uVar26);
          __s7Helpers10ThreadSafeC12wrappedValuexvg(unaff_x22 + 0x158);
          _swift_release(uVar26);
          lVar19 = *(long *)(unaff_x22 + 0x160);
          if (lVar19 == 0) {
            _swift_deallocUninitializedObject(puVar7,0x24,7);
          }
          else {
            uVar26 = *(undefined8 *)(unaff_x22 + 0x158);
            uVar31 = *(undefined4 *)(unaff_x22 + 0x168);
            uVar23 = *(undefined8 *)(unaff_x22 + 0x1d8);
            uVar21 = *(undefined8 *)(unaff_x22 + 0x1c8);
            uVar22 = *(undefined8 *)(unaff_x22 + 0x1c0);
            uVar24 = *(undefined8 *)(unaff_x22 + 0x1b0);
            *(short *)(puVar7 + 0x10) = (short)uVar26;
            puVar7[0x12] = (char)((ulong)uVar26 >> 0x10);
            *(long *)(puVar7 + 0x18) = lVar19;
            *(undefined4 *)(puVar7 + 0x20) = uVar31;
            uVar26 = *(undefined8 *)
                      (lVar27 + _TtC10CaptureLib18CaptureServiceImpl::_pendingNativeZoomFactor);
            _swift_retain(uVar26);
            UNRECOVERED_JUMPTABLE = (code *)(unaff_x22 + 0xf0);
            __s7Helpers10ThreadSafeC12wrappedValuexvM();
            *puVar14 = 0x3ff0000000000000;
            (*UNRECOVERED_JUMPTABLE)(unaff_x22 + 0xf0,0);
            _swift_release(uVar26);
            puVar8 = &DAT_100574bf8;
            _swift_allocObject(&DAT_100574bf8,0x20,7);
            *(undefined **)(puVar8 + 0x10) = puVar7;
            puVar8[0x1a] = uVar4;
            *(short *)(puVar8 + 0x18) = (short)lVar1;
            *(int *)(puVar8 + 0x1c) = (int)((ulong)lVar1 >> 0x20);
            puVar10 = &DAT_100574b08;
            _swift_allocObject(&DAT_100574b08,0x18,7);
            _swift_unknownObjectWeakInit(puVar10 + 0x10,lVar27);
            puVar11 = &DAT_100574c20;
            _swift_allocObject(&DAT_100574c20,0x28,7);
            *(code **)(puVar11 + 0x10) =
                 __s10CaptureLib0A11ServiceImplC06switchA4Mode2to7evShiftyAA0aF0O_SftYaKFAA0A13SessionConfigVycfU_TA
            ;
            *(undefined **)(puVar11 + 0x18) = puVar8;
            *(undefined **)(puVar11 + 0x20) = puVar10;
            *(code **)(unaff_x22 + 0xc0) =
                 __s10CaptureLib0A11ServiceImplC23scheduleReconfiguration33_E7DAB43E3ECD2C6E2A33D560465B5A46LL20sessionConfigChangesyAA0a7SessionR0Vyc_tFyyYbcfU_TA_38
            ;
            *(undefined **)(unaff_x22 + 200) = puVar11;
            *(undefined **)(unaff_x22 + 0xa0) = PTR___NSConcreteStackBlock_10055a808;
            *(undefined8 *)(unaff_x22 + 0xa8) = 0x42000000;
            *(code **)(unaff_x22 + 0xb0) = __sIegh_IeyBh_TR;
            *(undefined **)(unaff_x22 + 0xb8) = &_block_descriptor_41;
            pvVar9 = __Block_copy((void *)(unaff_x22 + 0xa0));
            _swift_retain(puVar7);
            _swift_retain(puVar8);
            puVar12 = puVar10;
            _swift_retain(puVar10);
            __s8Dispatch0A3QoSV11unspecifiedACvgZ(uVar23);
            *(undefined **)(unaff_x22 + 0x188) = PTR___swiftEmptyArrayStorage_10055c778;
            __s8Dispatch0A13WorkItemFlagsVACs10SetAlgebraAAWl();
            puVar11 = &__sSay8Dispatch0A13WorkItemFlagsVGMd;
            ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&__sSay8Dispatch0A13WorkItemFlagsVGMd,&__sSay8Dispatch0A13WorkItemFlagsVGMR);
            puVar13 = puVar11;
            __sSay8Dispatch0A13WorkItemFlagsVGSayxGSTsWl();
            __ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj
                      (uVar22,unaff_x22 + 0x188,puVar11,puVar13,uVar24,puVar12);
            __sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF
                      (0,uVar23,uVar22,pvVar9);
            __Block_release(pvVar9);
            _swift_release(puVar8);
            (**(code **)(lVar17 + 8))(uVar22,uVar24);
            (**(code **)(lVar20 + 8))(uVar23,uVar21);
            _swift_release(*(undefined8 *)(unaff_x22 + 200));
            _swift_release(puVar10);
            _swift_release(puVar7);
          }
        }
        else {
          lVar27 = *(long *)(lVar18 + 0x18);
          puVar7 = &DAT_100574ab8;
          _swift_allocObject(&DAT_100574ab8,0x24,7);
          uVar26 = *(undefined8 *)
                    (lVar27 + _TtC10CaptureLib18CaptureServiceImpl::_currentSessionConfig);
          _swift_retain(uVar26);
          __s7Helpers10ThreadSafeC12wrappedValuexvg(unaff_x22 + 0x140);
          _swift_release(uVar26);
          lVar19 = *(long *)(unaff_x22 + 0x148);
          if (lVar19 == 0) {
            _swift_deallocUninitializedObject(puVar7,0x24,7);
          }
          else {
            uVar22 = *(undefined8 *)(unaff_x22 + 0x140);
            uVar31 = *(undefined4 *)(unaff_x22 + 0x150);
            uVar24 = *(undefined8 *)(unaff_x22 + 0x1d8);
            uVar26 = *(undefined8 *)(unaff_x22 + 0x1c0);
            uVar21 = *(undefined8 *)(unaff_x22 + 0x1c8);
            uVar23 = *(undefined8 *)(unaff_x22 + 0x1b0);
            *(short *)(puVar7 + 0x10) = (short)uVar22;
            puVar7[0x12] = (char)((ulong)uVar22 >> 0x10);
            *(long *)(puVar7 + 0x18) = lVar19;
            *(undefined4 *)(puVar7 + 0x20) = uVar31;
            puVar8 = &DAT_100574b80;
            _swift_allocObject(&DAT_100574b80,0x1b,7);
            *(undefined **)(puVar8 + 0x10) = puVar7;
            puVar8[0x18] = (char)lVar1;
            puVar8[0x19] = (char)((ulong)lVar1 >> 8);
            puVar8[0x1a] = uVar4;
            puVar10 = &DAT_100574b08;
            _swift_allocObject(&DAT_100574b08,0x18,7);
            _swift_unknownObjectWeakInit(puVar10 + 0x10,lVar27);
            puVar11 = &DAT_100574ba8;
            _swift_allocObject(&DAT_100574ba8,0x28,7);
            *(code **)(puVar11 + 0x10) =
                 __s10CaptureLib0A11ServiceImplC24updateVideoConfigurationyyAA0fG0VFAA0A13SessionConfigVycfU_TA
            ;
            *(undefined **)(puVar11 + 0x18) = puVar8;
            *(undefined **)(puVar11 + 0x20) = puVar10;
            *(code **)(unaff_x22 + 0x90) =
                 __s10CaptureLib0A11ServiceImplC23scheduleReconfiguration33_E7DAB43E3ECD2C6E2A33D560465B5A46LL20sessionConfigChangesyAA0a7SessionR0Vyc_tFyyYbcfU_TA_38
            ;
            *(undefined **)(unaff_x22 + 0x98) = puVar11;
            *(undefined **)(unaff_x22 + 0x70) = PTR___NSConcreteStackBlock_10055a808;
            *(undefined8 *)(unaff_x22 + 0x78) = 0x42000000;
            *(code **)(unaff_x22 + 0x80) = __sIegh_IeyBh_TR;
            *(undefined **)(unaff_x22 + 0x88) = &_block_descriptor_29;
            pvVar9 = __Block_copy((void *)(unaff_x22 + 0x70));
            _swift_retain(puVar7);
            _swift_retain(puVar8);
            puVar12 = puVar10;
            _swift_retain(puVar10);
            __s8Dispatch0A3QoSV11unspecifiedACvgZ(uVar24);
            *(undefined **)(unaff_x22 + 0x180) = PTR___swiftEmptyArrayStorage_10055c778;
            __s8Dispatch0A13WorkItemFlagsVACs10SetAlgebraAAWl();
            puVar11 = &__sSay8Dispatch0A13WorkItemFlagsVGMd;
            ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&__sSay8Dispatch0A13WorkItemFlagsVGMd,&__sSay8Dispatch0A13WorkItemFlagsVGMR);
            puVar13 = puVar11;
            __sSay8Dispatch0A13WorkItemFlagsVGSayxGSTsWl();
            __ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj
                      (uVar26,unaff_x22 + 0x180,puVar11,puVar13,uVar23,puVar12);
            __sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF
                      (0,uVar24,uVar26,pvVar9);
            __Block_release(pvVar9);
            _swift_release(puVar8);
            (**(code **)(lVar17 + 8))(uVar26,uVar23);
            (**(code **)(lVar20 + 8))(uVar24,uVar21);
            _swift_release(*(undefined8 *)(unaff_x22 + 0x98));
            _swift_release(puVar10);
            _swift_release(puVar7);
          }
        }
      }
      else if (bVar5 == 2) {
        lVar27 = *(long *)(lVar18 + 0x18);
        puVar7 = &DAT_100574ab8;
        plVar15 = (long *)&DAT_00000024;
        _swift_allocObject(&DAT_100574ab8,0x24,7);
        uVar26 = *(undefined8 *)
                  (lVar27 + _TtC10CaptureLib18CaptureServiceImpl::_currentSessionConfig);
        _swift_retain(uVar26);
        __s7Helpers10ThreadSafeC12wrappedValuexvg(unaff_x22 + 0x128);
        _swift_release(uVar26);
        lVar19 = *(long *)(unaff_x22 + 0x130);
        if (lVar19 == 0) {
          _swift_deallocUninitializedObject(puVar7,0x24,7);
        }
        else {
          uVar26 = *(undefined8 *)(unaff_x22 + 0x128);
          uVar31 = *(undefined4 *)(unaff_x22 + 0x138);
          uVar24 = *(undefined8 *)(unaff_x22 + 0x1d8);
          uVar21 = *(undefined8 *)(unaff_x22 + 0x1c8);
          uVar22 = *(undefined8 *)(unaff_x22 + 0x1c0);
          uVar23 = *(undefined8 *)(unaff_x22 + 0x1b0);
          *(short *)(puVar7 + 0x10) = (short)uVar26;
          puVar7[0x12] = (char)((ulong)uVar26 >> 0x10);
          *(long *)(puVar7 + 0x18) = lVar19;
          *(undefined4 *)(puVar7 + 0x20) = uVar31;
          lVar19 = 0x3ff0000000000000;
          if ((bVar3 & 0x3f) != 1) {
            lVar19 = lVar29;
          }
          uVar26 = *(undefined8 *)
                    (lVar27 + _TtC10CaptureLib18CaptureServiceImpl::_pendingNativeZoomFactor);
          _swift_retain(uVar26);
          UNRECOVERED_JUMPTABLE = (code *)(unaff_x22 + 0xd0);
          __s7Helpers10ThreadSafeC12wrappedValuexvM();
          *plVar15 = lVar19;
          (*UNRECOVERED_JUMPTABLE)(unaff_x22 + 0xd0,0);
          _swift_release(uVar26);
          puVar8 = &DAT_100574ae0;
          _swift_allocObject(&DAT_100574ae0,0x24,7);
          *(undefined **)(puVar8 + 0x10) = puVar7;
          *(long *)(puVar8 + 0x18) = lVar1;
          *(int *)(puVar8 + 0x20) = (int)lVar2;
          puVar10 = &DAT_100574b08;
          _swift_allocObject(&DAT_100574b08,0x18,7);
          _swift_unknownObjectWeakInit(puVar10 + 0x10,lVar27);
          puVar11 = &DAT_100574b30;
          _swift_allocObject(&DAT_100574b30,0x28,7);
          *(code **)(puVar11 + 0x10) =
               __s10CaptureLib0A11ServiceImplC12switchDevice6device7evShift16pendingZoomScaleyAA0aF0V_Sf12CoreGraphics7CGFloatVSgtFAA0A13SessionConfigVycfU_TA
          ;
          *(undefined **)(puVar11 + 0x18) = puVar8;
          *(undefined **)(puVar11 + 0x20) = puVar10;
          *(code **)(unaff_x22 + 0x60) =
               __s10CaptureLib0A11ServiceImplC23scheduleReconfiguration33_E7DAB43E3ECD2C6E2A33D560465B5A46LL20sessionConfigChangesyAA0a7SessionR0Vyc_tFyyYbcfU_TA
          ;
          *(undefined **)(unaff_x22 + 0x68) = puVar11;
          *(undefined **)(unaff_x22 + 0x40) = PTR___NSConcreteStackBlock_10055a808;
          *(undefined8 *)(unaff_x22 + 0x48) = 0x42000000;
          *(code **)(unaff_x22 + 0x50) = __sIegh_IeyBh_TR;
          *(undefined **)(unaff_x22 + 0x58) = &_block_descriptor_17;
          pvVar9 = __Block_copy((void *)(unaff_x22 + 0x40));
          __s10CaptureLib18CameraStateMachineC6EffectOWOy(lVar1,lVar2,lVar29,bVar3);
          _swift_retain(puVar7);
          _swift_retain(puVar8);
          puVar12 = puVar10;
          _swift_retain(puVar10);
          __s8Dispatch0A3QoSV11unspecifiedACvgZ(uVar24);
          *(undefined **)(unaff_x22 + 0x178) = PTR___swiftEmptyArrayStorage_10055c778;
          __s8Dispatch0A13WorkItemFlagsVACs10SetAlgebraAAWl();
          puVar11 = &__sSay8Dispatch0A13WorkItemFlagsVGMd;
          ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__sSay8Dispatch0A13WorkItemFlagsVGMd,&__sSay8Dispatch0A13WorkItemFlagsVGMR);
          puVar13 = puVar11;
          __sSay8Dispatch0A13WorkItemFlagsVGSayxGSTsWl();
          __ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj
                    (uVar22,unaff_x22 + 0x178,puVar11,puVar13,uVar23,puVar12);
          __sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF
                    (0,uVar24,uVar22,pvVar9);
          __Block_release(pvVar9);
          _swift_release(puVar8);
          (**(code **)(lVar17 + 8))(uVar22,uVar23);
          (**(code **)(lVar20 + 8))(uVar24,uVar21);
          _swift_release(*(undefined8 *)(unaff_x22 + 0x68));
          _swift_release(puVar10);
          _swift_release(puVar7);
        }
      }
      else if ((bVar3 == 0xc0) && ((lVar29 == 0 && lVar2 == 0) && lVar1 == 0)) {
        __s10CaptureLib0A11ServiceImplC19startVideoRecordingyyKF();
        if (local_100 != 0) {
          _swift_bridgeObjectRelease(*(undefined8 *)(unaff_x22 + 0x1e8));
          uVar26 = *(undefined8 *)(unaff_x22 + 0x1c0);
          _swift_task_dealloc(*(undefined8 *)(unaff_x22 + 0x1d8));
          _swift_task_dealloc(uVar26);
          UNRECOVERED_JUMPTABLE = *(code **)(unaff_x22 + 8);
          goto LAB_100201d70;
        }
        local_100 = 0;
      }
      else {
        uVar22 = *(undefined8 *)(unaff_x22 + 0x1d8);
        uVar26 = *(undefined8 *)(unaff_x22 + 0x1c0);
        uVar21 = *(undefined8 *)(unaff_x22 + 0x1c8);
        uVar24 = *(undefined8 *)(unaff_x22 + 0x1b0);
        uVar23 = *(undefined8 *)
                  (*(long *)(lVar18 + 0x18) + _TtC10CaptureLib18CaptureServiceImpl::movieCapturer);
        puVar14 = (undefined8 *)&DAT_100574a68;
        _swift_allocObject(&DAT_100574a68,0x18,7);
        _swift_unknownObjectWeakInit(puVar14 + 2,uVar23);
        *(code **)(unaff_x22 + 0x30) = __s10CaptureLib13MovieCapturerC13stopRecordingyyFyyYbcfU_TA;
        *(undefined8 **)(unaff_x22 + 0x38) = puVar14;
        *(undefined **)(unaff_x22 + 0x10) = PTR___NSConcreteStackBlock_10055a808;
        *(undefined8 *)(unaff_x22 + 0x18) = 0x42000000;
        *(code **)(unaff_x22 + 0x20) = __sIegh_IeyBh_TR;
        *(undefined **)(unaff_x22 + 0x28) = &_block_descriptor;
        pvVar9 = __Block_copy((void *)(unaff_x22 + 0x10));
        puVar6 = puVar14;
        _swift_retain(puVar14);
        __s8Dispatch0A3QoSV11unspecifiedACvgZ(uVar22);
        *(undefined **)(unaff_x22 + 0x170) = PTR___swiftEmptyArrayStorage_10055c778;
        __s8Dispatch0A13WorkItemFlagsVACs10SetAlgebraAAWl();
        puVar7 = &__sSay8Dispatch0A13WorkItemFlagsVGMd;
        ___swift_instantiateConcreteTypeFromMangledNameV2
                  (&__sSay8Dispatch0A13WorkItemFlagsVGMd,&__sSay8Dispatch0A13WorkItemFlagsVGMR);
        puVar8 = puVar7;
        __sSay8Dispatch0A13WorkItemFlagsVGSayxGSTsWl();
        __ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj
                  (uVar26,unaff_x22 + 0x170,puVar7,puVar8,uVar24,puVar6);
        __sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF
                  (0,uVar22,uVar26,pvVar9);
        __Block_release(pvVar9);
        (**(code **)(lVar17 + 8))(uVar26,uVar24);
        (**(code **)(lVar20 + 8))(uVar22,uVar21);
        _swift_release(*(undefined8 *)(unaff_x22 + 0x38));
        _swift_release();
        __s7Helpers15OrientationToolC6sharedACvau();
        _swift_beginAccess();
        uVar26 = *puVar14;
        _swift_retain(uVar26);
        __s7Helpers15OrientationToolC13startTrackingyyF();
        _swift_release(uVar26);
      }
      uVar28 = uVar28 + 1;
      __s10CaptureLib18CameraStateMachineC6EffectOWOe(lVar1,lVar2,lVar29,bVar3);
      pbVar30 = pbVar30 + 0x20;
    } while (uVar16 != uVar28);
    lVar25 = *(long *)(unaff_x22 + 0x1e8);
  }
  _swift_bridgeObjectRelease(lVar25);
  uVar26 = *(undefined8 *)(unaff_x22 + 0x1c0);
  _swift_task_dealloc(*(undefined8 *)(unaff_x22 + 0x1d8));
  _swift_task_dealloc(uVar26);
  UNRECOVERED_JUMPTABLE = *(code **)(unaff_x22 + 8);
LAB_100201d70:
                    /* WARNING: Could not recover jumptable at 0x000100201d94. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (*UNRECOVERED_JUMPTABLE)();
  return;
}

