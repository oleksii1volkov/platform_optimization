section .data
    ; Declare three integers
    num1 dd 1
    num2 dd 2
    num3 dd 3
    result dd 0
    
section .text
    global _start

_start:
    ; Load the values into registers
    mov eax, [num1]
    add eax, [num2]
    add eax, [num3]

    ; Store the result in memory
    mov [result], eax
    
    ; Exit the program
    mov eax, 1          ; syscall number for exit
    xor ebx, ebx        ; status: 0
    int 0x80            ; invoke syscall
