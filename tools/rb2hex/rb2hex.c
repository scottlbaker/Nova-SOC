
//=======================================================
//    Convert nova relocatable-binary output file 
//    to Intel hex format
//
//    copyright (c) Scott L Baker 2016
//=======================================================

#include <stdio.h>
#include <stdlib.h>

FILE *fp1;        // input file
FILE *fp2;        // output file

char *line, buffer[16383];
int  address = 0;
int  bufaddr = 0;
int  bcount  = 0;
int  gotta3  = 0;
int  lastrec = 0;

void convert(void);
int  getf(void);
int  gettyp(void);
int  getlen(void);
void getaddr(void);
void getdata(void);
void skipw(int);
void writeline (int);
void writelast ();
char hex (int);
void puthex (int, int);
void ferr (char *);
void where(void);

int main (int argc, char *argv[]) {

  char *s;

  while(--argc) {
    s = *++argv;
    if(*s++ != '-')
      ferr("Expected '-' and an option");

    switch(*s++) {

    case 'i':    // input filename
      if(argc < 2)
        ferr("No input file");
      argc--;
      if((fp1 = fopen(*++argv, "rb")) == NULL)
        ferr("Cannot open input file");
      continue;

    case 'o':    // output filename
      if(argc < 2)
        ferr("No output file");
      argc--;
      if((fp2 = fopen(*++argv, "w")) == NULL)
        ferr("Cannot create output file");
      continue;

    default:
      ferr("Unknown option");
    }
  }

  convert();

  fclose(fp1);
  fclose(fp2);
  return 0;
}

// Get a record
void getrecord(void) {
  int  typ;
  int  len;

  typ = gettyp();
  len = getlen();

  // check for data records
  if(typ == 2) {
    // fprintf (stdout, "Record type = %d  ", typ);  // debug
    // fprintf (stdout, "length = %d\n", len);       // debug
    skipw(4);  // skip junk
    getaddr();

    while (len-- > 0) {
      getdata();
    }

  // ignore non-data-type records
  } else {

    // a start record indicates the end of data
    if(typ == 6) {
      lastrec = 1;
    } else {
      // currently cannot handle other record types
      fprintf (stdout, "ERROR: Record type = %d  ", typ);
      fprintf (stdout, "length = %d\n", len);
      exit (0);
    }
  }
}

// Read the paper-tape-binary format data
// and output Intel Hex
void convert(void) {
  int i, j;

  // read the records and fill the buffer
  while (lastrec == 0) {
    getrecord();
  }

  // now process the buffer and output hex data
  line = buffer;

  if (bcount <= 16) {
    writeline (bcount);
  } else {
    i = bcount;
    j = 0;
    while (i > 16) {
      // fprintf (stdout, "Writing i= %d\n", i);     // debug
      writeline (16);
      i -= 16;
      j += 16;
      address += 16;
      line = &buffer[j];
    }
    if (i > 0) {
      // fprintf (stdout, "Writing i= %d\n", i);     // debug
      writeline (i);
    }
  }
  writelast();
}

// read a character
int getf() {
  int ch;
  ch = fgetc(fp1);
  return ch;
}

// process address
void getaddr() {
  bufaddr  = fgetc(fp1);
  bufaddr += 256*fgetc(fp1);
  // fprintf (stdout, "@%06o == x%04x  x%04x\n", bufaddr,bufaddr,bcount>>1);  // debug

  while (bcount < (bufaddr*2)) {
    // fill gaps with zeros
    buffer[bcount++] = 0;
    // fprintf (stdout, ".");  // debug
  }
}

// process data
void getdata() {
  int ch1, ch2;
  ch1 = fgetc(fp1);
  ch2 = fgetc(fp1);
  buffer[bcount++] = ch1;
  buffer[bcount++] = ch2;
  // fprintf (stdout, "%02x%02x\n", ch1,ch2);  // debug
}

// skip words
void skipw(int count) {
  int i;
  for (i=0; i<count; i++) {
    fgetc(fp1);
    fgetc(fp1);
  }
}

// get record type
int gettyp() {
  int ch;
  ch = fgetc(fp1);  // type
  fgetc(fp1);       // skip
  return ch;
}

// get record length
int getlen() {
  int len;
  len  = fgetc(fp1);
  len += 256*fgetc(fp1);
  len = 65535 - len;
  return len;
}

// write a hex line
//
void writeline (int count) {
  int sum = 0;
  int i;
  char ch;

  sum += address >> 8;        // Checksum high address byte
  sum += address & 0xff;      // Checksum low address byte
  sum += count;               // Checksum record byte count
  putc (':', fp2);
  puthex (count, 2);          // Byte count
  puthex (address, 4);        // Address
  puthex (0, 2);              // Record type
  for (i=count; i; i--) {     // Then the actual data
    ch = *line++;
    sum += ch;                // Checksum each character
    puthex (ch, 2);
  }
  puthex (0 - sum, 2);        // Checksum is 1-byte 2's comp
  fprintf (fp2, "\n");
}

// write an end record
//
void writelast () {
  fprintf (fp2, ":00000001FF\n");
}

// return ASCII hex character for binary value
//
char hex (int ch) {
  if ((ch &= 0x000f) < 10)
    ch += '0';
  else
    ch += 'A' - 10;
  return ((char) ch);
}

// put the specified number of digits in ASCII hex
//
void puthex(int val, int digits) {
  char ch;
  if (--digits) puthex (val >> 4, digits);
  ch = hex (val & 0x0f);
  putc (ch, fp2);
}

// handle a fatal error
void ferr(char *text) {
  fprintf(stdout, text);
  where();
  exit(1);
}

// output the character position
void where() {
  long position;
  if(fp1 && (position = ftell(fp1)) != -1)
    fprintf(stdout, " at character position %ld\n", position);
  else
    fprintf(stdout, "\n");
}

