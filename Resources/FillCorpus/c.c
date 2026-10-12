#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <math.h>
#include <time.h>

#define MAX_SIZE 100
#define BUFFER_SIZE 256

typedef struct {
    int x;
    int y;
} Point;

typedef struct {
    char name[50];
    int age;
    float grade;
} Student;

typedef struct Node {
    int data;
    struct Node *next;
} Node;

int factorial(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

int fibonacci(int n) {
    if (n <= 1) {
        return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

int fibonacci_iterative(int n) {
    int a = 0, b = 1;
    for (int i = 0; i < n; i++) {
        int temp = a + b;
        a = b;
        b = temp;
    }
    return a;
}

bool is_prime(int n) {
    if (n < 2) {
        return false;
    }
    for (int i = 2; i * i <= n; i++) {
        if (n % i == 0) {
            return false;
        }
    }
    return true;
}

int gcd(int a, int b) {
    while (b != 0) {
        int temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

int lcm(int a, int b) {
    return a / gcd(a, b) * b;
}

int power(int base, int exponent) {
    int result = 1;
    for (int i = 0; i < exponent; i++) {
        result *= base;
    }
    return result;
}

void swap(int *a, int *b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

int sum_array(int arr[], int size) {
    int sum = 0;
    for (int i = 0; i < size; i++) {
        sum += arr[i];
    }
    return sum;
}

double average(int arr[], int size) {
    if (size == 0) {
        return 0.0;
    }
    return (double)sum_array(arr, size) / size;
}

int find_max(int arr[], int size) {
    int max = arr[0];
    for (int i = 1; i < size; i++) {
        if (arr[i] > max) {
            max = arr[i];
        }
    }
    return max;
}

int find_min(int arr[], int size) {
    int min = arr[0];
    for (int i = 1; i < size; i++) {
        if (arr[i] < min) {
            min = arr[i];
        }
    }
    return min;
}

void print_array(int arr[], int size) {
    for (int i = 0; i < size; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
}

void reverse_array(int arr[], int size) {
    for (int i = 0; i < size / 2; i++) {
        swap(&arr[i], &arr[size - 1 - i]);
    }
}

void bubble_sort(int arr[], int size) {
    for (int i = 0; i < size - 1; i++) {
        for (int j = 0; j < size - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                swap(&arr[j], &arr[j + 1]);
            }
        }
    }
}

void selection_sort(int arr[], int size) {
    for (int i = 0; i < size - 1; i++) {
        int min_index = i;
        for (int j = i + 1; j < size; j++) {
            if (arr[j] < arr[min_index]) {
                min_index = j;
            }
        }
        swap(&arr[i], &arr[min_index]);
    }
}

void insertion_sort(int arr[], int size) {
    for (int i = 1; i < size; i++) {
        int key = arr[i];
        int j = i - 1;
        while (j >= 0 && arr[j] > key) {
            arr[j + 1] = arr[j];
            j--;
        }
        arr[j + 1] = key;
    }
}

int binary_search(int arr[], int size, int target) {
    int low = 0;
    int high = size - 1;
    while (low <= high) {
        int mid = low + (high - low) / 2;
        if (arr[mid] == target) {
            return mid;
        } else if (arr[mid] < target) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return -1;
}

int linear_search(int arr[], int size, int target) {
    for (int i = 0; i < size; i++) {
        if (arr[i] == target) {
            return i;
        }
    }
    return -1;
}

int string_length(const char *str) {
    int length = 0;
    while (str[length] != '\0') {
        length++;
    }
    return length;
}

void reverse_string(char *str) {
    int length = strlen(str);
    for (int i = 0; i < length / 2; i++) {
        char temp = str[i];
        str[i] = str[length - 1 - i];
        str[length - 1 - i] = temp;
    }
}

bool is_palindrome(const char *str) {
    int left = 0;
    int right = strlen(str) - 1;
    while (left < right) {
        if (str[left] != str[right]) {
            return false;
        }
        left++;
        right--;
    }
    return true;
}

int count_vowels(const char *str) {
    int count = 0;
    for (int i = 0; str[i] != '\0'; i++) {
        char c = tolower(str[i]);
        if (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u') {
            count++;
        }
    }
    return count;
}

void to_upper(char *str) {
    for (int i = 0; str[i] != '\0'; i++) {
        str[i] = toupper(str[i]);
    }
}

Node *create_node(int data) {
    Node *node = malloc(sizeof(Node));
    if (node == NULL) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }
    node->data = data;
    node->next = NULL;
    return node;
}

void push_front(Node **head, int data) {
    Node *node = create_node(data);
    node->next = *head;
    *head = node;
}

void append(Node **head, int data) {
    Node *node = create_node(data);
    if (*head == NULL) {
        *head = node;
        return;
    }
    Node *current = *head;
    while (current->next != NULL) {
        current = current->next;
    }
    current->next = node;
}

void print_list(Node *head) {
    Node *current = head;
    while (current != NULL) {
        printf("%d -> ", current->data);
        current = current->next;
    }
    printf("NULL\n");
}

void free_list(Node *head) {
    while (head != NULL) {
        Node *next = head->next;
        free(head);
        head = next;
    }
}

double distance(Point a, Point b) {
    int dx = a.x - b.x;
    int dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
}

void print_student(const Student *student) {
    printf("Name: %s, Age: %d, Grade: %.2f\n", student->name, student->age, student->grade);
}

int *create_array(int size) {
    int *arr = malloc(size * sizeof(int));
    if (arr == NULL) {
        fprintf(stderr, "Allocation failed\n");
        exit(EXIT_FAILURE);
    }
    for (int i = 0; i < size; i++) {
        arr[i] = 0;
    }
    return arr;
}

void read_file(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        perror("Error opening file");
        return;
    }
    char line[BUFFER_SIZE];
    while (fgets(line, sizeof(line), file) != NULL) {
        printf("%s", line);
    }
    fclose(file);
}

void write_file(const char *filename, const char *content) {
    FILE *file = fopen(filename, "w");
    if (file == NULL) {
        perror("Error opening file");
        return;
    }
    fprintf(file, "%s\n", content);
    fclose(file);
}

int read_int(const char *prompt) {
    int value;
    printf("%s", prompt);
    while (scanf("%d", &value) != 1) {
        printf("Invalid input. %s", prompt);
        while (getchar() != '\n');
    }
    return value;
}

void print_matrix(int rows, int cols, int matrix[rows][cols]) {
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            printf("%4d", matrix[i][j]);
        }
        printf("\n");
    }
}

void menu(void) {
    int choice;
    do {
        printf("1. Add\n2. List\n3. Quit\n");
        choice = read_int("Choose an option: ");
        switch (choice) {
            case 1:
                printf("Adding...\n");
                break;
            case 2:
                printf("Listing...\n");
                break;
            case 3:
                printf("Goodbye!\n");
                break;
            default:
                printf("Invalid choice\n");
        }
    } while (choice != 3);
}

int main(int argc, char *argv[]) {
    int numbers[] = {5, 3, 8, 1, 9, 2};
    int size = sizeof(numbers) / sizeof(numbers[0]);

    printf("Original: ");
    print_array(numbers, size);

    bubble_sort(numbers, size);
    printf("Sorted: ");
    print_array(numbers, size);

    printf("Max: %d\n", find_max(numbers, size));
    printf("Min: %d\n", find_min(numbers, size));
    printf("Average: %.2f\n", average(numbers, size));

    int index = binary_search(numbers, size, 8);
    if (index != -1) {
        printf("Found 8 at index %d\n", index);
    } else {
        printf("8 not found\n");
    }

    for (int i = 1; i <= 10; i++) {
        printf("%d! = %d\n", i, factorial(i));
    }

    char name[50];
    printf("Enter your name: ");
    scanf("%49s", name);
    printf("Hello, %s!\n", name);

    Node *list = NULL;
    for (int i = 0; i < 5; i++) {
        append(&list, i * 10);
    }
    print_list(list);
    free_list(list);

    srand(time(NULL));
    int random_number = rand() % 100 + 1;
    printf("Random number: %d\n", random_number);

    return 0;
}
