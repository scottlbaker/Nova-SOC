
Name: rb2hex.c


Description:

The dga assembler outputs in a relocatable-binary format and my simulation environment requires the program data to be in Intel hex format. I wrote this program to convert the dga output to Intel hex format.


Example command line:

rb2hex -i t1.rb -o t1.hex


Compiling:

gcc rb2hex.c -o rb2hex


Note: The dga assembler (written by Toby Thain) can be found here:
http://www.telegraphics.com.au/svn/dpa/trunk

