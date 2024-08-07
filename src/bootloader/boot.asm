ORG 0x7C00
BITS 16

JMP SHORT main
NOP

bdb_oem: DB "MSWIN4.1"
bdb_bytes_per_sector: DW 512
bdb_sectors_per_cluster: DB 1
bdb_reserved_sectors: DW 1
bdb_fat_count: DB 2
bdb_dir_entries_count: DW 0E0h
bdb_total_sectors: DW 2880
bdb_media_descriptor_type: DB 0F0h
bdb_sectors_per_fat: DW 9
bdb_sectors_per_track: DW 18
bdb_heads: DW 2
bdb_hidden_sectors: DD 0
bdb_large_sector_count: DD 0

ebr_drive_number: DB 0
                  DB 0
ebr_signature: DB 29h
ebr_volume_id: DB 12h,34h,56h,78h
ebr_volume_label: DB "MC OS      "
ebr_system_id: DB "FAT12   "

main:
    MOV ax,0
    MOV ds,ax ;start address of data segment
    MOV es,ax ;start address of extended segment
    mov ss,ax ;start address of stack segments

    MOV sp,0x7C00

    MOV [ebr_drive_number],dl ;Drive number to read from
    MOV ax, 1 ;LBA Index
    MOV cl, 1 ; sector number
    MOV bx, 0x7E00 ;pointer to a buffer
    CALL disk_read

    MOV si,os_boot_msg
    CALL print
    HLT 

halt: 
    JMP halt

;input: LBA input in ax
;cx [bits 0-5]: sector number
;cx [btis 6-15]: cylinder
;dh: head
lba_to_chs:
    PUSH ax
    PUSH dx

    XOR dx,dx ; resets dx to 0
    DIV word [bdb_sectors_per_track] ;(LBA % sectors per track) + 1 = sector | value of bdb sector per track divided by the value in ax, remainder in dx
    INC dx ;sector
    MOV cx,dx

    XOR dx,dx ;reset dx to 0
    
    ;head = (LBA / sectors per track) % number of heads
    ;cylinder (LBA / Sectors per track) / number of heads
    ;we already caluclated LBA/Sectors per track, it is stored in ax register
    DIV word [bdb_heads]
    MOV dh,dl ;store head value

    MOV ch,al
    SHL ah,6
    OR cl,ah ;cylinder

    POP ax
    MOV dl,al
    POP ax

    RET

disk_read:
    PUSH ax
    PUSH bx
    PUSH cx
    PUSH dx
    PUSH di

    CALL lba_to_chs

    MOV ah, 02h
    MOV di, 3   ;counter

retry:
    STC ;set the carry
    INT 13h
    JNC doneRead

    CALL diskReset

    DEC di
    TEST di,di
    JNZ retry

failDiskRead:
    MOV si, read_failure
    CALL print
    HLT
    JMP halt

diskReset:
    PUSHA
    MOV ah,0
    STC
    INT 13h
    JC failDiskRead
    POPA
    RET

doneRead:
    POP di
    POP dx
    POP cx
    POP bx
    POP ax

    RET

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

os_boot_msg: DB 'OS booted correctly!',0x0D,0x0A,0
read_failure: DB 'FAILURE READING DISK',0x0D,0x0A,0

TIMES 510-($-$$) DB 0
DW 0AA55h