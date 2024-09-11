section .data
    array_size equ 4096        ; Size of the arrays (number of integers)
    first_array times array_size dd 0
    second_array times array_size dd 0
    result_array_simd times array_size dd 0
    result_array_loop times array_size dd 0
    elapsed_time_simd_msg db 'SIMD addition time: ', 0
    elapsed_time_loop_msg db 'Loop-based addition time: ', 0
    arrays_mismatch_msg db 'Arrays do not match', 0
    num_fmt db '%d', 0
    char_fmt db '%c', 0
    time_fmt db '%ld.%09ld seconds', 0
    str_fmt db '%s', 0

section .bss
    start_time   resb 8    ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    end_time     resb 8    ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    elapsed_time resb 8    ; Store seconds (4 bytes) and nanoseconds (4 bytes)

section .text
    global _start
    extern printf
    extern fflush
    extern clock_gettime
    extern rand
    extern srand
    extern time

_start:
    ; Initialize random number generator
    call initialize_random_number_generator

    ; Fill arrays
    push array_size
    push first_array
    call fill_array
    add esp, 8

    push array_size
    push second_array
    call fill_array
    add esp, 8

.add_arrays_simd:
    ; Start timing
    call start_timing

    ; Call SIMD function
    push array_size
    push result_array_simd
    push second_array
    push first_array
    call add_arrays_simd
    add esp, 16

    ; End timing
    call end_timing

    ; Print elapsed time message
    push elapsed_time_simd_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print elapsed time
    call print_elapsed_time

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.add_arrays_loop:
    ; Start timing
    call start_timing

    ; Call loop function
    push array_size
    push result_array_loop
    push second_array
    push first_array
    call add_arrays_loop
    add esp, 16

    ; End timing
    call end_timing

    ; Print elapsed time message
    push elapsed_time_loop_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print elapsed time
    call print_elapsed_time

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.compare_arrays:
    ; Compare arrays
    push array_size
    push result_array_simd
    push result_array_loop
    call are_arrays_equal
    add esp, 12

    ; Check if arrays are equal
    cmp eax, 0
    jne .exit

    ; Print arrays mismatch message
    push arrays_mismatch_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.exit:
    ; Exit program
    mov eax, 1              ; Syscall number for exit
    xor ebx, ebx            ; Return code 0
    int 0x80

initialize_random_number_generator:
    ; Prologue: Set up the stack frame
    push ebp
    mov ebp, esp

    push dword 0           ; Push NULL as the argument to time()
    call time              ; Call time(NULL)
    add esp, 4             ; Clean up the stack (remove the NULL argument)

    push eax               ; Push the result of time() as the argument to srand()
    call srand             ; Call srand() to seed the random number generator
    add esp, 4             ; Clean up the stack (remove the argument to srand())

    ; Epilogue: Clean up the stack frame
    pop ebp
    ret

fill_array:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the array
    ; [ebp+12] -> Size of the array (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the array into ESI
    mov ecx, [ebp+12]        ; Load size of the array into ECX

.fill_loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                 ; If no remainder, we're done

    call get_random_integer  ; Generate a random number
    mov [esi], eax           ; Store the value in the array
    add esi, 4               ; Advance the pointer by 1 integer (4 bytes)
    dec ecx                  ; Decrease remainder counter
    jmp .fill_loop           ; Repeat until no remaining elements

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop ecx
    pop eax
    pop ebp
    ret

get_random_integer:
    ; Epilogue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx

    call rand

    ; Epilogue: Restore stack frame and return
    pop ecx
    pop ebp
    ret

add_arrays_simd:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the first array
    ; [ebp+12] -> Address of the second array
    ; [ebp+16] -> Address of the result array
    ; [ebp+20] -> Size of the arrays (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the first array into ESI
    mov edi, [ebp+12]        ; Load address of the second array into EDI
    mov edx, [ebp+16]        ; Load address of the result array into EDX
    mov ecx, [ebp+20]        ; Load size of the arrays into ECX

    ; Calculate number of full SSE chunks (4 integers per chunk)
    mov eax, ecx             ; Copy array size to EAX
    shr eax, 2               ; Divide by 4 to get the number of 128-bit chunks

.simd_loop:
    test eax, eax            ; Check if there are any chunks to process
    jz .check_remainder      ; If no chunks, jump to scalar loop

    ; Load elements from first_array and second_array using SSE
    movdqu xmm0, [esi]       ; Load 4 integers from first array into XMM0
    movdqu xmm1, [edi]       ; Load 4 integers from second array into XMM1

    ; Perform SIMD addition
    paddd xmm0, xmm1         ; Add packed integers from XMM1 to XMM0, result in XMM0

    ; Store result back to memory
    movdqu [edx], xmm0       ; Store result into result_array

    ; Advance the pointers by 4 integers (16 bytes)
    add esi, 16              ; Move first array pointer by 16 bytes
    add edi, 16              ; Move second array pointer by 16 bytes
    add edx, 16              ; Move result array pointer by 16 bytes

    dec eax                  ; Decrease chunk counter
    jmp .simd_loop           ; Repeat SIMD loop

.check_remainder:
    ; Handle remaining elements (if array size is not a multiple of 4)
    and ecx, 3               ; Get the remainder of the array_size / 4

.scalar_loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                 ; If no remainder, we're done

    ; Scalar addition for remaining elements
    mov eax, [esi]           ; Load integer from first array
    add eax, [edi]           ; Add integer from second array
    mov [edx], eax           ; Store result in result array

    ; Advance the pointers by 1 integer (4 bytes)
    add esi, 4
    add edi, 4
    add edx, 4

    dec ecx                 ; Decrease remainder counter
    jmp .scalar_loop        ; Repeat until no remaining elements

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

add_arrays_loop:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the first array
    ; [ebp+12] -> Address of the second array
    ; [ebp+16] -> Address of the result array
    ; [ebp+20] -> Size of the arrays (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the first array into ESI
    mov edi, [ebp+12]        ; Load address of the second array into EDI
    mov edx, [ebp+16]        ; Load address of the result array into EDX
    mov ecx, [ebp+20]        ; Load size of the arrays into ECX

.loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                  ; If no remainder, we're done

    ; Scalar addition for remaining elements
    mov eax, [esi]           ; Load integer from first array
    add eax, [edi]           ; Add integer from second array
    mov [edx], eax           ; Store result in result array

    ; Advance the pointers by 1 integer (4 bytes)
    add esi, 4
    add edi, 4
    add edx, 4

    dec ecx                 ; Decrease remainder counter
    jmp .loop               ; Repeat until no remaining elements

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

are_arrays_equal:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the first array
    ; [ebp+12] -> Address of the second array
    ; [ebp+16] -> Size of the arrays (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the first array into ESI
    mov edi, [ebp+12]        ; Load address of the second array into EDI
    mov ecx, [ebp+16]        ; Load size of the arrays into ECX

    ; Compare the arrays
.compare_loop:
    test ecx, ecx            ; Check if there are any elements in the array
    jz .equal                 ; If no elements, arrays are equal

    mov eax, [esi]           ; Load integer from first array
    cmp eax, [edi]           ; Compare integer from second array
    jne .not_equal           ; If not equal, arrays are not equal

    ; Advance the pointers by 1 integer (4 bytes)
    add esi, 4
    add edi, 4
    dec ecx
    jmp .compare_loop

.not_equal:
    mov eax, 0               ; Set result to 0
    jmp .done                ; We're done

.equal:
    mov eax, 1               ; Set result to 1
    jmp .done                ; We're done

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop ecx
    pop ebp
    ret

print_array:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the array
    ; [ebp+12] -> Size of the array (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the array into ESI
    mov ecx, [ebp+12]        ; Load size of the array into ECX

.loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                 ; If no remainder, we're done

    mov eax, [esi]           ; Load integer from array
    push eax                 ; Push integer onto stack
    push num_fmt             ; Push format string onto stack
    call print_format        ; Call print_format
    add esp, 8               ; Pop arguments off the stack

    mov eax, ' '             ; Load space character into EAX
    push eax                 ; Push space character onto stack
    push char_fmt            ; Push format string onto stack
    call print_format        ; Call print_format
    add esp, 8               ; Pop arguments off the stack

    add esi, 4               ; Advance the pointer by 1 integer (4 bytes)
    dec ecx                 ; Decrease remainder counter
    jmp .loop               ; Repeat until no remaining elements

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop ecx
    pop eax
    pop ebp
    ret

print_format:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the format string
    ; [ebp+12] -> Address of the arguments

    push dword [ebp+12]      ; Push the address of the arguments
    push dword [ebp+8]       ; Push the address of the format string
    call printf              ; Call printf
    add esp, 8               ; Pop arguments off the stack

    push 0                   ; stdout
    call fflush              ; Call fflush
    add esp, 4               ; Pop arguments off the stack

.done:
    ; Epilogue: Restore stack frame and return
    pop ecx
    pop ebp
    ret

start_timing:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax

    lea eax, [start_time]                  ; Load address of start_time
    push eax                               ; Push address of start_time structure
    push dword 1                           ; Push CLOCK_MONOTONIC
    call clock_gettime                     ; Call clock_gettime
    add esp, 8                             ; Clean up stack (2 arguments)

    ; Epilogue: Restore stack frame and return
    pop eax
    pop ebp
    ret

end_timing:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx

    lea eax, [end_time]                    ; Load address of end_time
    push eax                               ; Push address of end_time structure
    push dword 1                           ; Push CLOCK_MONOTONIC
    call clock_gettime                     ; Call clock_gettime
    add esp, 8                             ; Clean up stack

    ; Calculate elapsed time (seconds and nanoseconds)
    ; Subtract start_time from end_time (seconds)
    mov eax, [end_time]                    ; Load end_time seconds
    sub eax, [start_time]                  ; Subtract start_time seconds
    mov ebx, eax                           ; Store result in ebx (elapsed seconds)

    ; Subtract start_time nanoseconds from end_time nanoseconds
    mov eax, [end_time + 4]                ; Load end_time nanoseconds
    sub eax, [start_time + 4]              ; Subtract start_time nanoseconds
    mov ecx, eax                           ; Store result in ecx (elapsed nanoseconds)

    ; If nanoseconds are negative, adjust seconds
    test ecx, ecx                          ; Check if nanoseconds are negative
    jge .done                              ; Jump if nanoseconds are positive
    dec ebx                                ; Adjust seconds
    add ecx, 1000000000                    ; Adjust nanoseconds

.done:
    mov [elapsed_time], ebx
    mov [elapsed_time + 4], ecx

    ; Epilogue: Restore stack frame and return
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

print_elapsed_time:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp

    push dword [elapsed_time + 4]          ; Push nanoseconds
    push dword [elapsed_time]              ; Push seconds
    push dword time_fmt                    ; Push format string
    call printf                            ; Call printf
    add esp, 12                            ; Clean up stack (3 arguments)

    ; Epilogue: Restore stack frame and return
    pop ebp
    ret
