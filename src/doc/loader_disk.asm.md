
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
current category. Some BIOSes (e.g. the one on VirtualBox) may return success for non-existent drives on probing. To prevent this, 
we also check the disk number after AND'ing with 0x7F against the value in DL to further determine whether the return value is valid.

### Enumeration Process and Disk Mapping Table

The disk enumeration begins with drive number 0x00, and increment this number for every iteration. We call INT13H/08H 
for each drive number until the routine reports error, after which we begin with 0x80 and repeat. After the routine
reports error for the second time, we finish the disk enumeration process, and print out disks found and their parameters
in CHS (Cylinder/Head/Sector) form.

For each disk found during enumeration, we allocate an entry in the disk mapping table. The disk mapping table is a 
consecutive range of memory consisting of disk parameter entries. It is allocated from system BSS memory (higher end
of the system segment), and uses the (total_number_entry - (disk letter - 'A')) as the index into the table.
Note that the indexing scheme into the disk mapping table is non-intuitive because the table is allocated from
the system BSS memory, and therefore the first drive is located on the highest address.

During the enumeration process we also turn off interrupts to ensure that all disk mapping entries are allocated
on a consecutive range of memory.

Two variables are used to maintain the disk mapping table: ``disk_mapping`` stores the pointer to the lower address of 
the table (it is updated every time we find an entry). ``disk_mapping_num`` stores the number of entries in the table.

## Disk Parameters

The following parameters are frequently used during normal disk operation: Disk letter, which is used as the unique 
identifier of the drive; C/H/S (Cylinder/Head/Sector) which describes the geometry of the disk, and is used to 
convert linear block address (LBA) to the C/H/S address for a given sector. 

High level disk operations take LBA to simplify programming. In order to convert LBA to C/H/S notation, which is required 
for BIOS routine to perform disk operation, we need a translation layer that accepts an LBA and disk letter, and returns 
the C/H/S or error if the input is invalid. The translation is performed by function ``disk_getchs``. The function decodes 
a given LBA in a similar way as a "digit printing" program decomposes an integer into digits. Actually, if we think of 
the C/H/S notation as a special numbering system where each digit has its own base, then this process is exactly the same
as the digit printing function. In order to compute S, we compute (LBA mod (# sectors per track)). In order to compute H,
we compute ((LBA div (# sectors per track)) mod (# of heads per cylinder)). In order to compute C, we compute 
((LBA div (# sectors per track)) div (# of heads per cylinder)). Once C/H/S are computed, we return them in a form
that matches the input format of disk I/O functions in INT13H.

## Buffer Pool

A system-wide buffer pool avoids frequent I/O operations by caching frequently used sectors in the main memory. The 
buffer pool is allocated on high memory, i.e. the BSS segment after 1MB boundary, using ``mem_get_large_bss``. Every
time the buffer pool is accessed, ES will be loaded with the corresponding segment descriptor. The buffer pool is 
initialized during the disk initialization time. 

The disk buffer pool maintains only minimal information for the most basic functionality. For each entry, we maintain
its LBA, disk letter, current status (dirty/valid), and drive ID. Sectors enter the buffer pool on-demand, i.e. an
entry is allocated only when a sector is requested. If the allocation cannot be done because all entries are currently
active, an eviction decision will be made, and one of the entries will be invalidated. The eviction happens in a round-robin
fashion: It always follows the pattern 0, 1, 2, ..., MAX_ENTRY, 0, 1, ..., etc. If the selected entry is dirty, it will
be written back to the disk before invalidation.

The buffer pool provides an abstraction of byte-addressable disk image, while being transparent to the upper level functions.
All disk requests must go through the buffer pool using special interfaces in order to access the disk. We choose not to
expose the fact that disk sectors are buffered to the application, such that the buffer pool manager has full freedom 
of deciding which entries should be invalidated. The buffer pool is also fully decoupled from the file system implementation:
No matter how the FS maintains its sectors (e.g. using clusters), the buffer pool always loads and invalidates entries on
sector granularity.

The entry point of the buffer pool manager is ``disk_insert_buffer``. This function first attempts to find an existing 
entry having the LBA and the disk letter. If no existing entry can be found, it uses an empty entry (more specifically, 
the last empty entry) in the buffer pool to insert the sector. If no empty entry can be found, an existing entry is evicted,
and its slot is allocated to the new sector.

## Buffered I/O

The buffered I/O interface has one single entry point: ``disk_op_word``. It takes the linear byte offset, the disk letter, 
a piece of 16 bit data if it is write operation, and finally the operation code in AX to indicate read or write.
This function supports reading from or writing into misaligned bytes, even if they cross the sector boundary. Operations
performed by this function uses the buffer pool described in the previous section to provide fast access. The function
only supports 16 bit reads and writes, and only takes the linear byte address rather than sector/offset. The upper level
functions can take advantage of this feature to simplify their implementations.

To avoid searching the buffer pool every time this function is called, we adopt an optimization that can improve the 
average case given good locality. Instead of searching from the beginning of the buffer pool on each call, the lower
byte of the LBA is hashed into an offset, and search begins at this offset. This guarantees that if the upper level
function accesses only a few sectors repeatedly, the search process only needs to check a few entries before the 
cached entry can be found.