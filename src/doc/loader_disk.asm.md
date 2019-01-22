
# Loader Disk Driver

The loader disk driver can fulfill simple disk-related tasks such as disk drive enumeration, parameter maintenance, buffer
management, and disk I/O using linear LBA. The disk driver module relies on BIOS INT13H for enumeration and access using C/H/S.
The module maintains its own buffer pool, disk parameter table, and C/H/S convertion routines. 

## Disk Enumeration Using INT13H/08H

Disk enumeration is the first step of disk module initialization. We rely on BIOS routine INT13H/08H to implement the disk enumeration
function. Disks are assigned letters beginning from upper case 'A'. Note that we do not distinguish between FDDs and HDDs in this
numbering, so it is possible that a system with one FDD and several HDDs has the first HDD being disk 'B'. The letter numbering 
also gives each disk an unique index in the system-wide disk mapping table which stores the disk parameter. We next describe
the process of disk enumeration.

### INT13H/08H

This BIOS routine returns the parameter of a given disk number, if it exists, or indicates an error. BIOS has its own way
of assigning numbers to disk drives: Each disk has an 8 bit identifier. Floppy disk numbering begins at 0x00, while hard
disk numbering begins from 0x80. Potentially there can be at most 128 drives under each category. 

The INT13H/08H works as follows. It takes one argument in DL, which is the BIOS number of the drive to be probed. Some BIOSes 
may also require that ES:BX be set to 0000:0000 to avoid subtle bugs. After the routine returns, CF is set if an error occurs.
Note that errors do not indicate failures in this case, because we rely on this property to know when the enumeration has finished. 
The returned state are as follows: AH is the status code. We ignore the value for now. BL is the drive type. We store this value
into the disk parameter table, but ignore it for future operations. Disk geometry information is stored in CH, CL and DH. 
DH stores the maximum addressable disk heads (note that the number of heads should be +1 of this value). The lower 6 bits of CL
is the maximum addressable sector number (note that sector number starts at 1, and this value equals sector per track). 
CH and the higher 2 bits of CL together form the maximum addressable track number (note that the number of tracks should be +1
of this value). The 2 bits in CL are on the higher position of track number. Besides, DL is the number of drives in the 
current category. The value DL is not clear. It seems that DL always contains the drive number, at least on qemu BIOS.

### Enumeration Process

The disk enumeration begins with drive number 0x00. We call INT13H/08H repeatedly

