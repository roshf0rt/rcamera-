// rea decompile_all
// name: _$sSh21_nonEmptyArrayLiteralShyxGSayxG_tcfCSo16NSURLResourceKeya_Tt0g5Tf4g_n
// address: 0x100200098
// body: available
// range: 0x100200098-0x100200287 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


/* WARNING: Function: _objc_retain_x23 replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_release_x8 replaced with injection: _objc_release_fixup */

undefined *
__sSh21_nonEmptyArrayLiteralShyxGSayxG_tcfCSo16NSURLResourceKeya_Tt0g5Tf4g_n(long param_1)

{
  code *pcVar1;
  undefined *puVar2;
  undefined *puVar3;
  undefined1 *puVar4;
  undefined *puVar5;
  undefined *puVar6;
  undefined *puVar7;
  ulong uVar8;
  ulong uVar9;
  ulong uVar10;
  ulong uVar11;
  undefined8 uVar12;
  undefined *puVar13;
  undefined *puVar14;
  undefined *puVar15;
  ulong uVar16;
  undefined1 auStack_a8 [72];
  
  puVar13 = *(undefined **)(param_1 + 0x10);
  puVar2 = PTR___swiftEmptySetSingleton_10055c788;
  if (puVar13 != (undefined *)0x0) {
    puVar6 = &__ss11_SetStorageCySo16NSURLResourceKeyaGMR;
    ___swift_instantiateConcreteTypeFromMangledNameV2
              (&__ss11_SetStorageCySo16NSURLResourceKeyaGMd,
               &__ss11_SetStorageCySo16NSURLResourceKeyaGMR);
    puVar2 = puVar13;
    __ss11_SetStorageC8allocate8capacityAByxGSi_tFZ();
    puVar15 = (undefined *)0x0;
    do {
      puVar14 = *(undefined **)(param_1 + 0x20 + (long)puVar15 * 8);
      uVar12 = *(undefined8 *)(puVar2 + 0x28);
      puVar3 = puVar14;
      __sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ();
      __ss6HasherV5_seedABSi_tcfC(auStack_a8);
      puVar4 = auStack_a8;
      __sSS4hash4intoys6HasherVz_tF(puVar4,puVar3,puVar6);
      __ss6HasherV9_finalizeSiyF();
      _swift_bridgeObjectRelease(puVar6);
      uVar11 = -1L << ((ulong)(byte)puVar2[0x20] & 0x3f);
      uVar16 = (ulong)puVar4 & (uVar11 ^ 0xffffffffffffffff);
      uVar8 = uVar16 >> 6;
      uVar9 = *(ulong *)(puVar2 + uVar8 * 8 + 0x38);
      uVar10 = 1L << (uVar16 & 0x3f);
      if ((uVar10 & uVar9) != 0) {
        puVar6 = puVar3;
        do {
          puVar5 = *(undefined **)(*(long *)(puVar2 + 0x30) + uVar16 * 8);
          __sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ();
          puVar3 = puVar14;
          puVar7 = puVar6;
          __sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ();
          if (puVar5 == puVar3 && puVar6 == puVar7) {
            puVar3 = puVar7;
            _swift_bridgeObjectRelease(uVar12,puVar6);
            _swift_bridgeObjectRelease(puVar7);
            goto LAB_100200120;
          }
          puVar3 = puVar6;
          __ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
                    ();
          _swift_bridgeObjectRelease(puVar6);
          _swift_bridgeObjectRelease(puVar7);
          if (((ulong)puVar5 & 1) != 0) goto LAB_100200120;
          uVar16 = uVar16 + 1 & ~uVar11;
          uVar8 = uVar16 >> 6;
          uVar9 = *(ulong *)(puVar2 + uVar8 * 8 + 0x38);
          uVar10 = 1L << (uVar16 & 0x3f);
          puVar6 = puVar3;
        } while ((uVar10 & uVar9) != 0);
      }
      *(ulong *)(puVar2 + uVar8 * 8 + 0x38) = uVar10 | uVar9;
      *(undefined8 *)(*(long *)(puVar2 + 0x30) + uVar16 * 8) = uVar12;
      if (SCARRY8(*(long *)(puVar2 + 0x10),1)) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x100200288);
        (*pcVar1)();
      }
      *(long *)(puVar2 + 0x10) = *(long *)(puVar2 + 0x10) + 1;
LAB_100200120:
      puVar15 = puVar15 + 1;
      puVar6 = puVar3;
    } while (puVar15 != puVar13);
  }
  return puVar2;
}

