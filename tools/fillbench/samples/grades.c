#include <stdio.h>
#include <stdlib.h>

#define NUM_STUDENTS 5

int sum_grades(int grades[], int count) {
    int total = 0;
    for (int i = 0; i < count; i++) {
        total += grades[i];
    }
    return total;
}

int highest_grade(int grades[], int count) {
    int highest = grades[0];
    for (int i = 1; i < count; i++) {
        if (grades[i] > highest) {
            highest = grades[i];
        }
    }
    return highest;
}

void print_grades(int grades[], int count) {
    for (int i = 0; i < count; i++) {
        printf("Student %d: %d\n", i + 1, grades[i]);
    }
}

int main(void) {
    int grades[NUM_STUDENTS];
    for (int i = 0; i < NUM_STUDENTS; i++) {
        printf("Enter grade for student %d: ", i + 1);
        scanf("%d", &grades[i]);
    }
    print_grades(grades, NUM_STUDENTS);
    printf("Average: %.2f\n", (double)sum_grades(grades, NUM_STUDENTS) / NUM_STUDENTS);
    printf("Highest: %d\n", highest_grade(grades, NUM_STUDENTS));
    return 0;
}
