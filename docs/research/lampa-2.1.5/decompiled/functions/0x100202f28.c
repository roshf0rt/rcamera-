// rea decompile_all
// name: _$s10CaptureLib0A4LensV7digital17displayMultiplier12sourceDeviceACSf_AA0aH0VtFZTf4nnd_n
// address: 0x100202f28
// body: available
// range: 0x100202f28-0x100203017 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100203014 to 0x10040e2a8 _objc_retain (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release_x20 replaced with injection: _objc_release_fixup */
/* WARNING: Function: _objc_retain replaced with injection: _objc_retain_fixup */

ID __s10CaptureLib0A4LensV7digital17displayMultiplier12sourceDeviceACSf_AA0aH0VtFZTf4nnd_n
             (undefined8 *param_1,float param_2,ID param_3)

{
  undefined8 uVar1;
  ID IVar2;
  undefined8 extraout_x1;
  undefined8 uVar3;
  float fVar4;
  undefined8 local_50;
  undefined8 local_48;
  
  local_50 = 0;
  local_48 = 0xe000000000000000;
  __sSS6appendyySSF(0x3a6c617469676964,0xe800000000000000);
  IVar2 = objc_stub::uniqueID(param_3);
  uVar3 = extraout_x1;
  __sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ(IVar2);
  __sSS6appendyySSF(IVar2,uVar3);
  _swift_bridgeObjectRelease(uVar3);
  __sSS6appendyySSF(0x3a,0xe100000000000000);
  fVar4 = param_2;
  __sSf5write2toyxz_ts16TextOutputStreamRzlF
            (&local_50,PTR___ss26DefaultStringInterpolationVN_10055c398,
             PTR___ss26DefaultStringInterpolationVs16TextOutputStreamsWP_10055c3a8);
  uVar1 = local_48;
  uVar3 = local_50;
  __s10CaptureLib0A6DeviceV17opticalMultiplierSfvg(param_3);
  *param_1 = uVar3;
  param_1[1] = uVar1;
  param_1[2] = param_3;
  *(float *)(param_1 + 3) = param_2;
  *(float *)((long)param_1 + 0x1c) = param_2 / fVar4;
  *(undefined1 *)(param_1 + 4) = 1;
  return param_3;
}

