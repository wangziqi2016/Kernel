
# Loader Disk Driver

The loader disk driver can fulfill simple disk-related tasks such as disk drive enumeration, parameter maintenance, buffer
management, and disk I/O using linear LBA. The disk driver module relies on BIOS INT13H for enumeration and access using C/H/S.
The module maintains its own buffer pool, disk parameter table, and C/H/S convertion routines. 

## Disk Enumeration using INT13H/08H

Disk enumeration is the first step of module initialization. We rely on BIOS routine INT13H/08H to implement the disk enumeration
function. Disks are assigned letters beginning from upper case 'A'. Note that we do not distinguish between FDDs and HDDs in this
numbering, so it is possible that a system with one FDD and several HDDs has the first HDD being disk 'B'. The letter 