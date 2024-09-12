section .data
    align_size equ 16           ; Alignment size (16 bytes for SSE)
    matrix_size equ 512         ; Size of the matrices (number of floats). Should be multiple of 4
    tolerance dd 0.0001         ; Tolerance for comparing floats
    abs_mask dd 0x7FFFFFFF      ; Mask for getting the absolute value
    elapsed_time_simd_msg db 'SIMD matrix multiplication time: ', 0
    elapsed_time_simd_transposed_msg db 'SIMD matrix multiplication time(with transposed): ', 0
    elapsed_time_loop_msg db 'Loop-based matrix multiplication time: ', 0
    matrices_loop_simd_transposed_mismatch_msg db 'Loop and SIMD with transposed result matrices do not match', 0
    matrices_loop_simd_mismatch_msg db 'Loop and SIMD result matrices do not match', 0
    str_fmt db '%s', 0
    num_fmt db '%f', 0
    char_fmt db '%c', 0
    time_fmt db '%ld.%09ld seconds', 0

section .bss
    first_matrix_ptr resd 1
    second_matrix_ptr resd 1
    second_matrix_transposed_ptr resd 1
    result_matrix_simd_ptr resd 1
    result_matrix_simd_transposed_ptr resd 1
    result_matrix_loop_ptr resd 1
    start_time resb 8           ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    end_time resb 8             ; Store seconds (4 bytes) and nanoseconds (4 bytes)
    elapsed_time resb 8         ; Store seconds (4 bytes) and nanoseconds (4 bytes)

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

.fill_matrices:
    ; Fill first matrix
    push matrix_size
    push dword [first_matrix_ptr]
    call fill_matrix
    add esp, 8

    ; Fill second matrix
    push matrix_size
    push dword [second_matrix_ptr]
    call fill_matrix
    add esp, 8

.multiply_matrices_simd:
    ; Start timing
    call start_timing

    ; Multiply matrices
    push matrix_size
    push dword [result_matrix_simd_ptr]
    push dword [second_matrix_ptr]
    push dword [first_matrix_ptr]
    call multiply_matrices_simd
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

.multiply_matrices_simd_transposed:
    ; Start timing
    call start_timing

    ; Transpose the second matrix
    push matrix_size
    push dword [second_matrix_transposed_ptr]
    push dword [second_matrix_ptr]
    call transpose_matrix
    add esp, 12

    ; Multiply matrices
    push matrix_size
    push dword [result_matrix_simd_transposed_ptr]
    push dword [second_matrix_transposed_ptr]
    push dword [first_matrix_ptr]
    call multiply_matrices_transposed_simd
    add esp, 16

    ; End timing
    call end_timing

    ; Print elapsed time message
    push elapsed_time_simd_transposed_msg
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

.multiply_matrices_loop:
    ; Start timing
    call start_timing

    ; Multiply matrices
    push matrix_size
    push dword [result_matrix_loop_ptr]
    push dword [second_matrix_ptr]
    push dword [first_matrix_ptr]
    call multiply_matrices_loop
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

.compare_matrices_loop_and_simd_transposed:
    ; Compare matrices
    push matrix_size
    push dword [result_matrix_simd_transposed_ptr]
    push dword [result_matrix_loop_ptr]
    call are_matrices_equal
    add esp, 12

    cmp eax, 0
    jne .compare_matrices_loop_and_simd

    ; Print matrices are not equal message
    push matrices_loop_simd_transposed_mismatch_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.compare_matrices_loop_and_simd:
    ; Compare matrices
    push matrix_size
    push dword [result_matrix_simd_ptr]
    push dword [result_matrix_loop_ptr]
    call are_matrices_equal
    add esp, 12

    cmp eax, 0
    jne .free_memory
    
    ; Print matrices are not equal message
    push matrices_loop_simd_mismatch_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.free_memory:
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

    ; Epilogue: Clean up the stack frame
    pop ebp
    ret

allocate_aligned_memory:
    ; Prologue: Set up the stack frame
    push ebp
    mov ebp, esp

    ; Allocate memory for the first matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword first_matrix_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for the second matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword second_matrix_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for the second transposed matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword second_matrix_transposed_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for the result matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword result_matrix_simd_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for the result matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword result_matrix_simd_transposed_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for the result matrix
    push dword matrix_size * matrix_size * 4
    push dword align_size
    push dword result_matrix_loop_ptr
    call posix_memalign
    add esp, 12

    ; Epilogue: Clean up the stack frame
    pop ebp
    ret

free_allocated_memory:
    ; Prologue: Set up the stack frame
    push ebp
    mov ebp, esp

    ; Free the memory for result_matrix_loop
    push dword [result_matrix_loop_ptr]
    call free
    add esp, 4

    ; Free the memory for result_matrix_simd_transposed
    push dword [result_matrix_simd_transposed_ptr]
    call free
    add esp, 4

    ; Free the memory for result_matrix_simd
    push dword [result_matrix_simd_ptr]
    call free
    add esp, 4

    ; Free the memory for second_matrix_transposed
    push dword [second_matrix_transposed_ptr]
    call free
    add esp, 4

    ; Free the memory for second_matrix
    push dword [second_matrix_ptr]
    call free
    add esp, 4

    ; Free the memory for first_matrix
    push dword [first_matrix_ptr]
    call free
    add esp, 4

    ; Epilogue: Clean up the stack frame
    pop ebp
    ret

transpose_matrix:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function arguments (on stack):
    ; [ebp+8]  -> Address of the source matrix
    ; [ebp+12] -> Address of the destination matrix
    ; [ebp+16] -> Matrix size

    mov eax, [ebp+8]          ; Load the address of the source matrix
    mov ebx, [ebp+12]         ; Load the address of the destination matrix
    mov ecx, [ebp+16]         ; Load the matrix size

    ; Loop through rows and columns
    xor esi, esi              ; row_index = 0
.row_loop:
    cmp esi, ecx              ; if row_index >= matrix_size, end loop
    jge .done

    xor edi, edi              ; column_index = 0
.column_loop:
    cmp edi, ecx              ; if column_index >= matrix_size, end loop
    jge .next_row

    ; Calculate the address for source_matrix[row_index * matrix_size + column_index]
    mov edx, esi              ; row_index
    imul edx, ecx             ; row_index * matrix_size
    add edx, edi              ; row_index * matrix_size + column_index
    shl edx, 2                ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm0, [eax+edx]     ; Load the element from source_matrix into xmm0

    ; Calculate the address for destination_matrix[column_index * matrix_size + row_index]
    mov edx, edi              ; column_index
    imul edx, ecx             ; column_index * matrix_size
    add edx, esi              ; column_index * matrix_size + row_index
    shl edx, 2                ; (column_index * matrix_size + row_index) * 4 (float is 4 bytes)
    movss [ebx+edx], xmm0     ; Store the element into destination_matrix

    add edi, 1                ; column_index += 1
    jmp .column_loop

.next_row:
    add esi, 1                ; row_index += 1
    jmp .row_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

multiply_matrices_transposed_simd:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8]  -> Address of the first matrix
    ; [ebp+12] -> Address of the second matrix transposed
    ; [ebp+16] -> Address of the result matrix
    ; [ebp+20] -> Matrix size

    mov eax, [ebp+8]      ; Load the address of the first matrix
    mov ebx, [ebp+12]     ; Load the address of the second matrix
    mov ecx, [ebp+16]     ; Load the address of the result matrix
    mov edx, [ebp+20]     ; Load the matrix size

    ; Loop through rows and columns
    xor esi, esi          ; row_index = 0
.row_loop:
    cmp esi, edx          ; if row_index >= matrix_size, end loop
    jge .done

    xor edi, edi          ; column_index = 0
.column_loop:
    cmp edi, edx          ; if column_index >= matrix_size, end loop
    jge .next_row

    ; Set xmm0 to zero (accumulator for result_vector)
    pxor xmm0, xmm0       ; Zero out xmm0 for accumulation

    xor ebp, ebp          ; element_index = 0
.inner_loop:
    cmp ebp, edx          ; if element_index >= matrix_size, end loop
    jge .horizontal_sum

    ; Load 4 elements from row (row_index) of first_matrix
    push esi              ; Save row_index
    imul esi, edx         ; row_index * matrix_size
    add esi, ebp          ; row_index * matrix_size + element_index
    shl esi, 2            ; (row_index * matrix_size + element_index) * 4 (float is 4 bytes)
    movaps xmm1, [eax+esi]  ; Load 4 floats from first_matrix
    pop esi               ; Restore row_index

    ; Load 4 elements from column (column_index) of second_matrix_transposed
    push edi              ; Save column_index
    imul edi, edx         ; column_index * matrix_size
    add edi, ebp          ; column_index * matrix_size + element_index
    shl edi, 2            ; (column_index * matrix_size + element_index) * 4 (float is 4 bytes)
    movaps xmm2, [ebx+edi]  ; Load 4 floats from transposed matrix
    pop edi               ; Restore column_index

    ; Perform element-wise multiplication and accumulate
    mulps xmm1, xmm2     ; Multiply xmm1 and xmm2
    addps xmm0, xmm1     ; Accumulate the result in xmm0

    add ebp, 4           ; element_index += 4
    jmp .inner_loop

.horizontal_sum:
    ; Perform a horizontal sum of the accumulated result in xmm0
    movaps xmm1, xmm0    ; Copy xmm0 to xmm1
    movhlps xmm1, xmm0   ; Move high part of xmm0 to low part of xmm1
    addps xmm0, xmm1     ; Add high and low parts
    movaps xmm1, xmm0    ; Copy xmm0 to xmm1 again
    shufps xmm1, xmm0, 1 ; Shuffle for the next sum
    addps xmm0, xmm1     ; Sum again to get the final result

    ; Store the result in the result_matrix
    push esi              ; Save row_index
    imul esi, edx         ; row_index * matrix_size
    add esi, edi          ; row_index * matrix_size + column_index
    shl esi, 2            ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss [ecx+esi], xmm0 ; Store the scalar result
    pop esi               ; Restore row_index

    add edi, 1           ; column_index += 1
    jmp .column_loop

.next_row:
    add esi, 1           ; row_index += 1
    jmp .row_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

multiply_matrices_simd:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8]  -> Address of the first matrix
    ; [ebp+12] -> Address of the second matrix
    ; [ebp+16] -> Address of the result matrix
    ; [ebp+20] -> Matrix size

    mov eax, [ebp+8]      ; Load the address of the first matrix
    mov ebx, [ebp+12]     ; Load the address of the second matrix
    mov ecx, [ebp+16]     ; Load the address of the result matrix
    mov edx, [ebp+20]     ; Load the matrix size

    ; Loop through rows and columns
    xor esi, esi          ; row_index = 0
.row_loop:
    cmp esi, edx          ; if row_index >= matrix_size, end loop
    jge .done

    xor edi, edi          ; column_index = 0
.column_loop:
    cmp edi, edx          ; if column_index >= matrix_size, end loop
    jge .next_row

    ; Set xmm0 to zero (accumulator for result_vector)
    pxor xmm0, xmm0       ; Zero out xmm0 for accumulation

    xor ebp, ebp          ; element_index = 0
.inner_loop:
    cmp ebp, edx          ; if element_index >= matrix_size, end loop
    jge .horizontal_sum

    ; Load 4 elements from row (row_index) of first_matrix
    push esi              ; Save row_index
    imul esi, edx         ; row_index * matrix_size
    add esi, ebp          ; row_index * matrix_size + element_index
    shl esi, 2            ; (row_index * matrix_size + element_index) * 4 (float is 4 bytes)
    movaps xmm1, [eax+esi]  ; Load 4 floats from first_matrix
    pop esi               ; Restore row_index

    ; Load 4 elements from column (column_index) of second_matrix
    push ebp              ; Save element_index
    imul ebp, edx         ; element_index * matrix_size
    add ebp, edi          ; element_index * matrix_size + column_index
    shl ebp, 2            ; (element_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm2, [ebx+ebp] ; Load a single float from second_matrix
    pop ebp               ; Restore element_index

    push ebp              ; Save element_index
    add ebp, 1            ; element_index += 1
    imul ebp, edx         ; element_index * matrix_size
    add ebp, edi          ; element_index * matrix_size + column_index
    shl ebp, 2            ; (element_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm3, [ebx+ebp]  ; Load a single float from second_matrix
    insertps xmm2, xmm3, 0x10 ; Insert xmm3[0] into xmm2[1]
    pop ebp               ; Restore element_index

    push ebp              ; Save element_index
    add ebp, 2            ; element_index += 2
    imul ebp, edx         ; element_index * matrix_size
    add ebp, edi          ; element_index * matrix_size + column_index
    shl ebp, 2            ; (element_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm3, [ebx+ebp]  ; Load a single float from second_matrix
    insertps xmm2, xmm3, 0x20 ; Insert xmm3[0] into xmm2[2]
    pop ebp               ; Restore element_index

    push ebp              ; Save element_index
    add ebp, 3            ; element_index += 3
    imul ebp, edx         ; element_index * matrix_size
    add ebp, edi          ; element_index * matrix_size + column_index
    shl ebp, 2            ; (element_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm3, [ebx+ebp]  ; Load a single float from second_matrix
    insertps xmm2, xmm3, 0x30 ; Insert xmm3[0] into xmm2[3]
    pop ebp               ; Restore element_index

    ; Perform element-wise multiplication and accumulate
    mulps xmm1, xmm2     ; Multiply xmm1 and xmm2
    addps xmm0, xmm1     ; Accumulate the result in xmm0

    add ebp, 4           ; element_index += 4
    jmp .inner_loop

.horizontal_sum:
    ; Perform a horizontal sum of the accumulated result in xmm0
    movaps xmm1, xmm0    ; Copy xmm0 to xmm1
    movhlps xmm1, xmm0   ; Move high part of xmm0 to low part of xmm1
    addps xmm0, xmm1     ; Add high and low parts
    movaps xmm1, xmm0    ; Copy xmm0 to xmm1 again
    shufps xmm1, xmm0, 1 ; Shuffle for the next sum
    addps xmm0, xmm1     ; Sum again to get the final result

    ; Store the result in the result_matrix
    push esi              ; Save row_index
    imul esi, edx         ; row_index * matrix_size
    add esi, edi          ; row_index * matrix_size + column_index
    shl esi, 2            ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss [ecx+esi], xmm0 ; Store the scalar result
    pop esi               ; Restore row_index

    add edi, 1           ; column_index += 1
    jmp .column_loop

.next_row:
    add esi, 1           ; row_index += 1
    jmp .row_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

multiply_matrices_loop:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8]  -> Address of the first matrix
    ; [ebp+12] -> Address of the second matrix
    ; [ebp+16] -> Address of the result matrix
    ; [ebp+20] -> Matrix size

    mov eax, [ebp+8]          ; Load the address of the first matrix
    mov ebx, [ebp+12]         ; Load the address of the second matrix
    mov ecx, [ebp+16]         ; Load the address of the result matrix
    mov edx, [ebp+20]         ; Load the matrix size

    ; Loop through rows and columns
    xor esi, esi              ; row_index = 0
.row_loop:
    cmp esi, edx              ; if row_index >= matrix_size, end loop
    jge .done

    xor edi, edi              ; column_index = 0
.column_loop:
    cmp edi, edx              ; if column_index >= matrix_size, end loop
    jge .next_row

    ; Initialize sum to 0.0f
    fldz                      ; Load zero onto FPU stack (sum = 0.0f)

    xor ebp, ebp              ; element_index = 0
.inner_loop:
    cmp ebp, edx              ; if element_index >= matrix_size, end loop
    jge .store_result

    ; Calculate the address for first_matrix[row_index * matrix_size + element_index]
    push esi                  ; Save row_index
    imul esi, edx             ; esi = row_index * matrix_size
    add esi, ebp              ; esi += element_index
    shl esi, 2                ; esi = (row_index * matrix_size + element_index) * 4 (float is 4 bytes)
    fld dword [eax+esi]       ; Load first_matrix[row_index * matrix_size + element_index] onto FPU stack
    pop esi                   ; Restore row_index

    ; Calculate the address for second_matrix[element_index * matrix_size + column_index]
    push ebp                  ; Save element_index
    imul ebp, edx             ; ebp = element_index * matrix_size
    add ebp, edi              ; ebp += column_index
    shl ebp, 2                ; ebp = (element_index * matrix_size + column_index) * 4 (float is 4 bytes)
    fld dword [ebx+ebp]       ; Load second_matrix[element_index * matrix_size + column_index] onto FPU stack
    pop ebp                   ; Restore element_index

    ; Multiply and add to sum
    fmul st1                  ; Multiply st(0) by st(1) (first_matrix element * second_matrix element)
    fstp st1                  ; Store and pop the value of the FPU stack (first matrix element)
    fadd st0, st1             ; Add the result to the sum (st(0))
    fstp st1                  ; Store and pop the value of the FPU stack (previous sum)

    add ebp, 1                ; element_index += 1
    jmp .inner_loop

.store_result:
    ; Store the result from the FPU stack into result_matrix
    push esi                  ; Save row_index
    imul esi, edx             ; row_index * matrix_size
    add esi, edi              ; row_index * matrix_size + column_index
    shl esi, 2                ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    fstp dword [ecx+esi]      ; Store the sum into result_matrix[row_index * matrix_size + column_index]
    pop esi                   ; Restore row_index

    add edi, 1                ; column_index += 1
    jmp .column_loop

.next_row:
    add esi, 1                ; row_index += 1
    jmp .row_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

are_matrices_equal:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8]  -> Address of the first matrix
    ; [ebp+12] -> Address of the second matrix
    ; [ebp+16] -> Matrix size

    mov eax, [ebp+8]          ; Load the address of the first matrix
    mov ebx, [ebp+12]         ; Load the address of the second matrix
    mov ecx, [ebp+16]         ; Load the matrix size

    xor esi, esi              ; row_index = 0
.row_loop:
    cmp esi, ecx              ; if row_index >= matrix_size, end loop
    jge .equal                ; Jump to end if matrices are equal

    xor edi, edi              ; column_index = 0
.column_loop:
    cmp edi, ecx              ; if column_index >= matrix_size, end loop
    jge .next_row

    ; Calculate address for first_matrix[row_index * matrix_size + column_index]
    mov edx, esi              ; row_index
    imul edx, ecx             ; row_index * matrix_size
    add edx, edi              ; row_index * matrix_size + column_index
    shl edx, 2                ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm0, [eax+edx]     ; Load first_matrix element into xmm0

    ; Calculate address for second_matrix[row_index * matrix_size + column_index]
    mov edx, esi              ; row_index
    imul edx, ecx             ; row_index * matrix_size
    add edx, edi              ; row_index * matrix_size + column_index
    shl edx, 2                ; (row_index * matrix_size + column_index) * 4 (float is 4 bytes)
    movss xmm1, [ebx+edx]     ; Load second_matrix element into xmm1

    ; Find the absolute difference between the two elements
    subss xmm0, xmm1          ; xmm0 = first_matrix[row_index * matrix_size + column_index] - second_matrix[row_index * matrix_size + column_index]
    movd xmm2, [abs_mask]     ; Load the absolute value mask (0x7FFFFFFF) into xmm2
    andps xmm0, xmm2          ; Clear the sign bit in xmm0 (absolute value)

    ; Compare the two elements with tolerance
    movss xmm2, [tolerance]   ; Load the tolerance into xmm2
    comiss xmm0, xmm2         ; Compare the two floats
    jb .next_column           ; If less than tolerance, continue

    ; If any element is not equal, set result to 0 and exit
    mov eax, 0                ; Return 0 (not equal)
    jmp .done

.next_column:
    add edi, 1                ; column_index += 1
    jmp .column_loop

.next_row:
    add esi, 1                ; row_index += 1
    jmp .row_loop

.equal:
    mov eax, 1                ; Return 1 (equal)

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

fill_matrix:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ecx
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the matrix
    ; [ebp+12] -> Size of the matrix (number of elements in one dimension)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the array into ESI
    mov ecx, [ebp+12]        ; Load size of the matrix into ECX
    imul ecx, ecx            ; Multiply ECX by ECX to get the number of elements

.fill_loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                 ; If no remainder, we're done

    call get_random_integer    ; Generate a random integer in eax
    cvtsi2ss xmm0, eax         ; Convert the random integer to a float
    mov eax, 0x7fffffff        ; RAND_MAX
    cvtsi2ss xmm1, eax         ; Convert RAND_MAX to float
    divss xmm0, xmm1           ; Normalize: divide by RAND_MAX to get a float between 0 and 1
    movss dword [esi], xmm0    ; Store the float in the array
    add esi, 4                 ; Move to the next float (each float is 4 bytes)

    dec ecx                  ; Decrease remainder counter
    jmp .fill_loop           ; Repeat until no remaining elements

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

print_matrix:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the matrix
    ; [ebp+12] -> Size of the matrix (number of elements in one dimension)

    ; Load arguments from the stack
    mov esi, [ebp+8]         ; Load address of the array into ESI
    mov ecx, [ebp+12]        ; Load size of the array into ECX
    imul ecx, ecx            ; Multiply ECX by ECX to get the number of elements

.loop:
    test ecx, ecx            ; Check if there are any remaining elements
    jz .done                 ; If no remainder, we're done

    push ecx                 ; Save the original value of ECX
    fld dword [esi]          ; Load the float from the array into FPU stack
    sub esp, 8               ; Allocate space on the stack for printf
    fstp qword [esp]         ; Store the float in the stack (printf expects 64-bit float)
    push num_fmt             ; Push format string onto stack
    call printf              ; Call printf
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
    push ecx                ; Save the original value of ECX

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
