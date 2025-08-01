#include <assert.h>
#include <stdio.h>

int divide(int a, int b) {
    assert(a != 0);
    assert(b != 0);
    return a/b;
}

int main(void){
    printf("%d\n", divide(10, 2));
    printf("%d\n", divide(10, 0));
    return 0; 
}
