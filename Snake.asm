define PROGRAM_TYPE GUI 6.0

include "encoding\win1251.inc"
include "FASM_OOP\x64.inc"
include "FASM_OOP\Winuser.inc"
include "FASM_OOP\DialogForm.inc"

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
	SetFocus,\
	BeginPaint,\
	EndPaint

entry main

struct ByteMatrix
	bCount 	rd 1
	len0 	rd 1
	len1 	rd 1
	arr 	rb 0
ends

struct SnakePart
	rect 	RECT
	mapPos 	rd 1
	direct 	rd 1
ends

struct StartButton BUTTON
	BN_CLICKED 	event ?
	WM_PAINT  	hook ?

	fEnabled 	rd 1
ends

struct MainForm DIALOGFORM
	const _cx		= 450
	const _cy		= 300
	const STEP 		= 4
	const SIZE_PART	= 4
	const HEAD_SIZE	= 10
	const FOOD_COUNT equ 1

	WM_INITDIALOG		event MainForm_Init
	WM_CTLCOLORSTATIC	event MainForm_CtlColor
	; WM_CTLCOLORBTN		event MainForm_CtlColor
	WM_CTLCOLORDLG		event MainForm_CtlColor
	WM_KEYDOWN 			event MainForm_KeyDownStart
	WM_TIMER			event MainForm_Timer
	WM_PAINT			event MainForm_Paint
	WM_CLOSE 			event MainForm_Close

	@control stScore 	STATIC,\
		_cx:  MainForm._cx,\
		_cy: MainForm.HEAD_SIZE,\
		_text: "",\
		_style: SS_CENTER or SS_CENTERIMAGE,\
		_style_ex: WS_EX_STATICEDGE

	@control btStart 	StartButton,\
		_x:  (MainForm._cx - MainForm.btStart._cx) / 2,\
		_y: (MainForm._cy - MainForm.btStart._cy) / 2,\
		_cx: 50,\
		_text: "Начать",\
		_style: WS_VISIBLE or BS_DEFPUSHBUTTON or BS_FLAT,\
		<_initvals: MainForm.btStart_Cicked, MainForm.btStart_Paint>

	lpMap 		rptr 1

	hTimer		rptr 1
	hook_ 		rptr 1
	canvBrush 	rptr 1
	bodyBrush 	rptr 1
	headBrush 	rptr 1
	mealBrush 	rptr 1

	g 			Graphics
	rcCanv		RECT
	rcGame		RECT 0, 0, MainForm._cx, MainForm.HEAD_SIZE
	xf 			XFORM 0.0, 0.0, 0.0, 0.0, 0.0, 0.0

	downBound 	rd 1
	rightBound	rd 1

	head 		SnakePart <1 * (1 shl MainForm.SIZE_PART), 0, 2 * (1 shl MainForm.SIZE_PART), 1 * (1 shl MainForm.SIZE_PART)>, 1, 3
	tale 		SnakePart NONE, 0, 3
	newDirect	dd 3
	mapInc 		dd -1, ?, 1, ?
	score 		dd 0
	scoreStr	db "Счёт: "
	scoreIntBuf	rb 11
	rnd 		Random
ends

.proc_frame_mode_static

.proc MainForm_Init(.p_form, .p_params, .p_eventData) uses pbx
	virtObj .form MainForm at pbx from @arg1
	.local .headOffset:DWORD
	$call .form::setCornerType(DWMWCP.DONOTROUND)
	$call .form.btStart::setTheme(<const du "DarkMode_Explorer", 0>)
	mov [.form.btStart.fEnabled], esp
	$call .form.btStart::setFocus()
	$call .form.stScore::setTheme(<const du "DarkMode_Explorer", 0>)

	$call .form.g::make()
	$call [MapDialogRect]([.form.hWnd], &.form.rcGame)
	mov eax, [.form.rcGame.bottom]
	sub eax, [.form.rcGame.top]
	mov [.headOffset], eax
	cvtsi2ss xmm0, eax
	movd [.form.xf.eDy], xmm0
	$call [GetClientRect]([.form.hWnd], &.form.rcCanv)
	$call CNV|fill(&.form.rcGame.right, &.form.rcCanv.right, sizeof.POINT)
	mov eax, [.headOffset]
	mov [.form.rcGame.top], eax

	.local .x:DWORD
	mov ecx, [.form.rcCanv.right]
	cvtsi2ss xmm0, ecx
	shr ecx, MainForm.SIZE_PART
	mov eax, ecx
	mov [.x], ecx
	mov [.form.mapInc + 4], ecx
	neg [.form.mapInc + 4]
	mov [.form.mapInc + 12], ecx
	shl ecx, MainForm.SIZE_PART
	mov [.form.rightBound], ecx
	cvtsi2ss xmm1, ecx
	divss xmm0, xmm1
	movd [.form.xf.eM11], xmm0

	.local .y:DWORD, .matrixSize:DWORD
	mov edx, [.form.rcCanv.bottom]
	sub edx, [.headOffset]
	cvtsi2ss xmm2, edx
	shr edx, MainForm.SIZE_PART
	imul eax, edx
	mov [.matrixSize], eax
	mov [.y], edx
	shl edx, MainForm.SIZE_PART
	mov [.form.downBound], edx
	cvtsi2ss xmm3, edx
	divss xmm2, xmm3
	movd [.form.xf.eM22], xmm2

	$call CNV|alloc(addr sizeof.ByteMatrix + eax * 1)
	mov [.form.lpMap], pax
	mov edx, [.matrixSize]
	mov [pax + ByteMatrix.bCount], edx
	mov edx, [.y]
	mov [pax + ByteMatrix.len0], edx
	mov edx, [.x]
	mov [pax + ByteMatrix.len1], edx
	mov dword[pax + ByteMatrix.arr], 03h
	$call .form.rnd::make()

	$call [CreateCompatibleBitmap]([.form.g.hDC], [.form.rightBound], [.form.downBound])
	$call .form.g::selectObject(pax, Graphics.BMP)
	$call [GetStockObject](BLACK_BRUSH)
	mov [.form.canvBrush], pax
	$call [CreateSolidBrush](0x0000CF)
	mov [.form.mealBrush], pax
	$call [CreateSolidBrush](0x00FF00)
	mov [.form.bodyBrush], pax
	$call [CreateSolidBrush](0x00CF00)
	mov [.form.headBrush], pax

	$return 1
.endp

.proc cdecl MakeMeal(.p_form) uses pbx psi
	.local .mealRect:RECT
	virtObj .form MainForm at pbx from @arg1
	virtObj .map ByteMatrix at psi from [.form.lpMap]
	.randAgain:
		$call .form.rnd::next([.map.bCount])
	cmp [.map.arr + pax], 0
	jne .randAgain
	mov [.map.arr + pdx], "@"
	mov eax, edx
	xor edx, edx
	div [.map.len1]
	shl edx, MainForm.SIZE_PART
	shl eax, MainForm.SIZE_PART
	mov [.mealRect.left], edx
	mov [.mealRect.top], eax
	add edx, 1 shl MainForm.SIZE_PART
	add eax, 1 shl MainForm.SIZE_PART
	mov [.mealRect.right], edx
	mov [.mealRect.bottom], eax
	$call .form.g::fillRect(&.mealRect, [.form.mealBrush])
	ret
.endp

.proc MainForm_CtlColor(.p_form, .p_params, .p_eventData) uses psi
	virtObj .params params at psi from @arg2
	$call [SetBkColor]([.params.wParam], 0x0)
	$call [SetTextColor]([.params.wParam], 0xFFFFFF)
	$call [GetStockObject](BLACK_BRUSH)
	$return pax
.endp

.proc MainForm.btStart_Paint(.p_form, .p_params, .p_control:P_StartButton, .p_eventData)
	virtObj .btn StartButton at pbx from @arg3
	.local .ps:PAINTSTRUCT, .btnRect:RECT
	$call [BeginPaint]([.btn.hWnd], &.ps)
	$call [GetStockObject](BLACK_BRUSH)
	; int3
	$call WND|repaintWindow([.btn.hWnd], [.ps.hdc], &.ps.rcPaint, pax)
	$call [EndPaint]([.btn.hWnd], &.ps)
	$return 0
.endp

.proc MainForm_Hook(.nCode, .wParam, .lParam) uses pbx
	@larg pbx, @arg3
	switch [pbx + MSG.message]
		case WM_KEYDOWN, WM_CHAR, WM_SYSKEYDOWN
			$call [GetActiveWindow]()
			$call [SendMessageA](pax, [pbx + MSG.message], [pbx + MSG.wParam], [pbx + MSG.lParam])
			$return 0
		case_default
			$call [CallNextHookEx](NULL, @arg1, @arg2, pbx)
			ret
	end_switch
.endp

.proc cdecl StartGame(.p_form) uses pbx psi
	virtObj .form MainForm at pbx from @arg1
	virtObj .map ByteMatrix at psi from [.form.lpMap]
	$call CNV|memset(&.map.arr, 0, [.map.bCount])
	mov dword[.map.arr], 03h

	mov [.form.head.rect.left], 1 * (1 shl MainForm.SIZE_PART)
	mov [.form.head.rect.top], 0
	mov [.form.head.rect.right], 2 * (1 shl MainForm.SIZE_PART)
	mov [.form.head.rect.bottom], 1 * (1 shl MainForm.SIZE_PART)
	mov [.form.head.mapPos], 1
	mov [.form.head.direct], 3

	mov [.form.tale.rect.left], 0
	mov [.form.tale.rect.top], 0
	mov [.form.tale.rect.right], 1 * (1 shl MainForm.SIZE_PART)
	mov [.form.tale.rect.bottom], 1 * (1 shl MainForm.SIZE_PART)
	mov [.form.tale.mapPos], 0
	mov [.form.tale.direct], 3

	mov [.form.newDirect], 3
	mov [.form.score], 0
	$call CNV|uintToStr(&.form.scoreIntBuf, [.form.score], 10)
	$call .form.stScore::setText(myForm.scoreStr)

	$call .form.g::fillRect(&.form.rcCanv, [.form.canvBrush])
	$call .form.g::fillRect(&.form.head.rect, [.form.headBrush])
	$call .form.g::fillRect(&.form.tale.rect, [.form.bodyBrush])
	rept MainForm.FOOD_COUNT{
		$call MakeMeal(&.form)
	}
	$call [InvalidateRect]([.form.hWnd], &.form.rcGame, 0)
	ret
.endp

.proc MainForm.btStart_Cicked(.p_form, .p_params, .p_control, .p_eventData) uses pbx
	virtObj .form MainForm at pbx from @arg1
	virtObj .button StartButton at .form.btStart
	cmp [.button.fEnabled], 0
	@block je @fb
		mov [.button.fEnabled], 0
		$call .form.btStart::setVisible(0)
		$call .form.stScore::setVisible(1)
		$call [GetCurrentThreadId]()
		$call [SetWindowsHookExA](WH_GETMESSAGE, MainForm_Hook, NULL, pax)
		mov [.form.hook_], pax
		$call StartGame(&.form)
		ret
	@endb
	mov [.button.fEnabled], 1
	cmp [.form.hTimer], NULL
	je .no_timer
		$call WND|killTimer([.form.hTimer], [.form.hWnd])
		mov [.form.hTimer], NULL
	.no_timer:
	$call [UnhookWindowsHookEx]([.form.hook_])
	mov [.form.WM_KEYDOWN], MainForm_KeyDownStart
	$call .form.btStart::setVisible(1)
	$call .form.stScore::setVisible(0)
	$call .form.stScore::setText("")
	$call .form.g::fillRect(&.form.rcCanv, [.form.canvBrush])
	$call [InvalidateRect]([.form.hWnd], &.form.rcGame, 0)
	ret
.endp

.proc MainForm_Paint(.p_form, .p_params, .p_eventData) uses pbx
	virtObj .form MainForm at pbx from @arg1
	.local .ps:PAINTSTRUCT
	$call [BeginPaint]([.form.hWnd], &.ps);
	$call [SetGraphicsMode]([.ps.hdc], GM_ADVANCED)
	$call [SetWorldTransform]([.ps.hdc], &.form.xf)
	$call [BitBlt]([.ps.hdc], 0, 0, [.form.rightBound], [.form.downBound], [.form.g.hDC], 0, 0, SRCCOPY)
	$call [EndPaint]([.form.hWnd], &.ps)
	$return 0
.endp

.proc MainForm_Timer(.p_form, .p_params, .p_eventData) uses pbx psi
	virtObj .form MainForm at pbx from @arg1
	cmp [.form.newDirect], 7
		je .restart
	virtObj .map ByteMatrix at psi from [.form.lpMap]
	test [.form.head.rect.left], 1 shl MainForm.SIZE_PART - 1
	jnz .no_cell_border
	test [.form.head.rect.top], 1 shl MainForm.SIZE_PART - 1
	jnz .no_cell_border
		mov eax, [.form.newDirect]
		jmp [.boundScan + (pax - 1) * pointer.size]
		.bound_scan_end:
		mov [.form.head.direct], eax
		mov edx, [.form.head.mapPos]
		mov [.map.arr + pdx], al
		mov eax, [.form.mapInc + (pax - 1) * 4]
		add [.form.head.mapPos], eax
		mov eax, [.form.head.mapPos]
		cmp [.map.arr + pax], '@'
		je .findMeal
			cmp [.map.arr + pax], 0
				jne .restart
			mov eax, [.form.tale.mapPos]
			movzx eax, byte[.map.arr + pax]
			mov [.form.tale.direct], eax
			mov edx, [.form.tale.mapPos]
			mov [.map.arr + pdx], 0
			mov eax, [.form.mapInc + (pax - 1) * 4]
			add [.form.tale.mapPos], eax
			jmp .no_cell_border
		.findMeal:
			inc [.form.score]
			$call CNV|uintToStr(&.form.scoreIntBuf, [.form.score], 10)
			$call .form.stScore::setText(myForm.scoreStr)
			$call MakeMeal(&.form)
	.no_cell_border:
	mov eax, [.form.head.mapPos]
	cmp [.map.arr + pax], '@'
	je .no_tail_print
		$call .form.g::fillRect(&.form.tale.rect, [.form.canvBrush])
		mov eax, [.form.tale.direct]
		movq xmm0, qword[.moveMagic + (pax - 1) * 8]
		movlhps xmm0, xmm0
		movups xmm1, xword[.form.tale.rect]
		paddq xmm1, xmm0
		movups xword[.form.tale.rect], xmm1
		$call .form.g::fillRect(&.form.tale.rect, [.form.bodyBrush])
	.no_tail_print:
	$call .form.g::fillRect(&.form.head.rect, [.form.bodyBrush])
	mov eax, [.form.head.direct]
	movq xmm0, qword[.moveMagic + (pax - 1) * 8]
	movlhps xmm0, xmm0
	movups xmm1, xword[.form.head.rect]
	paddq xmm1, xmm0
	movups xword[.form.head.rect], xmm1
	$call .form.g::fillRect(&.form.head.rect, [.form.headBrush])
	$call [InvalidateRect]([.form.hWnd], &.form.rcGame, 0)
	ret

	.restart: 
		$call WND|killTimer([.form.hTimer], [.form.hWnd])
		mov [.form.WM_KEYDOWN], MainForm_KeyDownStart
		$call StartGame(&.form)
		ret
	
	.moveMagic dd -MainForm.STEP, -1, 0, -MainForm.STEP, MainForm.STEP, 0, 0, MainForm.STEP
	.boundScan dptr .map_left, .map_up, .map_right, .map_down, .map_pause
 
	.map_left:
		cmp [.form.head.rect.left], 0
			jbe .restart
		jmp .bound_scan_end

	.map_up:
		cmp [.form.head.rect.top], 0
			jbe .restart
		jmp .bound_scan_end
	
	.map_right:
		mov edx, [.form.head.rect.right]
		cmp edx, [.form.rightBound]
			jae .restart
		jmp .bound_scan_end
	
	.map_down:
		mov edx, [.form.head.rect.bottom]
		cmp edx, [.form.downBound]
			jae .restart
		jmp .bound_scan_end

	.map_pause:
		mov [.form.WM_KEYDOWN], MainForm_KeyDownStart
		$call WND|killTimer([.form.hTimer], [.form.hWnd])
		ret
.endp

.proc MainForm_KeyDownStart(.p_form, .p_params, .p_eventData)
	virtObj .form MainForm at pcx from @arg1
	virtObj .params params at pdx from @arg2
	movzx eax, byte[.params.wParam]
	switch eax
		case VK_BACK
			$call .form::close()
			$return
		case u +37 ... +40
			sub eax, 36
			cmp eax, [.form.head.direct]
			je .equalDirections
				mov edx, [.form.head.direct]
				xor edx, eax
				test edx, 1
					jz end_case
			.equalDirections:
			mov [.form.newDirect], eax
			mov [.form.WM_KEYDOWN], MainForm_KeyDown
			mov [.p_form], pcx
			$call WND|setTimer(10, NULL, 1, [.form.hWnd])
			mov pcx, [.p_form]
			mov [.form.hTimer], pax
	end_switch
	ret
.endp

.proc MainForm_KeyDown(.p_form, .p_params, .p_eventData)
	virtObj .form MainForm at pcx from @arg1
	virtObj .params params at pdx from @arg2
	movzx eax, byte[.params.wParam]
	switch eax
		case VK_BACK
			$call .form::close()
			$return
		case VK_SPACE
			mov [.form.newDirect], 5
			$return
		case u +VK_LEFT ... +VK_DOWN
			sub eax, 36
			mov edx, [.form.head.direct]
			xor edx, eax
			test edx, 1
				jz end_case
			mov [.form.newDirect], eax
	end_switch
	.return: ret
.endp

.proc MainForm_Close(.p_form, .p_params, .p_eventData) uses pbx
	virtObj .form MainForm at pbx from @arg1
	@sarg @arg2

	$call [DeleteObject]([.form.bodyBrush])
	$call [DeleteObject]([.form.headBrush])
	$call [DeleteObject]([.form.mealBrush])
	$call .form.g::unmake()
	cmp [.form.hook_], 0
	je .no_hook
		$call [UnhookWindowsHookEx]([.form.hook_])
	.no_hook:
	$call CNV|free([.form.lpMap])
	cmp [.form.hTimer], 0
	je .no_timer
		$call WND|killTimer([.form.hTimer], [.form.hWnd])
	.no_timer:
	ret
.endp

ShblDialog_Mem MainForm, "Snake FASM_OOP", WS_VISIBLE or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX or DS_CENTER or WS_CLIPCHILDREN;, WS_EX_COMPOSITED

myForm dForm MainForm

.proc main
	$call myForm::start(NULL)
	$call [ExitProcess](0)
.endp

; data resource
; 	directory 	RT_MANIFEST, manifests

; 	resource manifests,\ 
; 		   1, LANG_ENGLISH or SUBLANG_DEFAULT, manifest

; 	resdata manifest
; 		file "FASM_OOP\manifest.xml"
; 	endres
; end data

; .proc ByteMatrix.print uses pbx psi rdi r12, this
; 	virtObj .this ByteMatrix at pbx from pcx
; 	xor esi, esi
; 	mov edi, [.this.len1]
; 	mov r12d, [.this.len0]
; 	imul r12d, edi
; 	.loop1:
; 		.loop2:
; 			$call [printf]("%d", byte[.this.arr + psi])
; 			inc esi
; 		cmp esi, edi
; 		jb .loop2
; 		$call [printf](<db 0Ah, 0>, byte[.this.arr + psi])
; 		add edi, [.this.len1]
; 	cmp esi, r12d
; 	jb .loop1 
; 	$call [printf](<db 0Ah, 0>, byte[.this.arr + psi])
; 	ret
; .endp