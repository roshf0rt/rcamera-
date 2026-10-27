// rea decompile_all
// name: _$s10CaptureLib18CameraStateMachineCfD
// address: 0x100201008
// body: available
// range: 0x100201008-0x100201043 inclusive
// non_contiguous: false
// provider: Ghidra 12.1.4 (ghidra)
// analysis_profile: 066f9d6c56d7a436e2061afaa7f68aa9085572cd83e3172cf52ecd30a6101bae
// limitations: The session serves operations only after Ghidra reports default auto-analysis complete; incomplete analysis does not expose partial results.; The imported Program and temporary project are ephemeral and deleted on close. Annotation operations edit session database metadata; original executable bytes are never written.; Cancelling an active Ghidra request terminates its ephemeral database and discards session annotations. The selected target remains open; the next provider query imports the original artifact again.; Default-space addresses use lowercase 0x-prefixed hexadecimal; other address spaces use <percent-encoded-space>:0x<hex>.; Ghidra Listing reports a terminal call at 0x100201040 to 0x10040e980 _swift_defaultActor_deallocate (external=false, thunk=true, hasNoReturn=false); fallthrough is excluded by Ghidra's flow model. The reason for the terminal flow is not established by this observation.; Pseudocode is Ghidra decompiler output, not original source and not text-equivalent to Hopper output.; External functions and functions without an analyzable body return null; other decompiler failures remain explicit.
// pseudocode: provider-specific; not original source


void __s10CaptureLib18CameraStateMachineCfD(void)

{
  long unaff_x20;
  
  __s10Foundation4DateVSg_ADtWOhTm
            (unaff_x20 + _TtC10CaptureLib18CameraStateMachine::continuation,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMd,
             &__sScS12ContinuationVy10CaptureLib18CameraStateMachineC0E0O_GSgMR);
  _swift_defaultActor_destroy();
  _swift_defaultActor_deallocate();
  return;
}

