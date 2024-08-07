ORG 0x7C00
BITS 16

main:
    MOV ax,0
    MOV ds,ax ;start address of data segment
    MOV es,ax ;start address of extended segment
    mov ss,ax ;start address of stack segments

    MOV sp,0x7C00
    MOV si,os_boot_msg
    CALL print
    HLT 

halt: 
    JMP halt

print:
    PUSH si
    PUSH ax
    PUSH bx

print_loop:
    LODSB ;Load single Byte at address (E)SI into EAX
    OR al,al
    JZ done_print ;if al is 0, or-ing it with iself would be 0.

    MOV ah, 0x0E ;Printing a character to a screen in BIOS
    MOV bh, 0 ;page number as argument
    INT 0x10 ;Video interrupt
    JMP print_loop


done_print:
    POP bx
    POP ax
    POP si
    RET


os_boot_msg: DB "--!--", 0x0D, 0x0A,0

TIMES 510-($-$$) DB 0
DW 0AA55h