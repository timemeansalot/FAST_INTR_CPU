	.text			# Define beginning of text section
	.global	_boot		# Define entry _boot

_boot:
    addi x5, x0, 4
    addi x1, x1, 1
    addi x0, x0, 1
    nop
    nop
    nop
    beq  x0, x5, _boot 
    j stop 
    nop
    addi x2, x2, 1
    addi x3, x3, 1
    addi x4, x4, 1
stop:
	j stop			# Infinite loop to stop execution

	.end			# End of file

