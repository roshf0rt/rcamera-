// rea decompile_all
// name: _$s10CaptureLib0A4LensV7optical6deviceAcA0A6DeviceV_tFZ
// address: 0x100202c54
// body: available
// range: 0x100202c54-0x100202cfb inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100202cf8 to 0x10040e2a8 _objc_retain (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release_x20 replaced with injection: _objc_release_fixup */
/* WARNING: Function: _objc_retain replaced with injection: _objc_retain_fixup */

ID __s10CaptureLib0A4LensV7optical6deviceAcA0A6DeviceV_tFZ(undefined8 *param_1,ID param_2)

{
  ID IVar1;
  undefined8 extraout_x1;
  undefined8 uVar2;
  undefined4 extraout_s0;
  undefined4 uVar3;
  
  IVar1 = objc_stub::uniqueID(param_2);
  uVar2 = extraout_x1;
  uVar3 = extraout_s0;
  __sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ(IVar1);
  __sSS6appendyySSF(IVar1,uVar2);
  _swift_bridgeObjectRelease(uVar2);
  __s10CaptureLib0A6DeviceV17opticalMultiplierSfvg(param_2);
  *param_1 = 0x3a6c61636974706f;
  param_1[1] = 0xe800000000000000;
  param_1[2] = param_2;
  *(undefined4 *)(param_1 + 3) = uVar3;
  *(undefined4 *)((long)param_1 + 0x1c) = 0x3f800000;
  *(undefined1 *)(param_1 + 4) = 0;
  return param_2;
}

