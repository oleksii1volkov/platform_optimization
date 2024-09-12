section .data
    align_size equ 16           ; Alignment size (16 bytes for SSE)
    string db 'WOdLIGZaV1ypdnKEWAmZiK9IwFX2mP2KWOdLIGZaV1ypdnKEWAmZiK9IwFX2mP2K', 0
    string_size equ $-string
    substring db 'OdLIGZaV1ypdnKEWAmZiK9IwFX2mP2K', 0
    substring_size equ $-substring
    elapsed_time_loop_msg db 'Loop-based substring count time: ', 0
    elapsed_time_simd_msg db 'SIMD substring count time: ', 0
    substring_count_loop_msg db 'Loop-based substring count: ', 0
    substring_count_simd_msg db 'SIMD substring count: ', 0
    str_fmt db '%s', 0
    num_fmt db '%d', 0
    char_fmt db '%c', 0
    time_fmt db '%ld.%09ld seconds', 0

section .bss
    string_ptr resd 1           ; Pointer to dynamically allocated string
    substring_ptr resd 1        ; Pointer to dynamically allocated substring
    substring_count_loop resd 1 ; Number of substring occurrences in string using loop-based algorithm
    substring_count_simd resd 1 ; Number of substring occurrences in string using SIMD algorithm
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

_start:
    ; Allocate aligned memory
    call allocate_aligned_memory

.copy_strings:
    ; Copy string
    push dword [string_ptr]
    push string
    call copy_string
    add esp, 8

    ; Copy substring
    push dword [substring_ptr]
    push substring
    call copy_string
    add esp, 8

.count_substring_loop:
    ; Start timing
    call start_timing

    ; Count number of occurrences
    push substring_size - 1
    push dword [substring_ptr]
    push string_size - 1
    push dword [string_ptr]
    call count_substring_loop
    add esp, 16
    mov [substring_count_loop], eax

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

    ; Substring count message
    push substring_count_loop_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print number of occurrences
    push dword [substring_count_loop]
    push num_fmt
    call print_format
    add esp, 8

    ; Print new line
    push dword 10
    push char_fmt
    call print_format
    add esp, 8

.count_substring_simd:
    ; Start timing
    call start_timing

    ; Count number of occurrences
    push substring_size - 1
    push dword [substring_ptr]
    push string_size - 1
    push dword [string_ptr]
    call count_substring_simd
    add esp, 16
    mov [substring_count_simd], eax

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

    ; Substring count message
    push substring_count_simd_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print number of occurrences
    push dword [substring_count_simd]
    push num_fmt
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

allocate_aligned_memory:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp

    ; Allocate memory for string
    push dword string_size
    push dword align_size
    push dword string_ptr
    call posix_memalign
    add esp, 12

    ; Allocate memory for substring
    push dword substring_size
    push dword align_size
    push dword substring_ptr
    call posix_memalign
    add esp, 12

    ; Epilogue: Restore stack frame
    pop ebp
    ret

free_allocated_memory:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp

    ; Free the memory for substring
    push dword [substring_ptr]
    call free
    add esp, 4

    ; Free the memory for string
    push dword [string_ptr]
    call free
    add esp, 4

    ; Epilogue: Restore stack frame
    pop ebp
    ret

count_substring_simd:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8]  -> Address of the string
    ; [ebp+12] -> Length of the string
    ; [ebp+16] -> Address of the substring
    ; [ebp+20] -> Length of the substring

    mov esi, [ebp+8]        ; Load the address of the string
    mov ecx, [ebp+12]       ; Load the length of the string
    mov edi, [ebp+16]       ; Load the address of the substring
    mov edx, [ebp+20]       ; Load the length of the substring

    xor eax, eax                  ; Initialize match count to 0
    test edx, edx                 ; Check if substring length is zero
    jz .done                      ; If substring length is zero, exit

.search_loop:
    cmp ecx, edx                  ; Check if enough bytes remain in the larger string
    jl .done                      ; If remaining bytes are less than substring length, stop

    xor ebx, ebx                  ; Set chunk index to 0
    mov edx, [ebp+20]             ; Load the length of the substring
    shr edx, 4                    ; Divide by 16 to get number of 16-byte chunks

.compare_chunks:
    ; Compare 16-byte chunks in a loop
    cmp ebx, edx                   ; Check if we have compared all chunks
    jge .check_remainder           ; If all chunks have been compared, check the remainder

    ; Load 16 bytes from the larger string and substring
    push ebx                       ; Save ebx
    imul ebx, 16                   ; Multiply chunk index by 16
    movdqu xmm0, [esi+ebx]         ; Load 16 bytes from larger string into xmm0
    movdqa xmm1, [edi+ebx]         ; Load 16 bytes from substring into xmm1
    pop ebx                        ; Restore ebx

    pcmpeqb xmm0, xmm1             ; Compare bytes in xmm0 with xmm1
    push ecx                       ; Save ecx
    pmovmskb ecx, xmm0             ; Move result of comparison to mask (ecx will hold the mask)
    cmp ecx, 0xFFFF                ; Compare the mask to 0xFFFF (16 bytes match)
    pop ecx                        ; Restore ecx
    jne .no_match                  ; If not all bytes match, go to no_match

    inc ebx                        ; Move to the next 16-byte chunk
    jmp .compare_chunks            ; Repeat the comparison for the next chunk

.check_remainder:
    mov edx, [ebp+20]              ; Load the length of the substring
    shl ebx, 4                     ; Multiply by 16 to get last chunk index

.remainder_loop:
    cmp ebx, edx                   ; Check if we have compared all chunks
    jge .match                     ; If all chunks have been compared, we have a match

    push eax                       ; Save eax
    push ebx                       ; Save ebx
    mov al, [esi+ebx]              ; Load byte from the larger string
    mov bl, [edi+ebx]              ; Load byte from the substring
    cmp al, bl                     ; Compare bytes
    pop ebx                        ; Restore ebx
    pop eax                        ; Restore eax
    jne .no_match                  ; If not all bytes match, go to no_match
    inc ebx                        ; Move to the next byte in the substring
    jmp .remainder_loop            ; Repeat the comparison for the next byte

.match:
    ; If here, a full match was found
    inc eax                       ; Increment match count

.no_match:
    inc esi                       ; Move to the next byte in the larger string
    dec ecx                       ; Decrement the remaining length of the larger string
    jmp .search_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

count_substring_loop:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the string
    ; [ebp+12] -> Length of the string
    ; [ebp+16] -> Address of the substring
    ; [ebp+20] -> Length of the substring

    mov esi, [ebp+8]        ; Load the address of the string
    mov ecx, [ebp+12]       ; Load the length of the string
    mov edi, [ebp+16]       ; Load the address of the substring
    mov edx, [ebp+20]       ; Load the length of the substring

    xor eax, eax            ; Initialize count to 0

    ; Loop through the larger string
.search_loop:
    cmp ecx, edx            ; Check if enough bytes remain in the larger string
    jl .done                ; If remaining bytes are less than substring length, stop

    ; Compare each character in the substring
    mov ebx, 0              ; Initialize index to 0
.compare_loop:
    push eax                ; Save eax
    push ebx                ; Save ebx
    mov al, [esi+ebx]       ; Load byte from the larger string
    mov bl, [edi+ebx]       ; Load byte from the substring
    cmp al, bl              ; Compare bytes
    pop ebx                 ; Restore ebx
    pop eax                 ; Restore eax
    jne .no_match
    inc ebx                 ; Move to the next byte in the substring
    cmp ebx, edx            ; Check if we've compared the whole substring
    jl .compare_loop

    ; Match found
    inc eax                 ; Increment count

.no_match:
    add esi, 1              ; Move to the next byte in the larger string
    sub ecx, 1              ; Decrement the length of remaining larger string
    jmp .search_loop

.done:
    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

copy_string:
    ; Prologue: Set up stack frame
    push ebp
    mov ebp, esp
    push eax
    push edi
    push esi

    ; Function Arguments (on stack):
    ; [ebp+8] -> Address of the source string
    ; [ebp+12] -> Address of the destination string

    mov esi, [ebp+8]       ; Get the address of the source string
    mov edi, [ebp+12]      ; Get the address of the destination string

    ; Copy the string
.copy_loop:
    mov al, [esi]         ; Load byte from source string
    cmp al, 0             ; Check if end of string (null terminator)
    je .done              ; If yes, exit
    mov [edi], al         ; Copy byte to destination string
    inc esi               ; Increment source pointer
    inc edi               ; Increment destination pointer
    jmp .copy_loop

.done:
    mov byte [edi], 0           ; Add null-terminator

    ; Epilogue: Restore stack frame and return
    pop esi
    pop edi
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
