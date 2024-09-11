section .data
    array_size equ 4096         ; Size of the arrays (number of floats)
    align_size equ 16           ; Alignment size (16 bytes for SSE)
    elapsed_time_simd_msg db 'SIMD addition time: ', 0
    elapsed_time_loop_msg db 'Loop-based addition time: ', 0
    elapsed_time_dot_product_simd_msg db 'SIMD dot product time: ', 0
    elapsed_time_dot_product_loop_msg db 'Loop-based dot product time: ', 0
    dot_product_simd_msg db 'SIMD dot product: ', 0
    dot_product_loop_msg db 'Loop-based dot product: ', 0
    arrays_mismatch_msg db 'Arrays do not match', 0
    num_fmt db '%.2f', 0
    char_fmt db '%c', 0
    time_fmt db '%ld.%09ld seconds', 0
    str_fmt db '%s', 0

section .bss
    first_array_ptr  resd 1         ; Pointer to dynamically allocated input array
    second_array_ptr resd 1         ; Pointer to dynamically allocated input array
    result_array_simd_ptr resd 1    ; Pointer to dynamically allocated result array
    result_array_loop_ptr resd 1    ; Pointer to dynamically allocated result array
    dot_product_loop resd 1         ; Result of the loop-based dot product
    dot_product_simd resd 1         ; Result of the SIMD dot product
    start_time   resb 8             ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    end_time     resb 8             ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    elapsed_time resb 8             ; Store seconds (4 bytes) and nanoseconds (4 bytes)

section .text
    global _start
    extern posix_memalign
    extern free
    extern printf
    extern fflush
    extern clock_gettime
    extern rand
    extern srand
    extern time

_start:
    ; Initialize random number generator
    call initialize_random_number_generator

    ; Allocate aligned memory
    call allocate_aligned_memory

    ; Fill first array
    push array_size
    push dword [first_array_ptr]
    call fill_array
    add esp, 8

    ; Fill second array
    push array_size
    push dword [second_array_ptr]
    call fill_array
    add esp, 8

.add_arrays_simd:
    ; Start timing
    call start_timing

    ; Call SIMD function
    push array_size
    push dword [result_array_simd_ptr]
    push dword [second_array_ptr]
    push dword [first_array_ptr]
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
    push dword [result_array_loop_ptr]
    push dword [second_array_ptr]
    push dword [first_array_ptr]
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
    ; Check if arrays match
    push array_size
    push dword [result_array_simd_ptr]
    push dword [result_array_loop_ptr]
    call are_arrays_equal
    add esp, 12

    ; Check if arrays are equal
    cmp eax, 0
    jne .calculate_dot_product_simd

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

.calculate_dot_product_simd:
    ; Start timing
    call start_timing

    ; Calculate dot product
    push array_size
    push dword [second_array_ptr]
    push dword [first_array_ptr]
    call calculate_dot_product_simd
    add esp, 12
    mov [dot_product_simd], eax

    ; End timing
    call end_timing

    ; Print elapsed time message
    push elapsed_time_dot_product_simd_msg
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

    ; Print dot product message
    push dot_product_simd_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print dot product
    fld dword [dot_product_simd]
    sub esp, 8
    fstp qword [esp]
    push num_fmt
    call printf
    add esp, 12

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.calculate_dot_product_loop:
    ; Start timing
    call start_timing

    ; Calculate dot product
    push array_size
    push dword [second_array_ptr]
    push dword [first_array_ptr]
    call calculate_dot_product_loop
    add esp, 12
    mov [dot_product_loop], eax

    ; End timing
    call end_timing

    ; Print elapsed time message
    push elapsed_time_dot_product_loop_msg
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

    ; Print dot product message
    push dot_product_loop_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print dot product
    fld dword [dot_product_loop]
    sub esp, 8
    fstp qword [esp]
    push num_fmt
    call printf
    add esp, 12

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.free_memory:
    ; Free allocated memory
    call free_allocated_memory

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

    ; Epilogue: Restore the stack frame
    pop ebp
    ret

allocate_aligned_memory:
    ; Prologue: Set up the stack frame
    push ebp
    mov ebp, esp

    ; Allocate memory for first_array
    push dword array_size * 4
    push dword align_size
    push dword first_array_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for second_array
    push dword array_size * 4
    push dword align_size
    push dword second_array_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for result_array_simd
    push dword array_size * 4
    push dword align_size
    push dword result_array_simd_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for result_array_loop
    push dword array_size * 4
    push dword align_size
    push dword result_array_loop_ptr
    call posix_memalign
    add esp, 12

    ; Epilogue: Restore the stack frame
    pop ebp
    ret

free_allocated_memory:
    ; Prologue: Set up the stack frame
    push ebp
    mov ebp, esp

    ; Free the memory for result_array_loop
    push dword [result_array_loop_ptr]
    call free
    add esp, 4

    ; Free the memory for result_array_simd
    push dword [result_array_simd_ptr]
    call free
    add esp, 4

    ; Free the memory for second_array
    push dword [second_array_ptr]
    call free
    add esp, 4

    ; Free the memory for first_array
    push dword [first_array_ptr]
    call free
    add esp, 4

    ; Epilogue: Restore the stack frame
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

    ; Calculate number of full SSE chunks (4 floats per chunk)
    mov eax, ecx             ; Copy array size to EAX
    shr eax, 2               ; Divide by 4 to get the number of 128-bit chunks

.simd_loop:
    test eax, eax            ; Check if there are any chunks to process
    jz .check_remainder      ; If no chunks, jump to scalar loop

    ; Load 4 floats from array1 and array2 into XMM registers
    movaps xmm0, [esi]   ; Load array1 values into xmm0
    movaps xmm1, [edi]   ; Load array2 values into xmm1

    ; Perform SIMD addition (4 floats at once)
    addps xmm0, xmm1

    ; Store the result in the result array
    movaps [edx], xmm0

    ; Advance the pointers by 4 floats (16 bytes)
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
    fld dword [esi]          ; Load first array element
    fadd dword [edi]         ; Add second array element
    fstp dword [edx]         ; Store result in result array

    ; Advance the pointers by 1 float (4 bytes)
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

    fld dword [esi]          ; Load first array element
    fadd dword [edi]         ; Add second array element
    fstp dword [edx]         ; Store result in result array

    ; Advance the pointers by 1 float (4 bytes)
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
    pop ebp
    ret

calculate_dot_product_simd:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the first array
    ; [ebp+12] -> Address of the second array
    ; [ebp+16] -> Size of the arrays (number of elements)

    mov edi, [ebp+8]          ; Load address of the first array into EDI
    mov esi, [ebp+12]         ; Load address of the second array into ESI
    mov ecx, [ebp+16]         ; Load size of the arrays into ECX

    ; Calculate how many full 4-element blocks to process
    mov eax, ecx
    shr ecx, 2                  ; Divide the size by 4 (number of full SIMD blocks)

    xorps xmm0, xmm0            ; Clear xmm0 to accumulate the result
    xor edx, edx                ; Zero out the remainder counter

.simd_loop:
    test ecx, ecx               ; Check if there are full 4-element blocks to process
    jz .remainder               ; If none, jump to the remainder handling

    ; Load 4 floats from array1 and array2
    movaps xmm1, [edi+edx*4]    ; Load 4 floats from vec1 into xmm1
    movaps xmm2, [esi+edx*4]    ; Load 4 floats from vec2 into xmm2
    mulps xmm1, xmm2            ; Multiply xmm1 and xmm2 (element-wise)
    addps xmm0, xmm1            ; Add result to xmm0

    add edx, 4                  ; Increment remainder counter by 4
    dec ecx                     ; Decrement loop counter
    jmp .simd_loop              ; Repeat loop

.remainder:
    ; Check if there are remaining elements (1 to 3)
    and eax, 3                  ; Get the remainder (number of leftover elements)
    jz .horizontal_sum          ; If no remainder, jump to horizontal sum

    ; Load and process remaining elements
    xorps xmm1, xmm1            ; Clear xmm1 to zero out unused elements

    cmp eax, 1
    jl .process_remainder       ; If less than 1 (no elements), skip
    movss xmm1, [edi+edx*4]     ; Load 1 element from vec1 into xmm1
    mulss xmm1, [esi+edx*4]     ; Multiply with 1 element from vec2
    add edx, 1                  ; Move to the next element

    cmp eax, 2
    jl .process_remainder        ; If less than 2 elements, skip
    movss xmm2, [edi+edx*4]     ; Load 2nd element from vec1 into xmm2
    mulss xmm2, [esi+edx*4]     ; Multiply with 2nd element from vec2
    addss xmm1, xmm2            ; Accumulate in xmm1
    add edx, 1                  ; Move to the next element

    cmp eax, 3
    jl .process_remainder        ; If less than 3 elements, skip
    movss xmm2, [edi+edx*4]     ; Load 3rd element from vec1 into xmm2
    mulss xmm2, [esi+edx*4]     ; Multiply with 3rd element from vec2
    addss xmm1, xmm2            ; Accumulate in xmm1

.process_remainder:
    addps xmm0, xmm1            ; Add the result from the remainder to xmm0

.horizontal_sum:
    ; Horizontal addition to get the final SIMD dot product
    movaps xmm1, xmm0           ; Move result to xmm1
    movhlps xmm1, xmm0          ; Move high part of xmm0 to low part of xmm1
    addps xmm0, xmm1            ; Add low and high parts

    movaps xmm1, xmm0
    shufps xmm1, xmm0, 1        ; Shuffle to add remaining elements
    addss xmm0, xmm1            ; Add the last two elements

    ; Store the final dot product result from xmm0 into memory
    sub esp, 4                ; Allocate 4 bytes on the stack
    movss [esp], xmm0         ; Move the scalar result from xmm0 to memory
    mov eax, [esp]            ; Move the result from memory to EAX (as an integer)
    add esp, 4                ; Clean up the stack space

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebp
    ret

calculate_dot_product_loop:
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

    mov esi, [ebp + 8]         ; Load address of the first array into ESI
    mov edi, [ebp + 12]        ; Load address of the second array into EDI
    mov ecx, [ebp + 16]        ; Load size of the arrays into ECX

    fldz                      ; Clear FPU register st(0) to accumulate the result

.loop:
    test ecx, ecx             ; Check if all elements are processed
    jz .done

    ; Load float from array1 and array2
    fld dword [esi]           ; Load float from array1 into st(0)
    fmul dword [edi]          ; Multiply it with the float from array2 (st(0) = array1[i] * array2[i])

    ; Accumulate the result in st(0)
    fadd                      ; Add to st(0)

    ; Move to the next element
    add esi, 4                ; Move to next element in array1
    add edi, 4                ; Move to next element in array2
    dec ecx                   ; Decrement loop counter
    jmp .loop

.done:
    ; Store the final result from st(0) to memory
    sub esp, 4                ; Allocate space for result
    fstp dword [esp]          ; Store the result in memory (on the stack)

    ; Load the result into eax
    mov eax, [esp]            ; Load the result from memory into eax
    add esp, 4                ; Clean up the stack space for result

    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop ecx
    pop ebp
    ret

fill_array:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the array
    ; [ebp+12] -> Size of the array (number of elements)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the array into ESI
    mov ecx, [ebp+12]        ; Load size of the array into ECX

.fill_loop:
    test ecx, ecx              ; Check if there are any remaining elements
    jz .done                   ; If no remainder, we're done

    call get_random_integer    ; Generate a random integer in eax
    cvtsi2ss xmm0, eax         ; Convert the random integer to a float
    mov eax, 0x7fffffff        ; RAND_MAX
    cvtsi2ss xmm1, eax         ; Convert RAND_MAX to float
    divss xmm0, xmm1           ; Normalize: divide by RAND_MAX to get a float between 0 and 1
    movss dword [esi], xmm0    ; Store the float in the array
    add esi, 4                 ; Move to the next float (each float is 4 bytes)

    dec ecx                    ; Decrease remainder counter
    jmp .fill_loop             ; Repeat until no remaining elements

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop ecx
    pop ebp
    ret

get_random_integer:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx

    call rand

    ; Epilogue: Restore stack frame and return
    pop ecx
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

    mov eax, [esi]           ; Load float from first array
    cmp eax, [edi]           ; Compare float from second array
    jne .not_equal           ; If not equal, arrays are not equal

    ; Advance the pointers by 1 float (4 bytes)
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

    push ecx                 ; Save the original value of ECX
    fld dword [esi]          ; Load the float from the array into FPU stack
    sub esp, 8               ; Allocate space on the stack for printf
    fstp qword [esp]         ; Store the float in the stack (printf expects 64-bit float)
    push num_fmt             ; Push format string onto stack
    call printf              ; Call print_format
    add esp, 12              ; Pop arguments off the stack
    pop ecx                  ; Restore the original value of ECX

    mov eax, ' '             ; Load space character into EAX
    push eax                 ; Push space character onto stack
    push char_fmt            ; Push format string onto stack
    call print_format        ; Call print_format
    add esp, 8               ; Pop arguments off the stack

    add esi, 4               ; Advance the pointer by 1 float (4 bytes)
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
