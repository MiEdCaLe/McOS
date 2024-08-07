ORG 0x7C00
BITS 16

JMP SHORT main
NOP

bdb_oem: DB "MSWIN4.1" ; 8 bytes
bdb_bytes_per_sector: DW 512
bdb_sectors_per_cluster: DB 1
bdb_reserved_sectors: DW 1
bdb_fat_count: DB 2
bdb_dir_entries_count: DW 0E0h
bdb_total_sectors: DW 2880 ; 2880 * 512 = 1.44 MB
bdb_media_descriptor_type: DB 0F0h ; F0 = 3.5" floppy disk
bdb_sectors_per_fat: DW 9   ;9 sectors/fat
bdb_sectors_per_track: DW 18
bdb_heads: DW 2
bdb_hidden_sectors: DD 0
bdb_large_sector_count: DD 0

;extended boot record
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

    MOV si,os_boot_msg
    CALL print

    ;fat 12, disk is divided into 4 segments
    ;reserved segment: 1 sector
    ;FAT: 9 (sectors per fat) * 2 (fat count)= 18 Sectors
    ;Root directory: starts at the end, so sector 19
    ;Data 

    MOV ax,[bdb_sectors_per_fat]
    MOV bl, [bdb_fat_count] ;low bits set to fat count, in this case 2
    XOR bh,bh ;so that the 8 high bits are 0
    MUL bx
    ADD ax, [bdb_reserved_sectors] ;result = 19 -> LBA of root directory
    PUSH ax

    MOV ax, [bdb_dir_entries_count]
    SHL ax, 5 ;ax *=32
    XOR dx,dx
    DIV word [bdb_bytes_per_sector] ;(32*num of entries)/bytes per sector

    test dx,dx
    JZ rootDirAfter
    INC ax

rootDirAfter:
    MOV cl,al ;number of sectors to read
    POP ax ;LBA back on register ax
    MOV dl, [ebr_drive_number]
    MOV bx, buffer
    CALL disk_read

    XOR bx,bx
    MOV di,buffer

searchkernel:
    MOV si, file_kernel_bin
    MOV cx, 11
    PUSH di ;preserve di
    REPE CMPSB ;repeat comparison of bytes between file_kernel bin and buffer
    POP di
    JE foundKernel

    ADD di, 32
    INC bx
    CMP bx, [bdb_dir_entries_count]
    JL searchkernel

    JMP kernelNotFound ;if its greater we didnt find the kernel

kernelNotFound:
    MOV si, msg_kernel_not_found
    CALL print
    
    HLT
    JMP halt

foundKernel:
    MOV ax, [di+26]
    MOV [kernel_cluster],ax

    MOV ax, [bdb_reserved_sectors]
    MOV bx, buffer
    MOV cl, [bdb_sectors_per_fat]
    MOV dl, [ebr_drive_number]

    CALL disk_read

    MOV bx, kernel_load_segment
    MOV es,bx
    MOV bx, kernel_load_offset

loadKernelLoop:
    MOV ax,[kernel_cluster]
    ADD ax,31 ;setup the offset so we're able to read the particular cluster
    MOV cl, 1
    MOV dl, [ebr_drive_number]

    CALL disk_read

    ADD bx, [bdb_bytes_per_sector]
    MOV ax, [kernel_cluster] ;(kernel cluster * 3)/2
    MOV cx, 3
    MUL cx ;multiply kernel cluster by 3
    MOV cx,2
    DIV cx

    MOV si, buffer
    ADD si, ax
    MOV ax, [ds:si]

    OR dx,dx
    JZ even 

odd: 
    SHR ax, 4
    JMP nextClusterAfter
even: 
    AND ax,0x0FFF ; 12 bits

nextClusterAfter:
    CMP ax, 0x0FF8
    JAE readFinish

    MOV [kernel_cluster], ax
    JMP loadKernelLoop
readFinish:
    MOV dl, [ebr_drive_number]
    MOV ax, kernel_load_segment
    MOV ds,ax
    MOV es,ax

    JMP kernel_load_segment:kernel_load_offset

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

os_boot_msg: DB 'Loading...',0x0D,0x0A,0
read_failure DB 'FAILURE READING DISK',0x0D,0x0A,0

file_kernel_bin DB 'KERNEL  BIN' ;has to be 11 bytes in length
msg_kernel_not_found DB 'KERNEL.BIN not found!'
kernel_cluster DW 0
kernel_load_segment EQU 0x2000
kernel_load_offset EQU 0

TIMES 510-($-$$) DB 0
DW 0AA55h

buffer: 