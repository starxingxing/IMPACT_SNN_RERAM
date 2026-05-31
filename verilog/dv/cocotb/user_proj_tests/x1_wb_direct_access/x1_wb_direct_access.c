#include <firmware_apis.h>

#define X1_MATRIX_OFFSET_WORD 1u
#define X1_DIRECT_OFFSET_WORD 0x1401u
#define X1_MODE_PROGRAM 0xC0000000u
#define X1_MODE_READ    0x40000000u
#define X1_MODE_FORM_A  0x80000000u
#define X1_ROW(row)     (((unsigned int)(row) & 0x1Fu) << 25)
#define X1_COL(col)     (((unsigned int)(col) & 0x1Fu) << 20)

static unsigned int read_x1_direct(unsigned int row, unsigned int col) {
    USER_writeWord(X1_MODE_READ | X1_ROW(row) | X1_COL(col), X1_DIRECT_OFFSET_WORD);
    dummyDelay(500);
    return USER_readWord(X1_DIRECT_OFFSET_WORD);
}

static unsigned int read_x1_matrix(unsigned int row, unsigned int col) {
    USER_writeWord(X1_MODE_READ | X1_ROW(row) | X1_COL(col), X1_MATRIX_OFFSET_WORD);
    dummyDelay(500);
    return USER_readWord(X1_MATRIX_OFFSET_WORD);
}

void main() {
    unsigned int ok = 1u;

    ManagmentGpio_outputEnable();
    ManagmentGpio_write(0);
    enableHkSpi(0);
    User_enableIF();

    if ((read_x1_direct(8, 9) & 1u) != 0u) ok = 0u;

    USER_writeWord(X1_MODE_PROGRAM | X1_ROW(8) | X1_COL(9) | 1u, X1_DIRECT_OFFSET_WORD);
    dummyDelay(500);
    if ((read_x1_direct(8, 9) & 1u) != 0u) ok = 0u;

    USER_writeWord(X1_MODE_PROGRAM | X1_ROW(8) | X1_COL(9) | 0xFFu, X1_DIRECT_OFFSET_WORD);
    dummyDelay(500);
    if ((read_x1_direct(8, 9) & 1u) != 1u) ok = 0u;

    USER_writeWord(X1_MODE_PROGRAM | X1_ROW(8) | X1_COL(9), X1_DIRECT_OFFSET_WORD);
    dummyDelay(500);
    if ((read_x1_direct(8, 9) & 1u) != 0u) ok = 0u;

    USER_writeWord(X1_MODE_FORM_A | X1_ROW(10) | X1_COL(11) | 0xFFu, X1_DIRECT_OFFSET_WORD);
    dummyDelay(500);
    if ((read_x1_direct(10, 11) & 1u) != 0u) ok = 0u;

    USER_writeWord(X1_MODE_PROGRAM | X1_ROW(12) | X1_COL(13) | 1u, X1_MATRIX_OFFSET_WORD);
    dummyDelay(500);
    if ((read_x1_matrix(12, 13) & 1u) != 1u) ok = 0u;

    ManagmentGpio_write(ok ? 1 : 0);
    while (1);
}
