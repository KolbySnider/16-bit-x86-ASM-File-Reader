
;
; marquee.asm
;

; ======================================================

MyStack SEGMENT STACK
        DW 256 DUP(?)
MyStack ENDS

; ======================================================

MyData SEGMENT

	; Command Tail Stuff
	inFileName    DB 26 DUP(0)		; Assume the file name is no longer than 25 chars
	limit         DW 0

	; Handles & Buffers
	inHandle      DW 0
	outHandle     DW 0
	outFileName   DB "output.dat",0
	
	blockSize     EQU 64
	inBuffer      DB blockSize DUP(0)
	inBufferEnd   DB 0

	outBuffer     DB 23 DUP(0)		; No more than 20 chars per name, so 23 for CR, LF, 0
 	num           DW 0

	; Misc.
	atEOF         DB 0

	; Messages
	errorOpenMsg  DB "Error Opening!$"
	errorReadMsg  DB "Error Reading!$"
	errorWriteMsg DB "Error Writing!$"
	errorCloseMsg DB "Error Closing!$"

	timeMsg       DB "Time (s): "		; There shouldn't be a file given that takes
	timeMsgNum    DB 6 DUP(0)		; more than an hour to process, so "3600.0"
	              DB "s$"  			; is used as an upper bound. 6 bytes at most	

	; Interrupt Codes
	createFileINT EQU 3Ch
	openFileINT   EQU 3Dh
	closeFileINT  EQU 3Eh
	readFileINT   EQU 3Fh
	writeFileINT  EQU 40h

	getTicksINT   EQU 00h
	printINT      EQU 09h
	stopINT       EQU 4Ch
MyData ENDS

; ======================================================

MyCode SEGMENT
ASSUME CS:MyCode, DS:MyData, SS:MyStack


; -----------------------------------------
; Writes outBuffer to the file only up to the line feed character
; -----------------------------------------
writeToFile PROC
	PUSH AX BX CX DX SI			; Preserve registers

	MOV CX, 0				; CX will be num bytes to write
	LEA SI, outBuffer			; SI -> outBuffer

	countBytes:
		MOV AL, [SI]			; AL := character in outBuffer
		CMP AL, 0			; If it's a null character
		JE writeName			; start writing the name
		
		INC CX				; Otherwise, inc CX since we write more
		INC SI				; SI -> next character in the name
		JMP countBytes			; Loop back until we reach null char
		
	writeName:

		MOV AH, writeFileINT		; Write to file
		MOV BX, outHandle		; file handle is outHandle
		LEA DX, outBuffer		; with data in outBuffer
		INT 21h	

	POP SI DX CX BX AX			; Restore registers
	RET
writeToFile ENDP

; -----------------------------------------
; Cleans out outBuffer and num
; On Exit:
; 	outBuffer is a null string
;	num := 0
; -----------------------------------------
clean PROC
	PUSH CX DI

	MOV num, 0				; num := 0

	LEA DI, outBuffer			; DI -> outBuffer
	MOV CX, 22				; We clean out 22 characters
	
	cleanLoop:
		MOV [DI], BYTE PTR 0		; Set to null character
		INC DI				; DI -> next char to clean
		LOOP cleanLoop			; Loop through all characters

	POP DI CX
	RET
clean ENDP

; -----------------------------------------
; Gets the next number in the file
; On Entry:
;	AL := 1st character of the number
; On Exit:
; 	num := next number of the file
;	AH := 0
;	AL := 1st CHAR of the name that's with this name
;	OR
;	atEOF := 1 if eof is after the number read
; -----------------------------------------
nextNum PROC
	PUSH BX DX				; Preserve registers

	MOV DX, 0 				; DX := 0 since it'll be our accumulator
	MOV DL, AL				; DX := value of 1st digit
	SUB DL, '0'

	MOV BX, 10				; BX := 10 to multiply

	nextNumLoop:
		MOV AH, 0
		CALL nextByteSkipSpace		; AL := next digit OR atEOF := 1

		CMP atEOF, 1			; If atEOF == 1
		JE nextNumExit			; Exit this proc
	
		CMP AL, 'A'			; If AL is a letter character
		JGE nextNumExit			; Exit this proc

		SUB AL, '0'			; AL := value of this digit
		PUSH AX				; Store this digit
		MOV AX, DX			; AX := accumulated value
		MUL BX				; AX := accumulated value shifted over 1 digit
		POP DX				; DX := stored digit
		ADD DX, AX			; DX += accumulated value

		JMP nextNumLoop			; Loop back until we get atEOF or letter char

	nextNumExit:
		MOV num, DX			; DX contains num by the time we get here
		
	POP DX BX
	RET
nextNum ENDP

; -----------------------------------------
; Gets the next name in the file
; On Entry:
;	AL := 1st character of the name
; On Exit:
; 	name := next name of the file
;	AL := 1st CHAR of the number that's with this name
; -----------------------------------------
nextName PROC
	PUSH DI					; Preserve registers

	LEA DI, outBuffer			; DI -> name
	nextNameLoop:
		MOV [DI], AL			; Write the character into the name
		CALL nextByteSkipSpace		; AL := next non-whitespace char
		
		CMP AL, '9'			; If AL is a number character
		JLE nextNameExit			; Then exit the proc

		INC DI				; Otherwise, DI -> next char
		JMP nextNameLoop

	nextNameExit:
		MOV [DI + 1], BYTE PTR 0Dh	; Insert carriage return
		MOV [DI + 2], BYTE PTR 0Ah	; Insert line feed char

	POP DI					; Restore registers
	RET
nextName ENDP

; -----------------------------------------
; Get the next byte in the proc that is not whitespace
; Calls nextByte repeatedly until it's not whitespace
; On Exit:
; 	AL := next non-whitespace character
;	OR atEOF := 1
; -----------------------------------------
nextByteSkipSpace PROC
	skipWS:
		CALL nextByte			; AL := next byte

		CMP atEOF, 1			; If atEOF turned on
		JE skipWSExit			; Exit the proc

		CMP AL, ' '			; Otherwise, if we ran into whitespace
		JLE skipWS			; try again

						; If not whitespace,
						; exit proc
	skipWSExit:
	RET
nextByteSkipSpace ENDP


; -----------------------------------------
; Get the next byte in the file
; On Entry:
;	[SI] is the next byte to read from the file
;	Does nothing if atEOF == 1
; On Exit:
;	AL contains the next byte
;	SI is moved to the byte after
;	OR atEOF := 1 and SI -> inBuffer
; -----------------------------------------
nextByte PROC
	CMP atEOF, 1				; If atEOF == 1
	JE nextByteExit				; Do nothing

	CMP SI, OFFSET inBufferEnd		; If SI is NOT the end of inBuffer
	JNE skipBufferReload			; Skip reloading the buffer

	CALL emptyBuffer			; Fill inBuffer of 0 chars
	CALL reloadBuffer			; Reload the buffer

	CMP atEOF, 1				; If we've reached EOF
	JE nextByteExit				; Exit the proc

	skipBufferReload:
			
	MOV AL, [SI]				; AL := next byte
	INC SI

	nextByteExit:
	RET
nextByte ENDP


; -----------------------------------------
; Fills the inBuffer with 0 chars
; -----------------------------------------
emptyBuffer PROC
	PUSH CX SI				; Preserve registers

	LEA SI, inBuffer			; SI -> inBuffer
	MOV CX, blockSize			; CX := blockSize

	emptyBufferLoop:
		MOV [SI], BYTE PTR 0		; Put null char in the buffer
		INC SI				; Move to next char
		LOOP emptyBufferLoop		; Loop until we do it blockSize times
	
	POP SI CX				; Restore registers
	RET
emptyBuffer ENDP


; -----------------------------------------
; Reloads the buffer
; Terminates the program if there's an error
; On Exit:
;	SI -> inBuffer
;	inBuffer is reloaded
;	If no bytes are read, atEOF := 1
; -----------------------------------------
reloadBuffer PROC
	PUSH AX BX CX DX			; Preserve registers

	MOV AH, readFileINT			; Read from file
	MOV BX, inHandle			; Use inHandle
	MOV CX, blockSize			; Request blockSize bytes
	LEA DX, inBuffer			; Read into inBuffer
	INT 21h
	JC readErr				; If error, show msg & terminate

	LEA SI, inBuffer			; [SI] is start of inBuffer
	
	CMP AX, 0				; If bytes were actually read,
	JNE reloadExit				; Exit the proc

	MOV atEOF, 1				; Otherwise, we've reached EOF

	JMP reloadExit				; Exit the proc


	readErr:
		MOV AH, printINT		; Print msg
		LEA DX, errorReadMsg		; "Error reading!"
		INT 21h
		MOV AH, stopINT			; Terminate program
		INT 21h
	
	reloadExit:
	POP DX CX BX AX				; Restore registers
	RET
reloadBuffer ENDP

; -----------------------------------------
; Closes the file handles for input and output files
; Terminates the program if there was an error.
; On Exit:
; 	inHandle & outHandle are closed file handles
; -----------------------------------------
closeFiles PROC
	PUSH AX BX DX				; Preserve registers

	MOV AH, closeFileINT			; Close file
	MOV BX, inHandle			; with the inHandle
	INT 21h
	JC closeFileErr				; If error, show msg & terminate

	MOV BX, outHandle			; Close with outHandle
	INT 21h
	JC closeFileErr				; If error, show msg & terminate

	JMP closeFilesExit			; We're done closing files, exit proc
	
	closeFileErr:
		MOV AH, printINT		; Print msg
		LEA DX, errorCloseMsg		; "Error closing!"
		INT 21h
		MOV AH, stopINT			; Terminate the program
		INT 21h

	closeFilesExit:
	POP DX BX AX				; Preserve registers
	RET
closeFiles ENDP

; -----------------------------------------
; Opens the file handles for input and output files
; Terminates the program if there was an error.
; On Entry:
;	inFileName & outFileName are ASCIIZ strings of the file names
; On Exit:
; 	inHandle & outHandle are open file handles
; -----------------------------------------
openFiles PROC
	PUSH AX CX DX				; Preserve registers

	MOV AH, openFileINT			; Open file
	MOV AL, 0				; In read mode
	LEA DX, inFileName			; whose name is the name of the input file
	INT 21h
	JC openFileErr				; If there was an error, display message & terminate

	MOV inHandle, AX			; Move the newly created file handle into inHandle

	MOV AH, createFileINT			; Create file
	MOV CL, 0				; with no special attributes
	LEA DX, outFileName			; whose name is the name of the output file
	INT 21h
	JC openFileErr				; If there was an error, display message & terminate

	MOV outHandle, AX			; Move the newly created file handle into outHandle
	JMP openFilesExit			; then exit the proc.

	openFileErr:
		MOV AH, printINT		; Print a message
		LEA DX, errorOpenMsg		; "Error opening!"
		INT 21h
		MOV AH, stopINT			; Then terminate the program
		INT 21h
		
	openFilesExit:
	POP DX CX AX				; Restore registers
	RET
openFiles ENDP

; -----------------------------------------
; Reads the command tail
; On Entry:
;	ES -> Command tail
; On Exit:
;	inFileName contains file name the user put in
;	limit contains the lower limit the user puts in
; -----------------------------------------
readCommandTail PROC
	PUSH AX BX CX DX SI DI			; Preserve registers

	MOV CX, 0				; CX := length of command tail
	MOV CL, ES:[80h]

	MOV SI, 82h				; ES:[SI] -> char after whitespace in 
						; command tail

	LEA DI, inFileName			; DI -> inFileName

	commandTailName:
		MOV AL, ES:[SI]			; AL := next char
		CMP AL, ' '			; If AL == ' '
		JE commandTailLimit		; Then start reading the limit

		MOV [DI], AL			; Otherwise, read the char into file name
		INC DI				; DI -> next char of inFileName
		INC SI				; ES:[SI] -> next char of command tail
		DEC CX				; We've read a character, so decrement CX
		JMP commandTailName		; Repeat until we run into the limit

	commandTailLimit:
		SUB CX, 2			; We've read the space and the previous char
						; so decrease counter by 2
		INC SI				; ES:[SI] -> next char
		MOV AX, 0			; AX := 0 for accumulation
		MOV BX, 10			; BX := 10 for moving digits over
	limitLoop:
		MOV DX, 0			; DX := next digit value in command tail
		MOV DL, ES:[SI]
		SUB DL, '0'
		DEC CX				; We've just read a char
		ADD AX, DX			; AX += digit we just read

		CMP CX, 0			; If we've read all characters
		JE commandTailExit		; Jump to where we exit

		MUL BX				; Make room for new digit by AX := AX * 10
		INC SI				; ES:[SI] -> next char

		JMP limitLoop			; Repeat until we've read all characers in 
						; the command tail

	commandTailExit:
		MOV limit, AX			; AX contains the limit by this time

	POP DI SI DX CX BX AX			; Restore Registers
	RET
readCommandTail ENDP

; ========================================================================================================================
;
; Writes the value of AX in some arbitrary spot on the screen
;
writeAXToScreen PROC
	PUSH AX BX CX DX SI

	MOV CX, 0
	MOV DX, 0
	MOV BX, 10

	waxtsLoop:
		
		CMP AX, 0
		JE waxtsExit

		DIV BX

		MOV SI, 160*5+28
		SUB SI, CX
		ADD DL, '0'
		MOV DH, 024h
		MOV ES:[SI], DL
		MOV DX, 0
		ADD CX, 2

		JMP waxtsLoop

	waxtsExit:
	
	POP SI DX CX BX AX
	RET
writeAXToScreen ENDP

;
; Writes the value of curName onto some arbitrary spot in screen memory
;
writeCurName PROC
	PUSH AX CX SI DI
	MOV CX, 20
	LEA SI, outBuffer
	MOV DI, 160*4 + 20

	wcnLoop:
		MOV Ah, 02AH
		MOV AL, [SI]
		MOV ES:[DI], AX
		INC SI 
		ADD DI, 2
		LOOP wcnLoop
	POP DI SI CX AX
	RET		

writeCurName ENDP

; -----------------------------------------
; Main Proc
; -----------------------------------------
MyMain PROC
	MOV AX, MyData				; DS -> MyData
	MOV DS, AX

	CALL readCommandTail			; Read command tail and process it

	MOV AX, 0B800h				; ES -> Screen Memory
	MOV ES, AX

	CALL openFiles				; Open file handles

	MOV DX, limit				; DX := limit
	CALL reloadBuffer			; Initially reload the buffer
	CALL nextByteSkipSpace			; Al := 1st character that isn't whitespace
	processFile:
		CMP atEOF, 1			; If we've reached the eof
		JE doneProcessing		; We're done processing the file

		CALL clean			; outBuffer := null string, num := 0

		CALL nextName			; outBuffer := next name in the file
		CALL nextNum			; num := next number in the file

		CMP num, DX			; If num <= limit
		JLE processFile			; Try reading the next one in the file

		CALL writeToFile		; Otherwise, write it to the file
		
		JMP processFile			; Then process the next name/num in the file

	doneProcessing:

	CALL closeFiles				; Close file handles

	MOV AH, stopINT				; Terminate the program
	INT 21h
	
MyMain ENDP



MyCode ENDS



END MyMain

