format pe64 GUI

entry main

section ".code" readable writeable executable

include "TOOLS\x64\TOOLS.INC"
include_once "encoding\Win1251.inc"
; include_once "TOOLS\x64\cstdio.inc"
include_once "TOOLS\x64\WINUSER\Winuser.inc"
include_once "TOOLS\x64\WINUSER\DialogForm\DialogForm.inc"
include "TOOLS\x64\Graphics\Graphics.inc"

importlib kernel32,\
	GetLastError,\
	GetCurrentThreadId,\
	ExitProcess

importlib gdi32,\
	DeleteObject,\
	GetStockObject,\
	BitBlt,\
	SetGraphicsMode,\
	SetWorldTransform

importlib user32,\
	InvalidateRect,\
	SetWindowsHookExA,\
	UnhookWindowsHookEx,\
	CallNextHookEx,\
	BeginPaint,\
	EndPaint,\
	SetDlgItemInt,\
	MapDialogRect,\
	MapWindowPoints,\
	SetFocus

struct Matrix_byte
	bCount 	dd ?
	len0 	dd ?
	len1 	dd ?
	arr 	db 0 dup(?)
	; print  	dm this
ends

struct SnakePart
	rect 	RECT
	mapPos 	dd ?
	direct 	dd ?
ends

struct ButtonStart BUTTON
	BN_CLICKED event bt_Start_BN_CLICKED

	fEnabled 	dd 1
ends

struct dForm1 DIALOGFORM
	const _cx		= 450
	const _cy		= 300
	const step 		= 4
	const sizePart	= 4
	const headSize	= 10
	const foodCount equ 1

	WM_CTLCOLORSTATIC  		event DIALOGFORM_WM_CTLCOLOR

	WM_INITDIALOG	event dForm1_Init
	WM_KEYDOWN 		event dForm1_KeyDownStart
	WM_TIMER		event dForm1_Timer
	WM_PAINT		event dForm1_Paint

	@control st_Score 	STATIC,\
		_cx:  dForm1._cx,\
		_cy: dForm1.headSize,\
		_text: "",\
		_style: SS_CENTER or WS_VISIBLE or SS_CENTERIMAGE,\
		<_initvals: 0x0, 0xFF>

	@control bt_Start 	ButtonStart,\
		_x:  (dForm1._cx - dForm1.bt_Start._cx) / 2,\
		_y: (dForm1._cy - dForm1.bt_Start._cy) / 2,\
		_cx: 50,\
		_text: "Начать",\
		_style: WS_VISIBLE or BS_DEFPUSHBUTTON

	oldClose	dq ?
	lpMap 		dq ?

	hTimer		dq ?
	hook 		dq ?
	canvBrush 	dq ?
	bodyBrush 	dq ?
	headBrush 	dq ?
	mealBrush 	dq ?

	g 			Graphics
	rcCanv		RECT
	rcGame		RECT 0, 0, dForm1._cx, dForm1.headSize
	xf 			XFORM 0.0, 0.0, 0.0, 0.0, 0.0, 0.0

	downBound 	dd ?
	rightBound	dd ?

	head 		SnakePart <1 * (1 shl dForm1.sizePart), 0, 2 * (1 shl dForm1.sizePart), 1 * (1 shl dForm1.sizePart)>, 1, 3
	tale 		SnakePart <0, 0, 1 * (1 shl dForm1.sizePart), 1 * (1 shl dForm1.sizePart)>, 0, 3
	newDirect	dd 3
	mapInc 		dd -1, -1, 1, 1
	score 		dd 0
	scoreStr	db "Счёт: "
	scoreIntBuf	db 11 dup(?)
	rnd 		Random
ends

proc_noprologue

proc makeMeal uses rbx rsi, lpForm
	local mealRect:RECT
	virtObj .form:arg dForm1 at rbx from rcx
	virtObj .map:arg Matrix_byte at rsi from [.form.lpMap]
	.randAgain:
		@call .form.rnd->next([.map.bCount])
	cmp [.map.arr + rax], 0
	jne .randAgain
	mov [.map.arr + rdx], "@"
	mov eax, edx
	xor edx, edx
	div [.map.len1]
	shl edx, dForm1.sizePart
	shl eax, dForm1.sizePart
	mov [mealRect.left], edx
	mov [mealRect.top], eax
	add edx, 1 shl dForm1.sizePart
	add eax, 1 shl dForm1.sizePart
	mov [mealRect.right], edx
	mov [mealRect.bottom], eax
	@jret .form.g->fillRect(addr mealRect, [.form.mealBrush])
endp

proc dForm1_Hook uses rbx, nCode, wparam, lparam
    cmp [r8+MSG.message], WM_KEYDOWN
	je .keyboard
    cmp [r8+MSG.message], WM_CHAR
	je .keyboard
    cmp [r8+MSG.message], WM_SYSKEYDOWN
	je .keyboard
    	@jret [CallNextHookEx](NULL, rcx, rdx, r8)
	.keyboard:
    mov rbx, r8
	@call [GetActiveWindow]()
    @call [SendMessageA](rax, [rbx+MSG.message], [rbx+MSG.wParam], [rbx+MSG.lParam])
    xor eax,eax
    ret
endp

proc bt_Start_BN_CLICKED uses rbx, lpForm, lpParams, lpControl
	virtObj .form:arg dForm1 at rbx from rcx
	virtObj .button:arg ButtonStart at .form.bt_Start
	cmp [.button.fEnabled], 0
	je .returnToMenu
		mov [.button.fEnabled], 0
		@call .form.bt_Start->setVisible(0)

	    @call [GetCurrentThreadId]()
	    @call [SetWindowsHookExA](WH_GETMESSAGE, dForm1_Hook, NULL, rax)
	    mov [.form.hook], rax

		@jret startGame(addr .form)
	.returnToMenu:
		mov [.button.fEnabled], 1
		cmp [.form.hTimer], 0
		je .noTimer
			@call WND:killTimer([.form.hTimer], [.form.hWnd])
			mov [.form.hTimer], 0
		.noTimer:
		@call [UnhookWindowsHookEx]([.form.hook])
		mov [.form.WM_KEYDOWN], dForm1_KeyDownStart
		@call .form.bt_Start->setVisible(1)
		@call .form.st_Score->setText("")
		@call .form.g->fillRect(addr .form.rcCanv, [.form.canvBrush])
		@jret [InvalidateRect]([.form.hWnd], addr .form.rcGame, 0)
endp

proc startGame uses rbx rsi, lpForm
	virtObj .form:arg dForm1 at rbx from rcx
	virtObj .map:arg Matrix_byte at rsi from [.form.lpMap]
	@call CNV:memset(addr .map.arr, 0, [.map.bCount])
	mov dword[.map.arr], 03h

	mov [.form.head.rect.left], 1 * (1 shl dForm1.sizePart)
	mov [.form.head.rect.top], 0
	mov [.form.head.rect.right], 2 * (1 shl dForm1.sizePart)
	mov [.form.head.rect.bottom], 1 * (1 shl dForm1.sizePart)
	mov [.form.head.mapPos], 1
	mov [.form.head.direct], 3

	mov [.form.tale.rect.left], 0
	mov [.form.tale.rect.top], 0
	mov [.form.tale.rect.right], 1 * (1 shl dForm1.sizePart)
	mov [.form.tale.rect.bottom], 1 * (1 shl dForm1.sizePart)
	mov [.form.tale.mapPos], 0
	mov [.form.tale.direct], 3

	mov [.form.newDirect], 3
	mov [.form.score], 0
	@call CNV:uintToStr(addr .form.scoreIntBuf, [.form.score], 10)
	@call .form.st_Score->setText(myForm.scoreStr)

	@call .form.g->fillRect(addr .form.rcCanv, [.form.canvBrush])
	@call .form.g->fillRect(addr .form.head.rect, [.form.headBrush])
	@call .form.g->fillRect(addr .form.tale.rect, [.form.bodyBrush])
	rept dForm1.foodCount{
		@call makeMeal(addr .form)
	}
	@jret [InvalidateRect]([.form.hWnd], addr .form.rcGame, 0)
endp

proc dForm1_Init uses rbx, lpForm, lpParams
	virtObj .form:arg dForm1 at rbx from rcx
	local headOffset:DWORD
	@call .form->setCornerType(DWMWCP.DONOTROUND)
	mov rax, [.form.WM_CLOSE]
	mov [.form.WM_CLOSE], dForm1_Close
	mov [.form.oldClose], rax
	@call .form.bt_Start->setTheme(<du "DarkMode_Explorer", 0>)
	@call .form.st_Score->setBgColor(WND.darkThemeColor)

	@call .form.g->create()
	@call [MapDialogRect]([.form.hWnd], addr .form.rcGame)
	mov eax, [.form.rcGame.bottom]
	sub eax, [.form.rcGame.top]
	mov [headOffset], eax
	cvtsi2ss xmm0, eax
	movd [.form.xf.eDy], xmm0
	@call [GetClientRect]([.form.hWnd], addr .form.rcCanv)
	@call CNV:fill(addr .form.rcGame.right, addr .form.rcCanv.right, sizeof.POINT)
	mov eax, [headOffset]
	mov [.form.rcGame.top], eax

	local x:DWORD
	mov ecx, [.form.rcCanv.right]
	cvtsi2ss xmm0, ecx
	shr ecx, dForm1.sizePart
	mov r8d, ecx
	mov [x], ecx
	mov [.form.mapInc + 4], ecx
	neg [.form.mapInc + 4]
	mov [.form.mapInc + 12], ecx
	shl ecx, dForm1.sizePart
	mov [.form.rightBound], ecx
	cvtsi2ss xmm1, ecx
	divss xmm0, xmm1
	movd [.form.xf.eM11], xmm0

	local y:DWORD, matrixSize:DWORD
	mov edx, [.form.rcCanv.bottom]
	sub edx, [headOffset]
	cvtsi2ss xmm2, edx
	shr edx, dForm1.sizePart
	imul r8d, edx
	mov [matrixSize], r8d
	mov [y], edx
	shl edx, dForm1.sizePart
	mov [.form.downBound], edx
	cvtsi2ss xmm3, edx
	divss xmm2, xmm3
	movd [.form.xf.eM22], xmm2

	@call CNV:alloc(addr sizeof.Matrix_byte + r8d * 1)
	mov [.form.lpMap], rax
	mov edx, [matrixSize]
	mov [rax + Matrix_byte.bCount], edx
	mov edx, [y]
	mov [rax + Matrix_byte.len0], edx
	mov edx, [x]
	mov [rax + Matrix_byte.len1], edx
	mov dword[rax + Matrix_byte.arr], 03h
	@call .form.rnd->new()

	@call [CreateCompatibleBitmap]([.form.g.hDC], [.form.rightBound], [.form.downBound])
	@call .form.g->selectObject(rax, Graphics.BMP)
	@call [GetStockObject](BLACK_BRUSH)
	mov [.form.canvBrush], rax
	@call [CreateSolidBrush](0x0000CF)
	mov [.form.mealBrush], rax
	@call [CreateSolidBrush](0x00FF00)
	mov [.form.bodyBrush], rax
	@call [CreateSolidBrush](0x00CF00)
	mov [.form.headBrush], rax

	; @call .form.g->fillRect(addr .form.rcCanv, [.form.canvBrush])
	; @call .form.g->fillRect(addr .form.head.rect, [.form.headBrush])
	; @call .form.g->fillRect(addr .form.tale.rect, [.form.bodyBrush])
	; rept dForm1.foodCount{
	; 	@call makeMeal(addr .form)
	; }

    mov eax, 1
    ret
endp

proc dForm1_Paint uses rbx, lpForm, lpParams
	virtObj .form:arg dForm1 at rbx from rcx
	local ps:PAINTSTRUCT
    @call [BeginPaint]([.form.hWnd], addr ps);
	@call [SetGraphicsMode]([ps.hdc], GM_ADVANCED)
	@call [SetWorldTransform]([ps.hdc], addr .form.xf)
    @call [BitBlt]([ps.hdc], 0, 0, [.form.rightBound], [.form.downBound], [.form.g.hDC], 0, 0, SRCCOPY)
	@call [EndPaint]([.form.hWnd], addr ps)
	mov rax, 0
	ret
endp

proc dForm1_Timer uses rbx rsi, lpForm, lpParams
	virtObj .form:arg dForm1 at rbx from rcx
	cmp [.form.newDirect], 7
		je .return
	virtObj .map Matrix_byte at rsi from [.form.lpMap]
	test [.form.head.rect.left], 1 shl dForm1.sizePart - 1
	jnz .noCellBorder
	test [.form.head.rect.top], 1 shl dForm1.sizePart - 1
	jnz .noCellBorder
		mov eax, [.form.newDirect]
		jmp [.boundScan + (eax - 1)*8]
		.boundScanEnd label QWORD
		mov [.form.head.direct], eax
		mov edx, [.form.head.mapPos]
		mov [.map.arr + rdx], al
		mov eax, [.form.mapInc + (rax - 1) * 4]
		add [.form.head.mapPos], eax
		mov eax, [.form.head.mapPos]
		cmp [.map.arr + rax], '@'
		je .findMeal
			cmp [.map.arr + rax], 0
				jne .return
			mov eax, [.form.tale.mapPos]
			movzx eax, byte[.map.arr + rax]
			mov [.form.tale.direct], eax
			mov edx, [.form.tale.mapPos]
			mov [.map.arr + rdx], 0
			mov eax, [.form.mapInc + (rax - 1) * 4]
			add [.form.tale.mapPos], eax
			jmp .noCellBorder
		.findMeal:
			inc [.form.score]
			@call CNV:uintToStr(addr .form.scoreIntBuf, [.form.score], 10)
			@call .form.st_Score->setText(myForm.scoreStr)
			@call makeMeal(addr .form)
	.noCellBorder:
	mov eax, [.form.head.mapPos]
	cmp [.map.arr + rax], '@'
	je .noTailPrint
		@call .form.g->fillRect(addr .form.tale.rect, [.form.canvBrush])
		mov eax, [.form.tale.direct]
		mov r11, qword[.moveMagic + (eax - 1)*8]
		add qword[.form.tale.rect], r11
		add qword[.form.tale.rect + 8], r11
		@call .form.g->fillRect(addr .form.tale.rect, [.form.bodyBrush])
	.noTailPrint:
	@call .form.g->fillRect(addr .form.head.rect, [.form.bodyBrush])
	mov eax, [.form.head.direct]
	mov r11, qword[.moveMagic + (eax - 1)*8]
	add qword[.form.head.rect], r11
	add qword[.form.head.rect + 8], r11
	@call .form.g->fillRect(addr .form.head.rect, [.form.headBrush])
	@jret [InvalidateRect]([.form.hWnd], addr .form.rcGame, 0)
	.return: 
		@call WND:killTimer([.form.hTimer], [.form.hWnd])
		mov [.form.WM_KEYDOWN], dForm1_KeyDownStart
		@jret startGame(addr .form)
	
	.moveMagic dd -dForm1.step, -1, 0, -dForm1.step, dForm1.step, 0, 0, dForm1.step
	.boundScan dq .mapLeft, .mapUp, .mapRight, .mapDown, .mapPause
 
	.mapLeft:
		cmp [.form.head.rect.left], 0
			jbe .return
		jmp .boundScanEnd

	.mapUp:
		cmp [.form.head.rect.top], 0
			jbe .return
		jmp .boundScanEnd
	
	.mapRight:
		mov edx, [.form.head.rect.right]
		cmp edx, [.form.rightBound]
			jae .return
		jmp .boundScanEnd
	
	.mapDown:
		mov edx, [.form.head.rect.bottom]
		cmp edx, [.form.downBound]
			jae .return
		jmp .boundScanEnd

	.mapPause:
		mov [.form.WM_KEYDOWN], dForm1_KeyDownStart
		@jret WND:killTimer([.form.hTimer], [.form.hWnd])
endp

proc dForm1_KeyDownStart, lpForm, lpParams
	virtObj .form:arg dForm1 at rcx
	virtObj .params:arg params at rdx
	mov rax, [.params.wparam]
	cmp al, VK_BACK
		je .exit
	cmp eax, 37
		jb .return
	cmp eax, 40
		ja .return
	sub eax, 36
	cmp eax, [.form.head.direct]
	je .equalDirections
		mov r8d, [.form.head.direct]
		xor r8d, eax
		test r8d, 1
			jz .return
	.equalDirections:
	mov [.form.newDirect], eax
	mov [.form.WM_KEYDOWN], dForm1_KeyDown
	mov [lpForm], rcx
	@call WND:setTimer(10, NULL, 1, [.form.hWnd])
	mov rcx, [lpForm]
	mov [.form.hTimer], rax
	.return: ret
	
	.exit: @jret .form->close()
endp

proc dForm1_KeyDown, lpForm, lpParams
	virtObj .form:arg dForm1 at rcx
	virtObj .params:arg params at rdx
	mov rax, [.params.wparam]
	cmp al, VK_BACK
		je .exit
	cmp al, VK_SPACE
		je ._pause
	cmp eax, 37
		jb .return
	cmp eax, 40
		ja .return
	sub eax, 36
	mov r8d, [.form.head.direct]
	xor r8d, eax
	test r8d, 1
		jz .return
	mov [.form.newDirect], eax
	.return: ret

	.exit: @jret .form->close()
	
	._pause: 
		mov [.form.newDirect], 5
		ret
endp

proc dForm1_Close uses rbx, lpForm, lpParams
	virtObj .form:arg dForm1 at rbx from rcx
	mov [lpParams], rdx
	@call [DeleteObject]([.form.bodyBrush])
	@call [DeleteObject]([.form.headBrush])
	@call [DeleteObject]([.form.mealBrush])
	@call .form.g->destroy()
	cmp [.form.hook], 0
	je .noHook
		@call [UnhookWindowsHookEx]([.form.hook])
	.noHook:
	@call CNV:free([.form.lpMap])
	cmp [.form.hTimer], 0
	je .noTimer
		@call WND:killTimer([.form.hTimer], [.form.hWnd])
	.noTimer:
	@jret [.form.oldClose](addr .form, [lpParams])
endp

ShblDialog dForm1, "Snake FASM_OOP", WS_VISIBLE or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX or DS_CENTER or WS_CLIPCHILDREN;, WS_EX_COMPOSITED

myForm form dForm1

proc main
	@call myForm->start()
	@jret [ExitProcess]()
endp
; ; virtual at rax
; ; 	a:
; ; end virtual
; a equ rax+4
; if a relativeto rax
; 	display "lol"
; end if

; proc Matrix_byte.print uses rbx rsi rdi r12, this
; 	virtObj .this:arg Matrix_byte at rbx from rcx
; 	xor esi, esi
; 	mov edi, [.this.len1]
; 	mov r12d, [.this.len0]
; 	imul r12d, edi
; 	.loop1:
; 		.loop2:
; 			@call [printf]("%d", byte[.this.arr + rsi])
; 			inc esi
; 		cmp esi, edi
; 		jb .loop2
; 		@call [printf](<db 0Ah, 0>, byte[.this.arr + rsi])
; 		add edi, [.this.len1]
; 	cmp esi, r12d
; 	jb .loop1 
; 	@call [printf](<db 0Ah, 0>, byte[.this.arr + rsi])
; 	ret
; endp

data resource
	directory 	RT_MANIFEST, manifests

	resource manifests,\ 
					 1, LANG_ENGLISH or SUBLANG_DEFAULT, manifest

	resdata manifest
		db 	'<assembly xmlns="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0">'
		db 		'<dependency>'
		db 			'<dependentAssembly>'
		db 				'<assemblyIdentity '
		db 					'type="win32" '
		db 					'name="Microsoft.Windows.Common-Controls" '
		db 					'version="6.0.0.0" '
		db 					'processorArchitecture="*" '
		db 					'publicKeyToken="6595b64144ccf1df" '
		db 					'language="*" '
		db 				'/>'
		db 			'</dependentAssembly>'
		db 		'</dependency>'
		db 	'</assembly>'
	endres
end data
; 		db	'<?xml version="1.0" encoding="UTF-8" standalone="yes"?> '
; 		db	'<assembly xmlns="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0">'
; 		db		'<dependency>'
; 		db			'<dependentAssembly>'
; 		db				'<assemblyIdentity '
; 		db					'type="win32" '
; 		db					'name="Microsoft.Windows.Common-Controls" '
; 		db					'version="6.0.0.0" '
; 		db					'processorArchitecture="*" '
; 		db					'publicKeyToken="6595b64144ccf1df" '
; 		db					'language="*" '
; 		db				'/>'
; 		db			'</dependentAssembly>'
; 		db		'</dependency>'
; 		db		'<application xmlns="urn:schemas-microsoft-com:asm.v3"> '
; 		db			'<windowsSettings> <dpiAware      xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/PM</dpiAware>                     </windowsSettings> '
; 		db			'<windowsSettings> <dpiAwareness  xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2,PerMonitor</dpiAwareness> </windowsSettings> '
; 		db			'<windowsSettings> <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>                   </windowsSettings> '
; 		db			'<windowsSettings> <heapType      xmlns="http://schemas.microsoft.com/SMI/2020/WindowsSettings">SegmentHeap</heapType>                 </windowsSettings> '
; 		db		'</application> '
; 		db		'<trustInfo xmlns="urn:schemas-microsoft-com:asm.v2"> '
; 		db			'<security> '
; 		db				'<requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3"> '
; 		db					'<requestedExecutionLevel level="asInvoker" uiAccess="false" /> '
; 		db				'</requestedPrivileges> '
; 		db			'</security> '
; 		db		'</trustInfo> '
; 		db		'<compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"> '
; 		db			'<application> '
; 		db				'<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" /> '
; 		db				'<supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}" /> '
; 		db				'<supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}" /> '
; 		db				'<supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}" /> '
; 		db				'<supportedOS Id="{e2011457-1546-43c5-a5fe-008deee3d3f0}" /> '
; 		db			'</application> '
; 		db		'</compatibility> '
; 		db	'</assembly> '