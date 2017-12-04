; This script waits for a file called "postProcessNow" to come into existence.
; When this script sees that file, it will delete it, then send Ctrl-Shift-P to Solidworks.
; Ctrl-Shift-P is the keyboard shortcut that I assigned, in solidworks, to run the HSMWorks "Post Process" function.


;For this to work, Solidworks has to be open with HSMWorks runnning, 
;and the proper machining operation or job has to be selected in the HSMWorks tab.

; Also, something other than the HSMWorks tab needs to have focus within solidworks 
;(does HSMWorks intercept Ctrl-Shift-P ?) (click in the model view area to achieve this)

;; Also, a keyboard shortcut in Solidworks needs to be set up to map Ctrl-Shift-P to the "Post Process" command.

#SingleInstance, Force
#Persistent


SetWorkingDir, %A_ScriptDir%
logFile = %A_Temp%\%A_ScriptName%-log.txt
FileAppend, %A_ScriptName% started at %A_NOW%`n, %logFile%
watchFile = %A_ScriptDir%\..\postProcessors\postProcessNow



Loop{
	If(FileExist(watchFile))
	{
		FileDelete, %watchFile%

		;ControlSend, swCaption, ^+p, ahk_exe SLDWORKS.exe
		;ControlSend, Tree Container Wnd, ^+p, ahk_exe SLDWORKS.exe
				
		WinActivate, ahk_exe SLDWORKS.exe
		SendInput, ^+p
		
		FileAppend, %A_NOW% : %A_ScriptName% did its thing. `n, %logFile%
	}
	Sleep 90
}

