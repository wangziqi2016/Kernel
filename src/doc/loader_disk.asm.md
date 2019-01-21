
# Loader Disk Driver

The loader disk driver can fulfill simple disk-related tasks such as disk drive enumeration, parameter maintenance, buffer
management, and disk I/O using linear LBA. The disk driver module relies on BIOS INT13H for enumeration and access using C/H/S.
The module maintains its own buffer pool, disk parameter table, and C/H/S convertion routines. 

## Disk Enumeration

Disk enumeration is the first step of module initialization. 