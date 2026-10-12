import java.io.BufferedReader;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Scanner;
import java.util.Set;
import java.util.stream.Collectors;

public class Main {

    public static int factorial(int n) {
        if (n <= 1) {
            return 1;
        }
        return n * factorial(n - 1);
    }

    public static int fibonacci(int n) {
        if (n <= 1) {
            return n;
        }
        return fibonacci(n - 1) + fibonacci(n - 2);
    }

    public static boolean isPrime(int n) {
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

    public static int gcd(int a, int b) {
        while (b != 0) {
            int temp = b;
            b = a % b;
            a = temp;
        }
        return a;
    }

    public static int sum(int[] numbers) {
        int total = 0;
        for (int number : numbers) {
            total += number;
        }
        return total;
    }

    public static double average(int[] numbers) {
        if (numbers.length == 0) {
            return 0.0;
        }
        return (double) sum(numbers) / numbers.length;
    }

    public static int findMax(int[] numbers) {
        int max = numbers[0];
        for (int i = 1; i < numbers.length; i++) {
            if (numbers[i] > max) {
                max = numbers[i];
            }
        }
        return max;
    }

    public static int findMin(int[] numbers) {
        int min = numbers[0];
        for (int number : numbers) {
            if (number < min) {
                min = number;
            }
        }
        return min;
    }

    public static String reverseString(String str) {
        return new StringBuilder(str).reverse().toString();
    }

    public static boolean isPalindrome(String str) {
        String cleaned = str.toLowerCase().replaceAll("[^a-z0-9]", "");
        return cleaned.equals(new StringBuilder(cleaned).reverse().toString());
    }

    public static int countVowels(String str) {
        int count = 0;
        for (char c : str.toLowerCase().toCharArray()) {
            if ("aeiou".indexOf(c) != -1) {
                count++;
            }
        }
        return count;
    }

    public static Map<String, Integer> countWords(String text) {
        Map<String, Integer> counts = new HashMap<>();
        for (String word : text.toLowerCase().split("\\s+")) {
            counts.put(word, counts.getOrDefault(word, 0) + 1);
        }
        return counts;
    }

    public static int binarySearch(int[] arr, int target) {
        int low = 0;
        int high = arr.length - 1;
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

    public static void bubbleSort(int[] arr) {
        int n = arr.length;
        for (int i = 0; i < n - 1; i++) {
            for (int j = 0; j < n - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    int temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;
                }
            }
        }
    }

    public static void insertionSort(int[] arr) {
        for (int i = 1; i < arr.length; i++) {
            int key = arr[i];
            int j = i - 1;
            while (j >= 0 && arr[j] > key) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = key;
        }
    }

    public static void printArray(int[] arr) {
        for (int value : arr) {
            System.out.print(value + " ");
        }
        System.out.println();
    }

    public static List<String> readLines(String path) throws IOException {
        List<String> lines = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            String line;
            while ((line = reader.readLine()) != null) {
                lines.add(line);
            }
        }
        return lines;
    }

    public static void writeFile(String path, String content) throws IOException {
        try (FileWriter writer = new FileWriter(path)) {
            writer.write(content);
        }
    }

    public static void fizzBuzz(int n) {
        for (int i = 1; i <= n; i++) {
            if (i % 15 == 0) {
                System.out.println("FizzBuzz");
            } else if (i % 3 == 0) {
                System.out.println("Fizz");
            } else if (i % 5 == 0) {
                System.out.println("Buzz");
            } else {
                System.out.println(i);
            }
        }
    }

    public static void main(String[] args) {
        int[] numbers = {5, 3, 8, 1, 9, 2};
        System.out.println("Original: " + Arrays.toString(numbers));

        bubbleSort(numbers);
        System.out.println("Sorted: " + Arrays.toString(numbers));
        System.out.println("Sum: " + sum(numbers));
        System.out.println("Average: " + average(numbers));
        System.out.println("Max: " + findMax(numbers));

        for (int i = 0; i < 10; i++) {
            System.out.println(i + "! = " + factorial(i));
        }

        List<String> names = new ArrayList<>();
        names.add("Alice");
        names.add("Bob");
        names.add("Carol");
        for (String name : names) {
            System.out.println("Hello, " + name);
        }

        Map<String, Integer> ages = new HashMap<>();
        ages.put("Alice", 30);
        ages.put("Bob", 25);
        for (Map.Entry<String, Integer> entry : ages.entrySet()) {
            System.out.println(entry.getKey() + " is " + entry.getValue());
        }

        List<Integer> evens = Arrays.stream(numbers)
                .filter(n -> n % 2 == 0)
                .boxed()
                .collect(Collectors.toList());
        System.out.println("Evens: " + evens);

        Scanner scanner = new Scanner(System.in);
        System.out.print("Enter your name: ");
        String input = scanner.nextLine();
        System.out.println("Hello, " + input + "!");
        System.out.print("Enter a number: ");
        int number = scanner.nextInt();
        System.out.println(number + " is " + (isPrime(number) ? "prime" : "not prime"));
        scanner.close();

        try {
            int result = 10 / 0;
        } catch (ArithmeticException e) {
            System.out.println("Error: " + e.getMessage());
        } finally {
            System.out.println("Done");
        }
    }
}

class Person {
    private String name;
    private int age;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public boolean isAdult() {
        return age >= 18;
    }

    @Override
    public String toString() {
        return "Person{name='" + name + "', age=" + age + "}";
    }
}

class BankAccount {
    private final String owner;
    private double balance;

    public BankAccount(String owner, double balance) {
        this.owner = owner;
        this.balance = balance;
    }

    public void deposit(double amount) {
        if (amount <= 0) {
            throw new IllegalArgumentException("Deposit must be positive");
        }
        balance += amount;
    }

    public void withdraw(double amount) {
        if (amount > balance) {
            throw new IllegalStateException("Insufficient funds");
        }
        balance -= amount;
    }

    public double getBalance() {
        return balance;
    }

    public String getOwner() {
        return owner;
    }
}

interface Shape {
    double area();
    double perimeter();
}

class Circle implements Shape {
    private final double radius;

    public Circle(double radius) {
        this.radius = radius;
    }

    @Override
    public double area() {
        return Math.PI * radius * radius;
    }

    @Override
    public double perimeter() {
        return 2 * Math.PI * radius;
    }
}

class Rectangle implements Shape {
    private final double width;
    private final double height;

    public Rectangle(double width, double height) {
        this.width = width;
        this.height = height;
    }

    @Override
    public double area() {
        return width * height;
    }

    @Override
    public double perimeter() {
        return 2 * (width + height);
    }
}

abstract class Animal {
    protected String name;

    public Animal(String name) {
        this.name = name;
    }

    public abstract String speak();
}

class Dog extends Animal {
    public Dog(String name) {
        super(name);
    }

    @Override
    public String speak() {
        return name + " says Woof!";
    }
}

class Node<T> {
    T data;
    Node<T> next;

    Node(T data) {
        this.data = data;
        this.next = null;
    }
}

class Stack<T> {
    private final LinkedList<T> items = new LinkedList<>();

    public void push(T item) {
        items.addFirst(item);
    }

    public T pop() {
        if (items.isEmpty()) {
            throw new RuntimeException("Stack is empty");
        }
        return items.removeFirst();
    }

    public T peek() {
        return items.getFirst();
    }

    public boolean isEmpty() {
        return items.isEmpty();
    }

    public int size() {
        return items.size();
    }
}
