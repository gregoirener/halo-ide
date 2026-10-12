#include <stdio.h>

int square(int x) {
    int result = x * x;
    return result;
}

int main(void) {
    int total = 0;
    for (int i = 1; i <= 5; i++) {
        total += square(i);
    }
    printf("total = %d\n", total);
    return 0;
}
