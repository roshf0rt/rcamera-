// rea decompile_all
// name: _$s10CaptureLib18CameraStateMachineC0D0O21__derived_enum_equalsySbAE_AEtFZTf4nnd_n
// address: 0x100202448
// body: available
// range: 0x100202448-0x10020256b inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


undefined8
__s10CaptureLib18CameraStateMachineC0D0O21__derived_enum_equalsySbAE_AEtFZTf4nnd_n
          (uint param_1,uint param_2)

{
  uint uVar1;
  uint uVar2;
  uint uVar3;
  uint uVar4;
  
  uVar1 = param_1 & 0xffffff;
  uVar3 = param_1 >> 0x18;
  uVar2 = param_2 & 0xffffff;
  uVar4 = param_2 >> 0x18;
  if (uVar3 < 2) {
    if (uVar3 != 0) {
      if (uVar4 != 1) {
        return 0;
      }
      goto LAB_1002024ec;
    }
    if (uVar4 != 0) {
      return 0;
    }
    if ((param_1 & 0xff00) != 0x200) {
      if ((param_2 & 0xff00) == 0x200) {
        return 0;
      }
      if (((param_2 ^ param_1) & 0xffff) != 0) {
        return 0;
      }
      if ((param_1 >> 0x10 & 0xff) != param_2 >> 0x10) {
        return 0;
      }
      return 1;
    }
LAB_1002024fc:
    if ((param_2 & 0xff00) != 0x200) {
      return 0;
    }
  }
  else {
    if (uVar3 == 2) {
      if (uVar4 != 2) {
        return 0;
      }
LAB_1002024ec:
      if ((param_1 & 0xff00) == 0x200) goto LAB_1002024fc;
      if ((param_2 & 0xff00) == 0x200) {
        return 0;
      }
      uVar2 = (param_2 ^ param_1) & 0xffffff;
    }
    else {
      if (uVar3 == 3) {
        if (uVar4 != 3) {
          return 0;
        }
        goto LAB_1002024ec;
      }
      if (1 < uVar1) {
        if (uVar1 == 2) {
          if (uVar4 != 4) {
            return 0;
          }
          if (uVar2 == 2) {
            return 1;
          }
          return 0;
        }
        if (uVar4 != 4) {
          return 0;
        }
        if (uVar2 == 3) {
          return 1;
        }
        return 0;
      }
      if (uVar1 != 0) {
        if (uVar4 != 4) {
          return 0;
        }
        if (uVar2 != 1) {
          return 0;
        }
        return 1;
      }
      if (uVar4 != 4) {
        return 0;
      }
    }
    if (uVar2 != 0) {
      return 0;
    }
  }
  return 1;
}

