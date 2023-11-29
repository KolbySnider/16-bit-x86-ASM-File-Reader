# 16-bit-x86-ASM-File-Reader

The "Spring 2023 Machine Organization PROG4" is an 8086 assembly program that processes files. It takes two command tail arguments: a filename with its extension, and an unsigned integer, separated by a single space. The program reads a source file where each line contains a name and an unsigned integer, with variable whitespace in between. It then converts the ASCII string of the second argument into an integer and opens the source file. For each line in the source file, the program temporarily stores the name and integer string, converts the string to an integer, and compares it with the argument integer. If the integer from the file is greater than or equal to the argument integer, the program writes the corresponding name to an output file named "output.dat". Upon completion, the program displays the time elapsed in tenths of a second, and "output.dat" is saved in the same folder as the program.
