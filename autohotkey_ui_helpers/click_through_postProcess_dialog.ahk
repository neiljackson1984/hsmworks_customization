; This script waits for the HSMWorks's "Post Process" dialog to appear, 
; then performas the sequence of clicks that results in the output file 
; being generated. This has the effect of making the "Post Process" button 
; in HSM works, a one-click button. 

; If you need to change any of the parameters in HSMWorks's "Post PRocess" 
; dialog, first stop this script, then manually click through the dialog 
; once to set the parameters as desired. Then, re-run this script to turn 
; on the one-click functionality. 

;Take care that the parameters in the "Post PRocess" dialog are correct before you run this script,
; because this script clicks "Yes" to the "do you want to overwrite" prompt that happens when saving the file with
; the same name.


#SingleInstance, Force
#Persistent


SetWorkingDir, %A_ScriptDir%
logFile = %A_ScriptName%-log.txt
FileAppend, %A_ScriptName% started at %A_NOW%`n, %logFile%

;;	FileAppend, %A_ScriptName% did its thing at %A_NOW%`n, %logFile%
;SetTitleMatchMode 3
;SetTitleMatchMode RegEx


;This loop works both for the initial "Post Process" dialog and the save-file dialog that pops up when you click "Post" (or equivalently press Enter) from within the the initial dialog,
; Because both Windows have title="Post Process" and, for both Windows, what we want to do is send an Enter keystroke.
Loop{
	WinWait, Post Process ahk_exe SLDWORKS.exe, &Reorder to minimize tool changes ;detects the initial "Post Process" dialog.  ; window contains all of the following strings in its visible text: "...", "Setup", "Post Configuration", "Open config", "Open folder", "&Output folder", "NC e&xtension", "Open Folder", "Program Settings", "Program name or number", "Program comment", "Unit", "&Reorder to minimize tool changes", and more, but that should be sufficient.
	ControlSend, , {Enter}

	WinWait, Post Process ahk_exe SLDWORKS.exe, Namespace Tree Control ;detects the save-file dialog that pops up after sending {Enter} to the initial "Post Process" dialog
	ControlSend, , {Enter}

	WinWait, Confirm Save As ahk_exe SLDWORKS.exe, ,2 ; timeout of 4 seconds in case a file with the same name did not already exist, in which case no "Confirm Save As" prompt will appear.
	If(ErrorLevel==0) {
		; in this case, the "Confirm Save As" windiow was detected
		ControlSend, , y
		confirmSavePromptEncountered:=1
	} else {
		confirmSavePromptEncountered:=0
	}
	
	Sleep, 600
	FileAppend, %A_NOW% : %A_ScriptName% did its thing. confirmSavePromptEncountered=%confirmSavePromptEncountered%  `n, %logFile%
}

