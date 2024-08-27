section .data
    factorial_loop_result dd 0
    factorial_recursive_result dd 0
    prompt_number_msg db "Enter a positive integer: ", 0
    prompt_number_msg_len equ $ - prompt_number_msg
    loop_result_msg db "Factorial using loop: ", 0
    loop_result_msg_len equ $ - loop_result_msg
    recursive_result_msg db "Factorial using recursion: ", 0
    recursive_result_msg_len equ $ - recursive_result_msg
    number_str db '%d', 10, 0

section .bss
    number resd 1
    buffer resb 10

section .text
    global main
    extern printf

main:
    ; Prompt user for input
    call prompt_number
    mov [number], eax
    mov ebx, eax

    ; Validate input (ensure positive integer)
    cmp ebx, 0
    jle .error         ; Jump to error if input is not positive

    ; Call loop-based factorial procedure
    push ebx
    call factorial_loop
    add esp, 4
    mov [factorial_loop_result], eax

    ; Call recursion-based factorial procedure
    push ebx
    call factorial_recursive
    add esp, 4
    mov [factorial_recursive_result], eax

.display_results:
    ; Display loop-based factorial result
    mov edx, loop_result_msg_len
    mov ecx, loop_result_msg
    mov ebx, 1
    mov eax, 4
    int 0x80

    mov eax, [factorial_loop_result]
    push eax
    push number_str
    call printf
    add esp, 8

    ; Display recursion-based factorial result
    mov edx, recursive_result_msg_len
    mov ecx, recursive_result_msg
    mov ebx, 1
    mov eax, 4
    int 0x80

    mov eax, [factorial_recursive_result]
    push eax
    push number_str
    call printf
    add esp, 8

.exit:
    ; Exit program
    mov eax, 1         ; sys_exit
    xor ebx, ebx       ; Exit code 0
    int 0x80

.error:
    ; Handle error case for invalid input
    mov eax, 1         ; sys_exit
    mov ebx, 1         ; Exit code 1 (error)
    int 0x80

factorial_loop:
    ; Parameters:
    ; [ebp+8] - number to calculate factorial of

    push ebp
    mov ebp, esp
    push ecx

    mov ecx, [ebp+8]         ; Get the input number
    mov eax, 1               ; Initialize result to 1

.loop_unrolled:
    cmp ecx, 4               ; Process in chunks of 4
    jl .remainder            ; Jump if less than 4

    imul eax, ecx            ; eax *= ecx
    dec ecx                  ; ecx--
    imul eax, ecx            ; eax *= ecx
    dec ecx                  ; ecx--
    imul eax, ecx            ; eax *= ecx
    dec ecx                  ; ecx--
    imul eax, ecx            ; eax *= ecx
    dec ecx                  ; ecx--
    jmp .loop_unrolled

.remainder:
    cmp ecx, 1
    jl .done                 ; If ecx < 1, done

    imul eax, ecx            ; Process remaining numbers
    dec ecx
    jmp .remainder

.done:
    pop ecx
    pop ebp
    ret

factorial_recursive:
    ; Parameters:
    ; [ebp+8] - number to calculate factorial of
    
    push ebp
    mov ebp, esp
    push ebx

    mov ebx, [ebp+8]         ; Get the input number
    mov eax, 1               ; ecx will hold the result (accumulator)

.tail:
    cmp ebx, 1               ; If eax <= 1, we are done
    jle .done

    imul eax, ebx            ; Multiply accumulator by current eax
    dec ebx                  ; Decrement eax
    jmp .tail                ; Continue recursion

.done:
    pop ebx
    pop ebp
    ret

prompt_number:
    push ebx
    push ecx
    push edx
    push esi

    ; Print the prompt
    mov eax, 4               ; sys_write
    mov ebx, 1               ; stdout
    mov ecx, prompt_number_msg
    mov edx, prompt_number_msg_len
    int 0x80

    ; Read input
    mov eax, 3               ; sys_read
    mov ebx, 0               ; stdin
    mov ecx, buffer          ; buffer to store input
    mov edx, 10              ; read up to 10 bytes
    int 0x80

    ; Convert ASCII string to integer
    mov eax, 0               ; clear eax (accumulator)
    mov esi, buffer          ; point esi to start of buffer
.convert_loop:
    movzx ebx, byte [esi]    ; load byte into ebx
    cmp bl, 10               ; check for newline
    je .done                 ; if newline, end conversion
    sub bl, '0'              ; convert ASCII to number
    imul eax, eax, 10        ; multiply eax by 10
    add eax, ebx             ; add the number
    inc esi                  ; move to the next byte
    jmp .convert_loop        ; repeat until newline

.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
