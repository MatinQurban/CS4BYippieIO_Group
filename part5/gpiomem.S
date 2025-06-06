//*****************************************************************
//  Sean Viravouth, Matin Qurbanzadeh
//  CS3B - Yippie IO: Part 4 - Keypad input detection
//  05/06/2025
//
//	This file contains a set of macros that will help with detecting
//	keypad input. Each macro has its own unique function set that are
//	used for specific tasks.
//
//	List of macros:
//	- mapMem 			- written by author
//	- nanoSleep 		- written by author
//	- GPIODirectionOut 	- written by author
//	- GPIODirectionIn 	- written by us
//	- GPIOTurnOn 		- written by author
//	- GPIOTurnOff 		- written by author
// 	- GPIOReadPin 		- written by us
//	- waitPinOff 		- written by us
//	- readRowKeyboard 	- written by us
//*****************************************************************

#include "fileio.S"

.equ	pagelen, 4096
.equ	setregoffset, 28
.equ    clrregoffset, 40
.equ	PROT_READ, 1
.equ	PROT_WRITE, 2
.equ	MAP_SHARED, 1

// Macro to map memory for GPIO Registers
.macro mapMem
	openFile	devmem, O_RDWR // open /dev/mem
	ADDS		X4, XZR, X0	// fd for memmap
	// check for error and print error msg if necessary
	B.PL		1f  // pos number file opened ok
	MOV		X1, #1  // stdout
	LDR		X2, =memOpnsz	// Error msg
	LDR		W2, [X2]
	writeFile	X1, memOpnErr, X2 // print the error
	B		_end

// Setup can call the mmap2 Linux service
1:	ldr		X5, =gpioaddr	// address we want / 4096
	ldr		X5, [X5]	// load the address
	mov		X1, #pagelen	// size of mem we want
	mov		X2, #(PROT_READ + PROT_WRITE) // mem protection options
	mov		X3, #MAP_SHARED	// mem share options
	mov		X0, #0		// let linux choose a virtual address
	mov		X8, #__NR_mmap	// mmap service num
	svc		0		// call service
	ADDS		X9, XZR, X0	// keep the returned virtual address
	// check for error and print error msg if necessary
	B.PL		2f  // pos number file opened ok
	MOV		X1, #1  // stdout
	LDR		X2, =memMapsz	// Error msg
	LDR		W2, [X2]
	writeFile	X1, memMapErr, X2 // print the error
	B		_end
2:
.endm

// Macro nanoSleep to sleep .1 second
// Calls Linux nanosleep entry point which is function 162.
// Pass a reference to a timespec in both X0 and X1
// First is input time to sleep in seconds and nanoseconds.
// Second is time left to sleep if interrupted (which we ignore)
.macro  nanoSleep
        ldr         X0, =timespecsec
        ldr         X1, =timespecsec
        mov         X8, #__NR_nanosleep
        svc         0
.endm
.macro  GPIODirectionOut   pin
	ldr	X2, =\pin	// offset of select register
	ldr	W2, [X2]	// load the value
        ldr	W1, [X9, X2]    // address of register
	ldr	X3, =\pin	// address of pin table
	add	X3, X3, #4	// load amount to shift from table
	ldr	W3, [X3]	// load value of shift amt
	mov	X0, #0b111	// mask to clear 3 bits
	lsl	X0, X0, X3	// shift into position
	bic	X1, X1, X0	// clear the three bits
	mov	X0, #1		// 1 bit to shift into pos
	lsl	X0, X0, X3	// shift by amount from table
	orr	X1, X1, X0	// set the bit
	str	W1, [X9, X2]    // save it to register to do work   
.endm

//*****************************************************************
//  Macro:       GPIODirectionIn
//  Description: Configure the specified GPIO pin as an input by
//               clearing its 3-bit function select field.
//  Registers used:
//    X0 - mask for clearing bits
//    X1 - current value of the function select register
//    X2 - offset to the function select register for this pin
//    X3 - address/shift helper from pin table
//    X9 - base address of mapped GPIO registers
//
//  Pseudocode / Algorithm:
//    1. X2 = offset field from pin table
//    2. W1 = X9 + X2]              // read current FSEL register
//    3. X3 = pin table address + 4	// point to shift amount
//    4. W3 = X3]                   // load shift amount
//    5. X0 = 0b111 << W3          	// build mask for 3 bits
//    6. X1 = W1 & ~X0              // clear those 3 bits
//    7. [X9 + X2 = X1              // write back to FSEL register
//*****************************************************************
.macro  GPIODirectionIn   pin
	LDR	X2, =\pin		// offset of select register
	LDR	W2, [X2]		// load the value
    LDR	W1, [X9, X2]    // address of register
	LDR	X3, =\pin		// address of pin table
	ADD	X3, X3, #4		// load amount to shift from table
	LDR	W3, [X3]		// load value of shift amt
	MOV	X0, #0b111		// mask to clear 3 bits
	LSL	X0, X0, X3		// shift into position
	BIC	X1, X1, X0		// clear the three bits
	STR	W1, [X9, X2]    // save it to register to do work   
.endm

.macro  GPIOTurnOn   pin, value
	mov	X2, X9		// address of gpio regs
	add	X2, X2, #setregoffset // off to set reg
	mov	X0, #1		// 1 bit to shift into pos
	ldr	X3, =\pin	// base of pin info table
	add	X3, X3, #8	// add offset for shift amt
	ldr	W3, [X3]        // load shift from table
	lsl	X0, X0, X3	// do the shift
	str	W0, [X2]	// write to the register
.endm

.macro  GPIOTurnOff   pin, value
	mov	X2, X9		// address of gpio regs
	add	X2, X2, #clrregoffset // off set of clr reg
	mov	X0, #1		// 1 bit to shift into pos
	ldr	X3, =\pin	// base of pin info table
	add	X3, X3, #8    // add offset for shift amt
	ldr	W3, [X3]        // load shift from table
	lsl	X0, X0, X3	// do the shift
	str	W0, [X2]	// write to the register
.endm

//*****************************************************************
//  Macro:  GPIOReadPin
//  Arguments:
//    col 		- symbol for pin info table entry
//    row 		- string label for the corresponding row
//    boolBlock - boolean flag (non-zero to block until pin goes low)
//
//  Description:
//  Reads the specified GPIO input pin, and if it is high:
//  	- Returns 0-16 in X5 depending on keyboard input
//  	- Optionally blocks (waits) until the pin goes low if boolBlock != 0
//
//  Pseudocode / Algorithm:
//    1. addr = X9 + 0x34              	// compute GPLEV register address
//    2. reg  = [addr]                  // read GPIO level bits
//    3. shift = load_shift(col)       	// load pins bit position from table
//    4. mask = 1 << shift             	// create bit mask for this pin
//    5. if (reg & mask) == mask then   // pin is high
//	  6. if pin is low, end read
//	  7. move address of row and col
//	  8. add the offsets to position the row and col
//	  9. load the values of row(0-3) and col(1-4)
//	  10. compute and save keyboard value: (4 * row) + col
//	  11. Check block mode: if block, loop until low
//    12. end macro
//*****************************************************************
.macro GPIOReadPin col, row, boolBlock
1:
	MOV	X2, X9			// address of gpio regs
	ADD	X2, X2, #0x34 	// offset to GPLEV regiser
	LDR W2, [X2]		// read level bits
	MOV	X0, #1			// 1 bit to shift into pos
	LDR	X3, =\col		// base of pin info table
	ADD	X3, X3, #8    	// add offset for shift amt
	LDR	W3, [X3]        // load shift from table
	LSL	X0, X0, X3		// do the shift
	AND X1, X2, X0		// test bit in level register
	CMP X1, X0			// compare X1 - X0
	B.NE 1f				// if not equal, pin is low, exit read

	MOV X4, \boolBlock		// X4 is going to be our block flag register
	
    LDR W0, =\row        	// move address of row
    LDR W1, =\col        	// move address of col
    ADD X0, X0, #12     	// add offset to position row value
    ADD X1, X1, #12     	// add offset to position col value
    LDR W0, [X0]       		// load value of row
    LDR W1, [X1]        	// load value of col
    
    MOV X2, #4				// X2 will be used for row multiplier
    SMULL X5, W0, W2		// (4 * row)
    ADD X5, X5, X1			// keyboard value = (4 * row) + col
	
	CMP X4, #1				// Check if we are blocking
	B.EQ 1b					// If blocking, loop again until input changes
	
1:
	CMP X5, #0				// Check if we read into pin
	B.EQ 2f					// keyboard value is 0, we have read nothing, move to next read
	
    //LDR X0, =\row        	// load address of row
    //ADD X0, X0, #16     	// add offset to position row value
    //BL putstring
    
    //LDR X0, =\col        	// load address of col
    //ADD X0, X0, #16     	// add offset to position col value
    //BL putstring
    
    //LDR X0, =szEOL			// load address of szEOL
    //BL putstring			// print newline

	//CMP X4, #1			// Check if we are blocking
	//B.EQ 3f	// If we are here and blocking, it means we have read a pin already. Skip next reads

2:
.endm

//*****************************************************************
//  Macro:       readRowKeyboard
//  Argument:    pin - pin info table entry symbol
//
//  Description: Enable a keyboard row pin, read all column inputs,
//               then disable the row.
//
//  Pseudocode / Algorithm:
//    1. set row pin high
//    2. for each column: call GPIOReadPin to read state
//    3. wait a short time
//    4. set row pin low
//*****************************************************************
.macro readRowKeyboard pin, boolBlock

    GPIOTurnOn    \pin           	// set row pin high
    
    MOV X5, #0
    GPIOReadPin   col1, \pin, \boolBlock 	// read input on col 1
    GPIOReadPin   col2, \pin, \boolBlock 	// read input on col 2
    GPIOReadPin   col3, \pin, \boolBlock 	// read input on col 3
    GPIOReadPin   col4, \pin, \boolBlock 	// read input on col 4  
	
    nanoSleep                   // short delay
    GPIOTurnOff \pin           	// set column pin low
    
3:
    
.endm

//*****************************************************************
//  Macro:       initializePins
//  Argument:    pin - pin info table entry symbol
//				 col - col info
//
//  Description: initialize pins and cols to be inputs and/or outputs
//
//  Pseudocode / Algorithm:
//    1. initialize pins
//	  2. initalize cols
//*****************************************************************
.macro initializePins

	mapMem					// map virtual registers to memory address
	nanoSleep				// delay

    GPIODirectionOut pin4   // Set GPIO4 as output
    GPIODirectionOut pin17  // Set GPIO17 as output
    GPIODirectionOut pin27 	// Set GPIO27 as output
    GPIODirectionOut pin22  // Set GPIO22 as output

    GPIODirectionIn col1   	// Set GPIO for keyboard column 1 as input
    GPIODirectionIn col2   	// Set GPIO for keyboard column 2 as input
    GPIODirectionIn col3   	// Set GPIO for keyboard column 3 as input
    GPIODirectionIn col4   	// Set GPIO for keyboard column 4 as input

.endm

.data
szNewLine: .asciz "\n"
timespecsec:   .dword   0
timespecnano:  .dword   100000000
devmem:	       .asciz  "/dev/gpiomem"
//devmem:	   .asciz  "/dev/mem"
memOpnErr:     .asciz  "Failed to open /dev/mem\n"
memOpnsz:      .word  .-memOpnErr 
memMapErr:     .asciz  "Failed to map memory\n"
memMapsz:      .word  .-memMapErr 
			   .align  4 // relign after strings
gpioaddr:      .dword   0x0	// mem address of gpio registers
//gpioaddr:    .dword   0xFE200000	// mem address of gpio registers

offsetgplev0: .word 52	// base address for GPLEV0


szPinOn:	.asciz "Keypress detected: "
szPinOff:	.asciz "Off "

// OUTPUT PINS
pin4:	   .word   0   // offset to select register
	       .word   12  // bit offset in select register
	       .word   4   // bit offset in set & clr register
	       .word   0
	       .asciz "row 1 "

pin17:	   .word   4   // offset to select register
	       .word   21  // bit offset in select register
	       .word   17  // bit offset in set & clr register
	       .word   1
	       .asciz "row 2 "
	       
pin22:	   .word   8   // offset to select register
	       .word   6   // bit offset in select register
	       .word   22  // bit offset in set & clr register
	       .word   2
	       .asciz "row 3 "
	       	       
pin27:	   .word   8   // offset to select register
	       .word   21  // bit offset in select register
	       .word   27  // bit offset in set & clr register
	       .word   3
	       .asciz "row 4 "

// INPUT PINS	       
col1:	   .word   4   	// offset to select register
	       .word   24  	// bit offset in select register
	       .word   18  	// bit offset in set & clr register
	       .word   1
	       .asciz "col 1 "
	       
col2:	   .word   8   	// offset to select register
	       .word   9  	// bit offset in select register
	       .word   23   // bit offset in set & clr register (figure this out later)
	       .word   2
	       .asciz "col 2 "
	       
col3:	   .word   8   	// offset to select register
	       .word   12  	// bit offset in select register
	       .word   24  	// bit offset in set & clr register
		   .word   3
           .asciz "col 3 "
           
col4:	   .word   8   	// offset to select register
	       .word   15  	// bit offset in select register
	       .word   25  	// bit offset in set & clr register
	       .word   4
	       .asciz "col 4 "

.text
