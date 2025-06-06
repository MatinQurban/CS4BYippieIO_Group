// Sean Viravouth, Matin Qurbanzadeh
//  CS3B - Yippie IO: Part 4 - Driver for getkey
//	05/06/2025

// Desc: This program will use call get key and print the 
//		 value of the key pressed (1-16) in both blocking
//		 and non-blocking modes. If no key is pressed in
//		 non-blocking mode, will continuously output 0.

// Algo:
//		For each mode:
//		Start getKey loop 
//		Print resluting key (1-16 for blocking, 0-16 for nonblocking)

#include "gpiomem.S"

.macro    printLine        stringBuff
// Prints stringBuff followed by newline
        LDR X0, =\stringBuff    // Load address of string buffer
        BL putstring            // print string to console
        LDR X0, =szEOL            // Load address of EOL
        BL putstring 			// print new line
.endm

.global _start	// Provide program starting address

_start:	// program start

		initializePins		// Map function registers and Initialize direction of pins
	
		MOV W11, #16			// Load immediate 5 into W6 for iteration count
loopBlocking:
		MOV X0, #1			// getKey uses X0 to denote blocking or nonblocking
		BL getKey 			// Call getKey, returns value 0-16 in X0
		
		SUBS W11, W11, #1	// Decrement W6; update condition flags
		B.NE loopBlocking	// If W6 != 0, branch back to loop
		
		MOV W11, #30		// Load immediate 30 into W6 for iteration count
		
		printLine szModeSeparator	// Output szModeSeparator to console
		
loopNonBlocking:
		MOV X0, #0				// getKey uses X0 for blocking mode
		BL getKey				// Call getKey, returns value 0-16 in X0
		
		SUBS W11, W11, #1		// Decrement W6; update condition flags
		B.NE loopNonBlocking	// If W6 != 0, branch back to loop


// Terminate program
		MOV X0, #0		// Set exit code 0 in X0
		MOV X8, #93		// SYS_CALL number 93 for exit
		SVC 0			// Linux supervisor call to terminate program
.data
szModeSeparator: .asciz "===== Non-Blocking ====="
szEOL: .asciz "\n"
